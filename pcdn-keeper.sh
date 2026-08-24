#!/bin/sh
echo "pcdn‑keeper｜脚本位置：/app/data/pcdn‑keeper.sh"
# ====================== 配置区 ======================
MAX_PARALLEL=3
RUN_TIMES_MIN=1
RUN_TIMES_MAX=3
SLEEP_MIN=2
SLEEP_MAX=3000
CURL_MAX_TIME=800
CURL_CONNECT_TIMEOUT=15
# 单任务最大限速，单位 k/s，0不限速
CURL_MAX_RATE="0"
# 每个任务启动间隔(毫秒)，busybox usleep
TASK_SPAWN_DELAY_MS=300
# cron时间窗口：分 时 日 月 周
RUN_CRON="* * * * *"
URL_POOL="
http://updates-http.cdn-apple.com/2019WinterFCS/fullrestores/041-39257/32129B6C-292C-11E9-9E72-4511412B0A59/iPhone_4.7_12.1.4_16D57_Restore.ipsw
"
CURL_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
LOG_MAX_BYTES=$((500*1024*1024))
# ====================================================
DATA_DIR="/app/data"
STAT_FILE="${DATA_DIR}/traffic.stat"
LOG_FILE="${DATA_DIR}/run.log"
TMP_LOG_DIR="/tmp/curl_task_log"

mkdir -p "${DATA_DIR}"
mkdir -p "${TMP_LOG_DIR}"

on_exit() {
    pkill -f "curl --no-progress-meter" 2>/dev/null || true
    echo "${TOTAL_BYTES}" > "${STAT_FILE}"
    echo ""
    echo "$(date +'%F %T') 程序退出，已保存统计"
    exit 0
}
trap on_exit SIGINT SIGTERM

rotate_log(){
    if [ -f "${LOG_FILE}" ];then
        log_size=$(stat -c%s "${LOG_FILE}")
        if [ "$log_size" -gt "${LOG_MAX_BYTES}" ];then
            echo "$(date +'%F %T') Log size exceed limit, truncate log" > "${LOG_FILE}"
        fi
    fi
}

TOTAL_BYTES=0
if [ -f "${STAT_FILE}" ]; then
    READ_VAL=$(cat "${STAT_FILE}")
    if echo "${READ_VAL}" | grep -q '^[0-9]\+$'; then
        TOTAL_BYTES=${READ_VAL}
    else
        echo "$(date +'%F %T') WARN stat file invalid, reset total bytes to 0" | tee -a "${LOG_FILE}"
        TOTAL_BYTES=0
    fi
fi

save_stat() {
    echo "${TOTAL_BYTES}" > "${STAT_FILE}"
}

human_size() {
    local bytes=$1
    if [ "$bytes" -lt $((1024*1024)) ]; then
        echo "$((bytes/1024)) KB"
    elif [ "$bytes" -lt $((1024*1024*1024)) ]; then
        echo "$(( bytes / 1024 / 1024 )) MB"
    else
        echo "$(( bytes / 1024 / 1024 / 1024 )) GB"
    fi
}

pick_random_url(){
    url_list=$(echo "$URL_POOL" | awk 'NF')
    count=$(echo "$url_list" | wc -l)
    if [ "$count" -eq 0 ];then
        echo ""
        return
    fi
    rand_idx=$(echo | awk -v c="$count" '{srand(); print int(rand()*c)+1}')
    echo "$url_list" | sed -n "${rand_idx}p"
}

check_cron_match(){
    cron_expr="$1"
    cur_min=$(date +%M)
    cur_hour=$(date +%H)
    cur_day=$(date +%d)
    cur_month=$(date +%m)
    cur_wday=$(date +%w)
    read c_min c_hour c_day c_month c_wday <<EOF
$cron_expr
EOF
    match_field(){
        f_now="$1"
        f_rule="$2"
        if [ "$f_rule" = "*" ];then return 0;fi
        if echo "$f_now" | awk -v r="$f_rule" '$0 ~ "^"r"$" || ($0 >= split(r,"-",a)[1] && $0 <= a[2]){exit 0}END{exit 1}';then
            return 0
        fi
        return 1
    }
    match_field "$cur_min" "$c_min" || return 1
    match_field "$cur_hour" "$c_hour" || return 1
    match_field "$cur_day" "$c_day" || return 1
    match_field "$cur_month" "$c_month" || return 1
    match_field "$cur_wday" "$c_wday" || return 1
    return 0
}

while true; do
    rotate_log
    if ! check_cron_match "${RUN_CRON}";then
        echo "$(date +'%F %T') 当前不在cron运行窗口，空闲休眠60s" | tee -a "${LOG_FILE}"
        sleep 60
        continue
    fi

    RUN_TIMES=$(echo | awk -v min="$RUN_TIMES_MIN" -v max="$RUN_TIMES_MAX" '{srand(); print int(rand()*(max-min+1)) + min}')

    echo "==================================================" | tee -a "${LOG_FILE}"
    echo "$(date +'%F %T'): 本轮开启${RUN_TIMES}组，最大并发${MAX_PARALLEL}" | tee -a "${LOG_FILE}"
    ROUND_BYTES=0
    SUCCESS_CNT=0
    FAIL_CNT=0
    i=0
    while [ ${i} -lt ${RUN_TIMES} ]; do
        TASK_ID=$((i+1))
        TASK_LOG="${TMP_LOG_DIR}/task_${TASK_ID}.log"
        rm -f "${TASK_LOG}"
        TARGET_URL=$(pick_random_url)
        if [ -z "${TARGET_URL}" ];then
            echo "$(date +'%F %T') ERROR URL_POOL is empty, sleep 30s" | tee -a "${LOG_FILE}"
            sleep 30
            continue 2
        fi
        echo "$(date +'%F %T'): [任务${TASK_ID}] 启动 ${TARGET_URL}" | tee -a "${LOG_FILE}"
        (
            curl --no-progress-meter \
                --max-time "${CURL_MAX_TIME}" \
                --connect-timeout "${CURL_CONNECT_TIMEOUT}" \
                -A "${CURL_USER_AGENT}" \
                -o /dev/null \
                --max-rate "${CURL_MAX_RATE}" \
                -w "TASK_RESULT|%{size_download}|%{http_code}\n" \
                "${TARGET_URL}" >"${TASK_LOG}" 2>&1
        ) &
        while [ $(jobs | wc -l) -ge ${MAX_PARALLEL} ]; do
            sleep 0.1
        done
        usleep "${TASK_SPAWN_DELAY_MS}"
        i=$((i+1))
    done

    echo "$(date +'%F %T'): 等待全部后台任务完成..." | tee -a "${LOG_FILE}"
    wait

    j=0
    while [ ${j} -lt ${RUN_TIMES} ]; do
        TASK_ID=$((j+1))
        TASK_LOG="${TMP_LOG_DIR}/task_${TASK_ID}.log"
        SIZE_DOWN=0
        HTTP_CODE=0
        if [ -f "${TASK_LOG}" ];then
            line=$(grep "TASK_RESULT" "${TASK_LOG}" || true)
            if [ -n "$line" ];then
                SIZE_DOWN=$(echo "$line" | cut -d'|' -f2)
                HTTP_CODE=$(echo "$line" | cut -d'|' -f3)
            fi
            # 打印curl原始输出，方便排错
            echo "$(date +'%F %T') [任务${TASK_ID}] RAW_LOG: $(cat "${TASK_LOG}")" | tee -a "${LOG_FILE}"
            if echo "${SIZE_DOWN}" | grep -q '^[0-9]\+$';then
                ROUND_BYTES=$(( ROUND_BYTES + SIZE_DOWN ))
            fi
            # http_code=0直接判定失败
            if [ "$HTTP_CODE" -gt 0 ] && [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ];then
                SUCCESS_CNT=$((SUCCESS_CNT+1))
            else
                FAIL_CNT=$((FAIL_CNT+1))
            fi
            echo "$(date +'%F %T') [任务${TASK_ID}] http_code:${HTTP_CODE},download_bytes:${SIZE_DOWN}" | tee -a "${LOG_FILE}"
        fi
        rm -f "${TASK_LOG}"
        j=$((j+1))
    done

    TOTAL_BYTES=$(( TOTAL_BYTES + ROUND_BYTES ))
    save_stat
    ROUND_HUMAN=$(human_size ${ROUND_BYTES})
    TOTAL_HUMAN=$(human_size ${TOTAL_BYTES})
    echo ">>>>>>>>>> 本轮：成功${SUCCESS_CNT} 失败${FAIL_CNT}，本轮下载流量：${ROUND_HUMAN}" | tee -a "${LOG_FILE}"
    echo ">>>>>>>>>> 程序累计总下载流量：${TOTAL_HUMAN} (${TOTAL_BYTES} 字节)" | tee -a "${LOG_FILE}"

    SLEEP_SEC=$(echo | awk -v min="$SLEEP_MIN" -v max="$SLEEP_MAX" '{srand(); print int(rand()*(max-min+1)) + min}')
    echo "$(date +'%F %T'): 本轮结束，休眠${SLEEP_SEC}秒" | tee -a "${LOG_FILE}"
    echo "==================================================" | tee -a "${LOG_FILE}"
    sleep ${SLEEP_SEC}
done
