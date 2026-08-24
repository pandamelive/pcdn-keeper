#!/bin/bash
set -e

# ==========配置项==========
RPC_PORT=6800
MAX_SPLIT=16
PIECE_LENGTH="1M"
SLEEP_AFTER_TASK=20
# 苹果CDN IPSW固件，http大文件测试
URL_LIST=(
"http://updates-http.cdn-apple.com/2019WinterFCS/fullrestores/041-39257/32129B6C-292C-11E9-9E72-4511412B0A59/iPhone_4.7_12.1.4_16D57_Restore.ipsw"
)
# =========================

# 启动 aria2 RPC，关闭mmap、限制分片块大小
aria2c \
  --enable-rpc \
  --rpc-listen-all=true \
  --rpc-listen-port="${RPC_PORT}" \
  --split="${MAX_SPLIT}" \
  --max-connection-per-server="${MAX_SPLIT}" \
  --piece-length="${PIECE_LENGTH}" \
  --max-mmap-limit=0 \
  --log-level=warn \
  --quiet &
ARIA2_PID=$!
sleep 2

RPC_URL="http://127.0.0.1:${RPC_PORT}/jsonrpc"
TOTAL_TRAFFIC=0

# JSON‑RPC调用封装
rpc_call(){
  local METHOD="$1"
  shift
  curl -s "${RPC_URL}" \
  -H "Content-Type:application/json" \
  -d "$(jq -n \
    --arg method "$METHOD" \
    --argjson params "$(printf '%s' "$*" | jq -s '.')" \
    '{jsonrpc:"2.0",id:1,method:$method,params:$params}')"
}

# 信号捕获，优雅停止aria2
trap 'kill ${ARIA2_PID}; echo -e "\n程序退出"; exit 0' SIGINT SIGTERM

while true; do
  for DL_URL in "${URL_LIST[@]}"; do
    echo "========================================"
    echo "开始下载: ${DL_URL}"

    # 提交任务 out=/dev/null 不落盘
    RESP=$(rpc_call aria2.addUri "[\"${DL_URL}\"]" '{"out":"/dev/null"}')
    GID=$(echo "$RESP" | jq -r '.result')
    echo "任务GID: $GID"

    # 轮询下载进度
    while true; do
      RET=$(rpc_call aria2.tellStatus "\"${GID}\"" '["totalLength","completedLength","downloadSpeed","status"]')
      STATUS=$(echo "$RET" | jq -r '.result.status')
      TOTAL=$(echo "$RET" | jq -r '.result.totalLength')
      COMPLETED=$(echo "$RET" | jq -r '.result.completedLength')
      SPEED=$(echo "$RET" | jq -r '.result.downloadSpeed')

      COMP_MB=$(echo "$COMPLETED" | awk '{printf "%.2f", $1/1024/1024}')
      TOTAL_MB=$(echo "$TOTAL" | awk '{printf "%.2f", $1/1024/1024}')
      SPEED_MB=$(echo "$SPEED" | awk '{printf "%.2f", $1/1024/1024}')

      echo -ne "\r进度: ${COMP_MB}/${TOTAL_MB} MB | 速度: ${SPEED_MB} MB/s"

      if [[ "$STATUS" == "complete" || "$STATUS" == "error" || "$STATUS" == "removed" ]]; then
        break
      fi
      sleep 0.8
    done

    echo ""
    if [[ "$STATUS" == "complete" ]]; then
      TOTAL_TRAFFIC=$(( TOTAL_TRAFFIC + COMPLETED ))
      TRAFFIC_MB=$(echo "$TOTAL_TRAFFIC" | awk '{printf "%.2f", $1/1024/1024}')
      echo "✅任务完成，累计总流量：${TRAFFIC_MB} MB"
    else
      echo "❌任务失败 status=${STATUS}"
    fi

    # 清理任务元数据，防止内存泄漏
    rpc_call aria2.removeDownloadResult "\"${GID}\"" >/dev/null
    echo "休眠 ${SLEEP_AFTER_TASK}s ..."
    sleep "${SLEEP_AFTER_TASK}"
  done
done

wait
