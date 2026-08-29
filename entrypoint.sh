#!/bin/bash
set -e

# ========== 环境变量 ==========
PK_LISTEN="${PK_LISTEN:-0.0.0.0:5566}"
PK_TOKEN="${PK_TOKEN:-}"
SPDE_MASTER="${SPDE_MASTER:-http://127.0.0.1:5566}"
MAX_RESTART="${MAX_RESTART:-5}"
RESTART_INTERVAL=3
HEALTH_CHECK_INTERVAL=2

PK_BIN="/pnos/controlcentre/pk"
SPDE_BIN="/pnos/download/spde"
PK_WORK_DIR="/pnos/controlcentre/pk-controlcenter"

# 日志函数（带时间戳）
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "======================================="
log " pcdn-keeper (pk + spde minimal combo)"
log " pk binary:     ${PK_BIN}"
log " pk work dir:   ${PK_WORK_DIR}"
log " spde binary:   ${SPDE_BIN}"
log " max restart:   ${MAX_RESTART} 次/服务"
log "======================================="

# 确保 pk 工作目录存在
mkdir -p "${PK_WORK_DIR}"

# pk 配置不存在时复制默认配置
if [ ! -f "${PK_WORK_DIR}/config.yaml" ]; then
    cp /pnos/pk-config.default.yaml "${PK_WORK_DIR}/config.yaml"
    log "[init] 创建默认 pk 配置: ${PK_WORK_DIR}/config.yaml"
fi

# 环境变量 PK_TOKEN 非空时覆盖配置文件中的 token
if [ -n "${PK_TOKEN}" ]; then
    sed -i "s/^token:.*/token: \"${PK_TOKEN}\"/" "${PK_WORK_DIR}/config.yaml"
    log "[init] 已从环境变量设置 PK_TOKEN"
fi

# 检测 dry_run 配置，落盘下载时警告内存风险
if grep -qE '^\s*dry_run:\s*false' "${PK_WORK_DIR}/config.yaml"; then
    log "[warn] ======================================="
    log "[warn]  dry_run=false：下载数据将实际写入 /tmp"
    log "[warn]  /tmp 为 tmpfs 内存文件系统，大文件可能占满容器内存"
    log "[warn] ======================================="
fi

# ========== 版本号检测 ==========
# clap 输出格式固定: "pk 1.1" / "spde 1.1"，取最后一个字段即可
extract_version() {
    "$1" --version 2>&1 | awk '{print $NF}' | tr -d 'vV[:space:]'
}

BUILD_PK_VERSION="${PK_VERSION:-unknown}"
BUILD_SPDE_VERSION="${SPDE_VERSION:-unknown}"
log "[init] 构建时版本号: pk=${BUILD_PK_VERSION}, spde=${BUILD_SPDE_VERSION}"

set +e
RUNTIME_PK_VERSION=$(extract_version "${PK_BIN}")
RUNTIME_SPDE_VERSION=$(extract_version "${SPDE_BIN}")
set -e

log "[init] 运行时提取版本号: pk=${RUNTIME_PK_VERSION}, spde=${RUNTIME_SPDE_VERSION}"

# 优先用运行时版本号，无效则回退到构建时版本号
PK_VERSION="${RUNTIME_PK_VERSION:-${BUILD_PK_VERSION}}"
SPDE_VERSION="${RUNTIME_SPDE_VERSION:-${BUILD_SPDE_VERSION}}"

if [ "${PK_VERSION}" = "unknown" ] || [ -z "${PK_VERSION}" ]; then
    PK_VERSION="${BUILD_PK_VERSION}"
fi
if [ "${SPDE_VERSION}" = "unknown" ] || [ -z "${SPDE_VERSION}" ]; then
    SPDE_VERSION="${BUILD_SPDE_VERSION}"
fi

PCDN_KEEPER_VERSION="pk-v${PK_VERSION}_spde-v${SPDE_VERSION}"
export PK_VERSION SPDE_VERSION PCDN_KEEPER_VERSION
log "[init] 版本标识: ${PCDN_KEEPER_VERSION}"

# ========== 进程管理 ==========
PK_PID=""
SPDE_PID=""
PK_RESTART_COUNT=0
SPDE_RESTART_COUNT=0

is_alive() {
    kill -0 "$1" 2>/dev/null
}

start_pk() {
    log "[supervisor] 启动 pk 主控..."
    "${PK_BIN}" serve --listen "${PK_LISTEN}" &
    PK_PID=$!
    log "[supervisor] pk pid=${PK_PID}"
}

# spde 数据目录持久化（node-id.json、运行历史等）
SPDE_DATA_DIR="/pnos/download/data"
SPDE_DATA_PERSIST="${PK_WORK_DIR}/spde-data"

ensure_spde_data_persist() {
    mkdir -p "${SPDE_DATA_PERSIST}"
    if [ ! -L "${SPDE_DATA_DIR}" ]; then
        if [ -d "${SPDE_DATA_DIR}" ] && [ ! -L "${SPDE_DATA_DIR}" ]; then
            log "[init] 迁移 spde data 目录到持久化位置..."
            cp -rn "${SPDE_DATA_DIR}/." "${SPDE_DATA_PERSIST}/" 2>/dev/null || true
            rm -rf "${SPDE_DATA_DIR}"
        fi
        mkdir -p "$(dirname "${SPDE_DATA_DIR}")"
        ln -sf "${SPDE_DATA_PERSIST}" "${SPDE_DATA_DIR}"
        log "[init] spde data 目录已持久化: ${SPDE_DATA_DIR} -> ${SPDE_DATA_PERSIST}"
    fi
}

start_spde() {
    log "[supervisor] 启动 spde agent..."
    ensure_spde_data_persist
    local args="agent --master ${SPDE_MASTER}"
    if [ -n "${PK_TOKEN}" ]; then
        args="${args} --token ${PK_TOKEN}"
    fi
    # 子 shell 中切换目录启动，不影响当前 shell
    (cd /pnos/download && "${SPDE_BIN}" ${args}) &
    SPDE_PID=$!
    log "[supervisor] spde pid=${SPDE_PID}"
}

# 从 PK_LISTEN 提取端口，动态构造健康检查地址
wait_pk_ready() {
    local pk_port="${PK_LISTEN##*:}"
    log "[supervisor] 等待 pk 服务就绪（端口 ${pk_port}）..."
    for i in $(seq 1 30); do
        if curl -sf "http://127.0.0.1:${pk_port}/api/v1/overview" >/dev/null 2>&1; then
            log "[supervisor] pk 服务已就绪"
            return 0
        fi
        sleep 1
    done
    log "[supervisor] 警告：pk 30秒内未就绪，继续启动 spde"
    return 1
}

# 信号捕获，优雅退出
cleanup() {
    echo ""
    log "[shutdown] 收到退出信号，停止所有服务..."
    kill "${PK_PID}" "${SPDE_PID}" 2>/dev/null || true
    wait 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM

# ---------- 初始启动 ----------
start_pk
wait_pk_ready
start_spde

log "======================================="
log " 所有服务已启动"
log " Web UI:  http://<host>:${PK_LISTEN##*:}"
log " pk pid:   ${PK_PID}"
log " spde pid: ${SPDE_PID}"
log "======================================="

# ---------- 监控循环 ----------
set +e
while true; do
    sleep "${HEALTH_CHECK_INTERVAL}"

    # 检查 pk
    if ! is_alive "${PK_PID}"; then
        PK_RESTART_COUNT=$((PK_RESTART_COUNT + 1))
        log "[supervisor] pk 已退出（pid=${PK_PID}），第 ${PK_RESTART_COUNT}/${MAX_RESTART} 次重启"

        if [ "${PK_RESTART_COUNT}" -ge "${MAX_RESTART}" ]; then
            log "[supervisor] pk 连续重启 ${MAX_RESTART} 次失败，退出容器交由 docker 重启..."
            kill "${SPDE_PID}" 2>/dev/null || true
            exit 1
        fi

        sleep "${RESTART_INTERVAL}"
        start_pk
        wait_pk_ready
    else
        PK_RESTART_COUNT=0
    fi

    # 检查 spde
    if ! is_alive "${SPDE_PID}"; then
        SPDE_RESTART_COUNT=$((SPDE_RESTART_COUNT + 1))
        log "[supervisor] spde 已退出（pid=${SPDE_PID}），第 ${SPDE_RESTART_COUNT}/${MAX_RESTART} 次重启"

        if [ "${SPDE_RESTART_COUNT}" -ge "${MAX_RESTART}" ]; then
            log "[supervisor] spde 连续重启 ${MAX_RESTART} 次失败，退出容器交由 docker 重启..."
            kill "${PK_PID}" 2>/dev/null || true
            exit 1
        fi

        sleep "${RESTART_INTERVAL}"
        start_spde
    else
        SPDE_RESTART_COUNT=0
    fi
done
