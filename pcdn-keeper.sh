#!/bin/sh
echo "流量保镖服务启动【curl低内存并发版】"

MAX_PARALLEL=4

TARGET_URL="http://updates-http.cdn-apple.com/2019WinterFCS/fullrestores/041-39257/32129B6C-292C-11E9-9E72-4511412B0A59/iPhone_4.7_12.1.4_16D57_Restore.ipsw"

while true; do
  RUN_TIMES=$(expr $RANDOM % 3 + 1)
  echo "$(date +'%F %T'): 本轮开启${RUN_TIMES}组，最大并发${MAX_PARALLEL}"

  i=0
  while [ ${i} -lt ${RUN_TIMES} ]; do
    curl \
      --no-progress-meter \
      --max-time 600 \
      --connect-timeout 15 \
      -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
      -o /dev/null \
      "${TARGET_URL}" 2>/dev/null &

    # 控制最大并发
    while [ $(jobs | wc -l) -ge ${MAX_PARALLEL} ]; do
      sleep 0.2
    done

    i=$(expr ${i} + 1)
  done

  wait
  RANDOM_SLEEP=$(expr $RANDOM % 3000 + 1)
  echo "$(date +'%F %T'): 本轮全部任务结束，休眠${RANDOM_SLEEP}秒"
  sleep ${RANDOM_SLEEP}
done
