#!/usr/bin/env bash
#
# 三网回程线路质量检测脚本
# 依赖: NextTrace (https://github.com/nxtrace/NTrace-core)
#
# 功能:
# - 自动检测 nexttrace 是否安装
# - 测试三条回程: 电信 / 联通 / 移动
# - 按特征 IP 进行评分
# - 输出单线结论 + 综合结论
# - 保存原始日志和分析报告

set -euo pipefail

TELECOM_IP="101.227.255.45"   # 上海电信
UNICOM_IP="202.106.0.20"      # 北京联通
MOBILE_IP="211.136.192.6"     # 广州移动

# 兼容 bash <(curl ...) 这种进程替换运行方式：
# BASH_SOURCE[0] 在这种场景下通常是 /dev/fd/63，不能当作真实目录使用。
# 所以日志和报告统一写到用户可写的状态目录；没有 HOME 时退回到 /tmp。
STATE_BASE="${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}"
LOG_DIR="$STATE_BASE/oneclick-scripts/nexttrace_logs"
mkdir -p "$LOG_DIR"

if ! command -v nexttrace >/dev/null 2>&1; then
    echo "[提示] 未检测到 NextTrace，开始自动安装..."
    if command -v curl >/dev/null 2>&1; then
        bash <(curl -fsSL https://raw.githubusercontent.com/nxtrace/NTrace-core/master/install.sh)
    elif command -v wget >/dev/null 2>&1; then
        tmp_installer="$(mktemp)"
        wget -qO "$tmp_installer" https://raw.githubusercontent.com/nxtrace/NTrace-core/master/install.sh
        bash "$tmp_installer"
        rm -f "$tmp_installer"
    else
        echo "[错误] 当前系统没有 curl 或 wget，无法自动安装 NextTrace。"
        echo "请先安装 curl/wget，或手动安装 NextTrace 后再运行。"
        exit 1
    fi
fi

if ! command -v nexttrace >/dev/null 2>&1; then
    echo "[错误] NextTrace 安装失败，请检查网络或手动安装后重试。"
    exit 1
fi

ts="$(date '+%Y%m%d_%H%M%S')"
REPORT_FILE="$LOG_DIR/report_$ts.txt"

declare -a TARGET_NAMES=("上海电信" "北京联通" "广州移动")
declare -a TARGET_IPS=("$TELECOM_IP" "$UNICOM_IP" "$MOBILE_IP")
declare -a TARGET_KEYS=("telecom" "unicom" "mobile")

echo "========================================"
echo "  三网回程线路质量检测"
echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

run_nexttrace() {
    local name="$1"
    local ip="$2"
    local log_file="$3"

    echo "---------- $name ($ip) ----------"
    if nexttrace -m 25 "$ip" 2>&1 | tee "$log_file"; then
        echo ""
    else
        echo "[警告] $name 测试过程返回非 0 状态，已保留原始输出供分析。"
        echo ""
    fi
}

classify_target() {
    local key="$1"
    local text="$2"

    local verdict="未知"
    local score=0
    local reason="未识别到明确特征 IP"

    case "$key" in
        telecom)
            if grep -qE '\b59\.43\.' <<< "$text"; then
                verdict="优质"
                score=3
                reason="命中 59.43.x.x，符合电信 CN2 GIA 特征"
            elif grep -qE '\b202\.97\.' <<< "$text"; then
                verdict="普通"
                score=1
                reason="命中 202.97.x.x，符合电信 163 普通骨干特征"
            elif grep -qE 'AS4812|CHINANET' <<< "$text"; then
                verdict="普通/待确认"
                score=1
                reason="可见电信骨干信息，但未出现 CN2 GIA 特征 IP"
            fi
            ;;
        unicom)
            if grep -qE '\b10099\.' <<< "$text"; then
                verdict="优质"
                score=3
                reason="命中 10099.x.x，符合联通 AS9929 特征"
            elif grep -qE '\b219\.158\.' <<< "$text"; then
                verdict="普通"
                score=1
                reason="命中 219.158.x.x，符合联通 4837 普通骨干特征"
            elif grep -qE 'AS4837|AS9929|CHINAUNICOM|UNICOM' <<< "$text"; then
                verdict="普通/待确认"
                score=1
                reason="可见联通信息，但未出现 9929 精品特征 IP"
            fi
            ;;
        mobile)
            if grep -qE '\b223\.120\.' <<< "$text"; then
                verdict="优质"
                score=3
                reason="命中 223.120.x.x，符合移动 CMIN2 特征"
            elif grep -qE '\b221\.183\.' <<< "$text"; then
                verdict="普通"
                score=1
                reason="命中 221.183.x.x，符合移动 CMI 普通线路特征"
            elif grep -qE 'AS9808|CMNET|10086' <<< "$text"; then
                verdict="普通/待确认"
                score=1
                reason="可见移动骨干信息，但未出现 CMIN2 精品特征 IP"
            fi
            ;;
    esac

    printf '%s|%s|%s|%s\n' "$verdict" "$score" "$reason" "$key"
}

declare -a SUMMARIES=()

for i in "${!TARGET_NAMES[@]}"; do
    name="${TARGET_NAMES[$i]}"
    ip="${TARGET_IPS[$i]}"
    key="${TARGET_KEYS[$i]}"
    log_file="$LOG_DIR/${key}_$ts.log"

    run_nexttrace "$name" "$ip" "$log_file"
    raw_text="$(cat "$log_file")"
    SUMMARIES+=("$(classify_target "$key" "$raw_text")")
done

echo "========================================"
echo "  线路分析报告"
echo "========================================"

total_score=0
premium_count=0
normal_count=0
unknown_count=0

for i in "${!TARGET_NAMES[@]}"; do
    name="${TARGET_NAMES[$i]}"
    IFS='|' read -r verdict score reason key <<< "${SUMMARIES[$i]}"
    total_score=$((total_score + score))

    case "$verdict" in
        优质)
            premium_count=$((premium_count + 1))
            ;;
        普通|普通/待确认)
            normal_count=$((normal_count + 1))
            ;;
        *)
            unknown_count=$((unknown_count + 1))
            ;;
    esac

    echo "  [$name] 结论: $verdict (得分: $score/3)"
    echo "      依据: $reason"
done

echo ""
echo "  综合得分: $total_score / 9"
echo ""

if (( premium_count >= 2 )); then
    overall="优秀线路"
    overall_text="三网中至少两网为精品特征，整体可认为是优质线路。"
elif (( premium_count == 1 && normal_count >= 2 )); then
    overall="中等线路"
    overall_text="有部分优质特征，但普通线路占比更高，日常可用但不算精品。"
elif (( premium_count == 0 && normal_count >= 1 )); then
    overall="普通线路"
    overall_text="未看到精品特征，且至少一条已明确为普通线路，整体偏普通。"
else
    overall="无法准确判断"
    overall_text="回程被过滤较多，特征 IP 不足，建议换探测方式或重复多次测试。"
fi

echo "  >>> 最终结论: $overall"
echo "      $overall_text"
echo ""
echo "  判定参考:"
echo "    - 电信优质: 59.43.x.x（CN2 GIA）"
echo "    - 联通优质: 10099.x.x（AS9929）"
echo "    - 移动优质: 223.120.x.x（CMIN2）"
echo "    - 电信普通: 202.97.x.x（163）"
echo "    - 联通普通: 219.158.x.x（4837）"
echo "    - 移动普通: 221.183.x.x（CMI）"
echo ""
echo "  原始日志已保存到: $LOG_DIR"
echo "  本次报告已保存到: $REPORT_FILE"
echo "========================================"

{
    echo "NextTrace 三网回程检测报告"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    for i in "${!TARGET_NAMES[@]}"; do
        name="${TARGET_NAMES[$i]}"
        IFS='|' read -r verdict score reason key <<< "${SUMMARIES[$i]}"
        echo "[$name]"
        echo "结论: $verdict"
        echo "得分: $score/3"
        echo "依据: $reason"
        echo ""
    done
    echo "综合结论: $overall"
    echo "综合说明: $overall_text"
    echo ""
    echo "备注: 线路判断以特征 IP 为主，若探测结果出现大量 '*'，说明中间回程可能被过滤，需结合多次测试和晚高峰表现一起判断。"
} > "$REPORT_FILE"
