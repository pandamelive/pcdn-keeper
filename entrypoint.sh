#!/bin/bash
set -e

# ========== 环境变量 ==========
# PK_LISTEN:    pk 监听地址，默认 0.0.0.0:5566
# PK_TOKEN:     pk API / agent 鉴权 token，默认空（不鉴权）
# SPDE_MASTER:  spde agent 连接的 pk 地址，默认 http://127.0.0.1:5566
# MAX_RESTART:  单个服务最大连续重启次数，超过后退出容器交由 docker 重启，默认 5
# ================================

PK_LISTEN="${PK_LISTEN:-0.0.0.0:5566}"
PK_TOKEN="${PK_TOKEN:-}"
SPDE_MASTER="${SPDE_MASTER:-http://127.0.0.1:5566}"
MAX_RESTART="${MAX_RESTART:-5}"
RESTART_INTERVAL=3
HEALTH_CHECK_INTERVAL=2

PK_BIN="/pnos/controlcentre/pk"
SPDE_BIN="/pnos/download/spde"
PK_WORK_DIR="/pnos/controlcentre/pk-controlcenter"

echo "========================================"
echo " pcdn-keeper (pk + spde minimal combo)"
echo " pk binary:     ${PK_BIN}"
echo " pk work dir:   ${PK_WORK_DIR}"
echo " spde binary:   ${SPDE_BIN}"
echo " download dir:  /tmp (tmpfs)"
echo " max restart:   ${MAX_RESTART} 次/服务"
echo "========================================"

# 确保 pk 工作目录存在
mkdir -p "${PK_WORK_DIR}"

# pk 配置不存在时复制默认配置（save_path 已指向 /tmp）
if [ ! -f "${PK_WORK_DIR}/config.yaml" ]; then
    cp /pnos/pk-config.default.yaml "${PK_WORK_DIR}/config.yaml"
    echo "[init] 已创建默认 pk 配置: ${PK_WORK_DIR}/config.yaml"
fi

# 环境变量 PK_TOKEN 非空时覆盖配置文件中的 token
if [ -n "${PK_TOKEN}" ]; then
    sed -i "s/^token:.*/token: \"${PK_TOKEN}\"/" "${PK_WORK_DIR}/config.yaml"
    echo "[init] 已从环境变量设置 PK_TOKEN"
fi

# 检测 dry_run 配置，落盘下载时警告内存风险
if grep -qE '^\s*dry_run:\s*false' "${PK_WORK_DIR}/config.yaml"; then
    echo "[warn] ===================================================="
    echo "[warn]  dry_run=false：下载数据将实际写入 /tmp"
    echo "[warn]  /tmp 为 tmpfs 内存文件系统，大文件可能占满容器内存"
    echo "[warn] ===================================================="
fi

# ========== 版本号检测 ==========
# 从二进制 --version 输出提取真实版本号
# 兼容多种输出格式: "pk 0.4.5" / "pk v0.4.5" / "pk version 0.4.5" / "0.4.5"
extract_version() {
    local bin=$1
    local output
    output=$("$bin" --version 2>&1 | tr -d '[:space:]')
    # 优先匹配语义化版本号（可选 v 前缀）
    local ver
    ver=$(echo "$output" | grep -oE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | sed 's/^v//')
    if [ -z "$ver" ]; then
        # 兜底：取最后一个空白分隔的字段
        ver=$(echo "$output" | awk '{print $NF}')
    fi
    echo "$ver"
}

# 保存构建时传入的版本号作为 fallback
BUILD_PK_VERSION="${PK_VERSION:-unknown}"
BUILD_SPDE_VERSION="${SPDE_VERSION:-unknown}"

# 从二进制获取真实版本号（set +e 防止 --version 返回非零导致脚本退出）
set +e
RUNTIME_PK_VERSION=$(extract_version "${PK_BIN}")
RUNTIME_SPDE_VERSION=$(extract_version "${SPDE_BIN}")
set -e

# 使用运行时版本号（如果获取成功），否则回退到构建时版本号
PK_VERSION="${RUNTIME_PK_VERSION:-${BUILD_PK_VERSION}}"
SPDE_VERSION="${RUNTIME_SPDE_VERSION:-${BUILD_SPDE_VERSION}}"

if [ -n "${PK_VERSION}" ] && [ -n "${SPDE_VERSION}" ] && [ "${PK_VERSION}" != "unknown" ] && [ "${SPDE_VERSION}" != "unknown" ]; then
    PCDN_KEEPER_VERSION="pk-v${PK_VERSION}_spde-v${SPDE_VERSION}"
    export PK_VERSION SPDE_VERSION PCDN_KEEPER_VERSION
    echo "[init] 版本标识: ${PCDN_KEEPER_VERSION}"
else
    echo "[warn] 无法获取 pk/spde 真实版本号（pk=${PK_VERSION}, spde=${SPDE_VERSION}），使用构建时 fallback"
    PCDN_KEEPER_VERSION="pk-v${BUILD_PK_VERSION}_spde-v${BUILD_SPDE_VERSION}"
    PK_VERSION="${BUILD_PK_VERSION}"
    SPDE_VERSION="${BUILD_SPDE_VERSION}"
    export PK_VERSION SPDE_VERSION PCDN_KEEPER_VERSION
fi

# ========== 进程管理 ==========
PK_PID=""
SPDE_PID=""
PK_RESTART_COUNT=0
SPDE_RESTART_COUNT=0

is_alive() {
    kill -0 "$1" 2>/dev/null
}

start_pk() {
    echo "[supervisor] 启动 pk 主控..."
    "${PK_BIN}" serve --listen "${PK_LISTEN}" &
    PK_PID=$!
    echo "[supervisor] pk pid=${PK_PID}"
}

# spde 数据目录持久化（node-id.json、运行历史等）
# 链接到 pk 的持久化目录下，确保容器重建后 node_id 不变
SPDE_DATA_DIR="/pnos/download/data"
SPDE_DATA_PERSIST="${PK_WORK_DIR}/spde-data"

ensure_spde_data_persist() {
    mkdir -p "${SPDE_DATA_PERSIST}"
    # 如果 data 目录不存在或不是符号链接，创建符号链接
    if [ ! -L "${SPDE_DATA_DIR}" ]; then
        # 如果已存在普通目录，先备份内容
        if [ -d "${SPDE_DATA_DIR}" ] && [ ! -L "${SPDE_DATA_DIR}" ]; then
            echo "[init] 迁移 spde data 目录到持久化位置..."
            cp -rn "${SPDE_DATA_DIR}/." "${SPDE_DATA_PERSIST}/" 2>/dev/null || true
            rm -rf "${SPDE_DATA_DIR}"
        fi
        mkdir -p "$(dirname "${SPDE_DATA_DIR}")"
        ln -sf "${SPDE_DATA_PERSIST}" "${SPDE_DATA_DIR}"
        echo "[init] spde data 目录已持久化: ${SPDE_DATA_DIR} -> ${SPDE_DATA_PERSIST}"
    fi
}

start_spde() {
    echo "[supervisor] 启动 spde agent..."
    # 确保 spde 数据目录持久化（node-id 不变）
    ensure_spde_data_persist
    local args="agent --master ${SPDE_MASTER}"
    if [ -n "${PK_TOKEN}" ]; then
        args="${args} --token ${PK_TOKEN}"
    fi
    # cd 到 spde 工作目录，确保 data 目录在正确位置
    cd /pnos/download
    "${SPDE_BIN}" ${args} &
    SPDE_PID=$!
    cd /  # 切回根目录，避免影响其他操作
    echo "[supervisor] spde pid=${SPDE_PID}"
}

wait_pk_ready() {
    echo "[supervisor] 等待 pk 服务就绪..."
    for i in $(seq 1 30); do
        if curl -sf "http://127.0.0.1:5566/api/v1/overview" >/dev/null 2>&1; then
            echo "[supervisor] pk 服务已就绪"
            return 0
        fi
        sleep 1
    done
    echo "[supervisor] 警告：pk 30秒内未就绪，继续启动 spde"
    return 1
}

# 信号捕获，优雅退出
cleanup() {
    echo ""
    echo "[shutdown] 收到退出信号，停止所有服务..."
    kill "${PK_PID}" "${SPDE_PID}" 2>/dev/null || true
    wait 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM

# ---------- 初始启动 ----------
start_pk
wait_pk_ready
start_spde

echo "========================================"
echo " 所有服务已启动"
echo " Web UI:  http://<host>:5566"
echo " pk pid:   ${PK_PID}"
echo " spde pid: ${SPDE_PID}"
echo "========================================"

# ---------- 监控循环 ----------
set +e
while true; do
    sleep "${HEALTH_CHECK_INTERVAL}"

    # 检查 pk
    if ! is_alive "${PK_PID}"; then
        PK_RESTART_COUNT=$((PK_RESTART_COUNT + 1))
        echo "[supervisor] pk 已退出（pid=${PK_PID}），第 ${PK_RESTART_COUNT}/${MAX_RESTART} 次重启"

        if [ "${PK_RESTART_COUNT}" -ge "${MAX_RESTART}" ]; then
            echo "[supervisor] pk 连续重启 ${MAX_RESTART} 次失败，退出容器交由 docker 重启..."
            kill "${SPDE_PID}" 2>/dev/null || true
            exit 1
        fi

        sleep "${RESTART_INTERVAL}"
        start_pk
        # pk 重启后等待就绪，spde 有自动重连机制无需强制重启
        wait_pk_ready
    else
        PK_RESTART_COUNT=0
    fi

    # 检查 spde
    if ! is_alive "${SPDE_PID}"; then
        SPDE_RESTART_COUNT=$((SPDE_RESTART_COUNT + 1))
        echo "[supervisor] spde 已退出（pid=${SPDE_PID}），第 ${SPDE_RESTART_COUNT}/${MAX_RESTART} 次重启"

        if [ "${SPDE_RESTART_COUNT}" -ge "${MAX_RESTART}" ]; then
            echo "[supervisor] spde 连续重启 ${MAX_RESTART} 次失败，退出容器交由 docker 重启..."
            kill "${PK_PID}" 2>/dev/null || true
            exit 1
        fi

        sleep "${RESTART_INTERVAL}"
        start_spde
    else
        SPDE_RESTART_COUNT=0
    fi
done
