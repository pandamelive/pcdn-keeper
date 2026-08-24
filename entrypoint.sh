#!/bin/bash
set -e

# ========== 环境变量 ==========
# LOOP_INTERVAL: 每轮下载完成后的休眠秒数，默认 20
# SPDE_BIN: spde 可执行文件路径
# ================================

SPDE_BIN="${SPDE_BIN:-/app/spde}"
LOOP_INTERVAL="${LOOP_INTERVAL:-20}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/tmp/downloads}"

echo "========================================"
echo " pcdn-keeper (spde edition) 启动"
echo " spde 二进制: ${SPDE_BIN}"
echo " 循环间隔: ${LOOP_INTERVAL}s"
echo " 下载目录: ${DOWNLOAD_DIR}"
echo " 配置文件: /app/spde-node/config/config.yaml"
echo "========================================"

# 信号捕获，优雅退出
cleanup() {
    echo ""
    echo "收到退出信号，正在停止..."
    exit 0
}
trap cleanup SIGINT SIGTERM

# 确保下载目录存在
mkdir -p "${DOWNLOAD_DIR}"

ROUND=0

while true; do
    ROUND=$((ROUND + 1))
    echo ""
    echo "========== 第 ${ROUND} 轮下载开始 =========="
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"

    # 执行 spde serve（一次性跑完配置中所有 enable=true 的任务）
    if "${SPDE_BIN}" serve; then
        echo "========== 第 ${ROUND} 轮下载完成 =========="
    else
        echo "⚠️  第 ${ROUND} 轮 spde 执行异常（退出码 $?），继续下一轮"
    fi

    # 清理下载文件，防止 tmpfs 占满
    if [ -d "${DOWNLOAD_DIR}" ] && [ "$(ls -A "${DOWNLOAD_DIR}" 2>/dev/null)" ]; then
        rm -rf "${DOWNLOAD_DIR:?}"/*
        echo "已清理下载目录"
    fi

    echo "休眠 ${LOOP_INTERVAL}s 后进入下一轮..."
    sleep "${LOOP_INTERVAL}"
done
