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

start_spde() {
    echo "[supervisor] 启动 spde agent..."
    local args="agent --master ${SPDE_MASTER}"
    if [ -n "${PK_TOKEN}" ]; then
        args="${args} --token ${PK_TOKEN}"
    fi
    "${SPDE_BIN}" ${args} &
    SPDE_PID=$!
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
