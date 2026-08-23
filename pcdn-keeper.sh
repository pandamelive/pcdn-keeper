#!/bin/sh
echo "流量保镖服务启动...开始平衡你的上下行比例"

while true; do
  RUN_TIMES=$(expr $RANDOM % 3 + 1)
  echo "$(date +'%F %T'): 本轮将连续执行${RUN_TIMES}次下载任务..."

  i=1
  while [ ${i} -le ${RUN_TIMES} ]; do
    echo "$(date +'%F %T'): 执行第${i}/${RUN_TIMES}次下载任务..."
    aria2c \
      --dir=/tmp \
      -o /dev/null \
      --max-connection-per-server=8 \
      --split=8 \
      --max-overall-download-limit=100M \
      --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
      --connect-timeout=15 \
      --timeout=600 \
      --retry-wait=10 \
      --max-tries=5 \
      --disk-cache=0 \
      --max-download-result=0 \
      --file-allocation=none \
      --quiet=true \
      "http://updates-http.cdn-apple.com/2019WinterFCS/fullrestores/041-39257/32129B6C-292C-11E9-9E72-4511412B0A59/iPhone_4.7_12.1.4_16D57_Restore.ipsw" || \
      echo "第${i}次下载异常，继续执行下一次..."

    i=$(expr ${i} + 1)
  done

  RANDOM_SLEEP=$(expr $RANDOM % 3000 + 1)
  echo "$(date +'%F %T'): 本轮${RUN_TIMES}次任务执行完毕，随机休息${RANDOM_SLEEP}秒..."
  sleep ${RANDOM_SLEEP}
done
