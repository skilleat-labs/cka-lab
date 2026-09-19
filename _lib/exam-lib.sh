#!/usr/bin/env bash
# ============================================================
# exam-lib.sh — 순차 진행형 시험 엔진
#
# 각 세트의 exam.sh 가 이 파일을 source 하고 아래를 정의한 뒤
# exam_main "$@" 를 호출한다.
#
#   EXAM_TITLE="..."          시험 제목
#   EXAM_NQ=3                 문제 수
#   exam_cleanup()            시험 리소스 전부 삭제 (원상복구)
#   exam_setup()              환경 준비 (네임스페이스, 고장 파드 등)
#   qN_title()                문제 제목 한 줄  (echo)
#   qN_text()                 문제 본문        (cat <<'EOF' ...)
#   qN_grade()                채점 — check / check_output 만 호출
#   qN_hint()                 (선택) 힌트
#
# 학생이 쓰는 명령:
#   bash exam.sh start    환경 준비 + Q1 출제
#   bash exam.sh show     현재 문제 다시 보기
#   bash exam.sh check    현재 문제 채점 → 만점이면 다음 문제로
#   bash exam.sh skip     현재 점수로 확정하고 다음으로
#   bash exam.sh hint     힌트 보기 (기록에 남음)
#   bash exam.sh status   진행 현황
#   bash exam.sh finish   최종 리포트
#   bash exam.sh clean    클러스터의 시험 리소스 삭제 + 진행 기록 삭제 (원상복구)
#   bash exam.sh reset    진행 기록만 삭제
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; ORANGE='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

EXAM_DIR="${EXAM_DIR:-$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)}"
WORK_DIR="$EXAM_DIR/work"
STATE="$WORK_DIR/.progress"
QLOG="$WORK_DIR/questions-so-far.txt"
mkdir -p "$WORK_DIR"

sep() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
thin() { echo -e "${DIM}──────────────────────────────────────────────────────────────${RESET}"; }

# ── 상태 파일 (key=value 한 줄씩) ────────────────────────────────
state_get() { [[ -f "$STATE" ]] && grep -E "^$1=" "$STATE" | tail -1 | cut -d= -f2- || true; }
state_set() {
  local k="$1" v="$2"
  [[ -f "$STATE" ]] && grep -vE "^$k=" "$STATE" > "$STATE.tmp" || true
  echo "$k=$v" >> "$STATE.tmp"; mv "$STATE.tmp" "$STATE"
}
now() { date +%s; }
fmt_dur() {
  local s="$1"; [[ -z "$s" || "$s" -lt 0 ]] && s=0
  printf '%d분 %02d초' $((s/60)) $((s%60))
}

# ── 채점 헬퍼 (qN_grade 안에서만 사용) ───────────────────────────
#   배점 없이 쓰면 항목 1개 = 1점, 마지막 인자로 배점을 주면 그 점수로 계산
#   check        desc cmd            [pts]
#   check_output desc cmd pattern    [pts]
#   check_result desc ok(0/1) [note] [pts]
Q_PASS=0; Q_TOTAL=0; Q_FAILS=()
EXAM_UNIT="${EXAM_UNIT:-항목}"   # 세트에서 EXAM_UNIT="점" 으로 바꾸면 리포트 단위가 바뀜
_pass() { local pts="$1"; Q_PASS=$((Q_PASS+pts)); }
_pts_label() { [[ "${EXAM_UNIT}" == "점" ]] && printf '[+%s점] ' "$1" || true; }
_zero_label() { [[ "${EXAM_UNIT}" == "점" ]] && printf '[ 0점] ' || true; }
check() {
  local desc="$1" cmd="$2" pts="${3:-1}"
  Q_TOTAL=$((Q_TOTAL+pts))
  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}[PASS]${RESET} $(_pts_label "$pts")$desc"; _pass "$pts"
  else
    echo -e "  ${RED}[FAIL]${RESET} $(_zero_label)$desc"; Q_FAILS+=("$desc")
  fi
}
check_output() {
  local desc="$1" cmd="$2" pattern="$3" pts="${4:-1}" out
  Q_TOTAL=$((Q_TOTAL+pts))
  out=$(eval "$cmd" 2>/dev/null || echo "")
  if echo "$out" | grep -qE "$pattern"; then
    echo -e "  ${GREEN}[PASS]${RESET} $(_pts_label "$pts")$desc"; _pass "$pts"
  else
    echo -e "  ${RED}[FAIL]${RESET} $(_zero_label)$desc  ${ORANGE}(기대: $pattern / 실제: '${out}')${RESET}"
    Q_FAILS+=("$desc")
  fi
}
# 직접 판정한 결과를 기록할 때 (복잡한 검사용)
check_result() {
  local desc="$1" ok="$2" note="${3:-}" pts="${4:-1}"
  Q_TOTAL=$((Q_TOTAL+pts))
  if [[ "$ok" == "0" ]]; then
    echo -e "  ${GREEN}[PASS]${RESET} $(_pts_label "$pts")$desc"; _pass "$pts"
  else
    echo -e "  ${RED}[FAIL]${RESET} $(_zero_label)$desc${note:+  ${ORANGE}($note)${RESET}}"; Q_FAILS+=("$desc")
  fi
}
# 파드 Ready 대기 (최대 40초) — 채점 전 안정화용. 파드가 없으면 즉시 반환
wait_ready() {
  local sel="$1" ns="${2:-default}" i
  [[ -z "$(kubectl get pods -n "$ns" $sel -o name 2>/dev/null)" ]] && return 1
  for i in $(seq 1 20); do
    local r; r=$(kubectl get pods -n "$ns" $sel -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | sort -u | tr -d '\n')
    [[ "$r" == "true" ]] && return 0
    sleep 2
  done
  return 1
}

# ── 진행바 ───────────────────────────────────────────────────────
progress_bar() {
  local cur="$1" i out=""
  for ((i=1;i<=EXAM_NQ;i++)); do
    local rec; rec=$(state_get "q$i")
    if [[ -n "$rec" ]]; then
      local p="${rec%%/*}" t="${rec#*/}"; t="${t%%:*}"
      [[ "$p" == "$t" ]] && out+="${GREEN}●${RESET}" || out+="${ORANGE}◐${RESET}"
    elif [[ "$i" == "$cur" ]]; then out+="${BLUE}◉${RESET}"
    else out+="${DIM}○${RESET}"; fi
    out+=" "
  done
  echo -e "  $out ${DIM}(● 만점  ◐ 부분  ◉ 현재  ○ 대기)${RESET}"
}

# ── 문제 출력 ────────────────────────────────────────────────────
show_question() {
  local n="$1" title
  title=$("q${n}_title")
  echo ""
  sep
  echo -e "  ${BOLD}[Q${n}/${EXAM_NQ}]  ${title}${RESET}"
  sep
  echo ""
  "q${n}_text" | sed 's/^/  /'
  echo ""
  thin
  echo -e "  풀고 나서:  ${CYAN}bash exam.sh check${RESET}      다시 보기: ${CYAN}bash exam.sh show${RESET}"
  echo -e "  넘어가기:   ${CYAN}bash exam.sh skip${RESET}       현황:     ${CYAN}bash exam.sh status${RESET}"
  thin
  progress_bar "$n"
  echo ""
  # 지나온 문제는 파일에 쌓아서 다시 볼 수 있게
  if ! grep -q "^\[Q${n}\]" "$QLOG" 2>/dev/null; then
    { echo "[Q${n}] ${title}"; echo; "q${n}_text"; echo; echo "────────────────────────────────────"; echo; } >> "$QLOG"
  fi
}

# ── 채점 실행 (결과를 Q_PASS/Q_TOTAL 에 남김) ────────────────────
run_grade() {
  local n="$1"
  Q_PASS=0; Q_TOTAL=0; Q_FAILS=()
  "q${n}_grade"
}

advance() {
  local n="$1"
  local next=$((n+1))
  if (( next > EXAM_NQ )); then
    state_set current "$next"
    cmd_finish
  else
    state_set current "$next"
    state_set "q${next}_start" "$(now)"
    show_question "$next"
  fi
}

record_q() {
  local n="$1" pass="$2" total="$3"
  local st; st=$(state_get "q${n}_start"); [[ -z "$st" ]] && st=$(now)
  local el=$(( $(now) - st ))
  state_set "q$n" "${pass}/${total}:${el}"
}

# ── 명령들 ───────────────────────────────────────────────────────
cmd_start() {
  echo ""
  sep
  echo -e "  ${BOLD}${EXAM_TITLE}${RESET}"
  echo -e "  ${EXAM_NQ}문제 · 한 문제씩 풀고 채점하며 진행합니다"
  sep
  rm -f "$STATE" "$QLOG"
  kubectl get nodes &>/dev/null || {
    echo -e "${RED}[ERROR] kubectl 을 실행할 수 없습니다. kubeconfig 를 확인하세요.${RESET}"; exit 1; }
  echo -e "\n${CYAN}[CLEAN] 이전 시험 리소스를 정리합니다...${RESET}"
  exam_cleanup
  echo -e "\n${CYAN}[SETUP] 환경을 준비합니다...${RESET}"
  exam_setup
  echo -e "${GREEN}[SETUP] 완료${RESET}"
  state_set started "$(now)"
  state_set current 1
  state_set q1_start "$(now)"
  show_question 1
}

cmd_show() {
  local cur; cur=$(state_get current)
  [[ -z "$cur" ]] && { echo -e "${ORANGE}아직 시작하지 않았습니다.  bash exam.sh start${RESET}"; exit 1; }
  (( cur > EXAM_NQ )) && { echo -e "${GREEN}모든 문제를 마쳤습니다.  bash exam.sh finish${RESET}"; exit 0; }
  show_question "$cur"
}

cmd_check() {
  local cur; cur=$(state_get current)
  [[ -z "$cur" ]] && { echo -e "${ORANGE}아직 시작하지 않았습니다.  bash exam.sh start${RESET}"; exit 1; }
  (( cur > EXAM_NQ )) && { echo -e "${GREEN}모든 문제를 마쳤습니다.  bash exam.sh finish${RESET}"; exit 0; }
  echo ""
  sep
  echo -e "  ${BOLD}[Q${cur}] 채점${RESET}  $("q${cur}_title")"
  sep
  run_grade "$cur"
  local st; st=$(state_get "q${cur}_start"); local el=$(( $(now) - ${st:-$(now)} ))
  thin
  if (( Q_PASS == Q_TOTAL )); then
    echo -e "  ${GREEN}${BOLD}Q${cur}: ${Q_PASS}/${Q_TOTAL}  ✓ 만점${RESET}   ${DIM}(소요 $(fmt_dur $el))${RESET}"
    record_q "$cur" "$Q_PASS" "$Q_TOTAL"
    state_set "q${cur}_tries" "$(( $(state_get "q${cur}_tries") + 1 ))"
    echo -e "  ${BLUE}→ 다음 문제로 넘어갑니다${RESET}"
    advance "$cur"
  else
    state_set "q${cur}_tries" "$(( $(state_get "q${cur}_tries") + 1 ))"
    echo -e "  ${ORANGE}${BOLD}Q${cur}: ${Q_PASS}/${Q_TOTAL}${RESET}   ${DIM}(경과 $(fmt_dur $el) · 시도 $(state_get "q${cur}_tries")회)${RESET}"
    echo ""
    echo -e "  ▸ 위 ${RED}[FAIL]${RESET} 항목을 고치고 다시  ${CYAN}bash exam.sh check${RESET}"
    echo -e "  ▸ 이 점수로 넘어가려면        ${CYAN}bash exam.sh skip${RESET}"
    [[ "$(type -t "q${cur}_hint")" == "function" ]] && \
      echo -e "  ▸ 막혔으면                    ${CYAN}bash exam.sh hint${RESET}  ${DIM}(사용 기록이 남습니다)${RESET}"
    echo ""
  fi
}

cmd_skip() {
  local cur; cur=$(state_get current)
  [[ -z "$cur" ]] && { echo -e "${ORANGE}아직 시작하지 않았습니다.${RESET}"; exit 1; }
  (( cur > EXAM_NQ )) && { cmd_finish; exit 0; }
  echo -e "\n${ORANGE}[Q${cur}] 현재 점수로 확정하고 넘어갑니다...${RESET}"
  run_grade "$cur" >/dev/null
  record_q "$cur" "$Q_PASS" "$Q_TOTAL"
  state_set "q${cur}_skipped" 1
  echo -e "  Q${cur}: ${Q_PASS}/${Q_TOTAL}  ${DIM}(skip)${RESET}"
  advance "$cur"
}

cmd_hint() {
  local cur; cur=$(state_get current)
  [[ -z "$cur" ]] && { echo -e "${ORANGE}아직 시작하지 않았습니다.${RESET}"; exit 1; }
  if [[ "$(type -t "q${cur}_hint")" != "function" ]]; then
    echo -e "${DIM}이 문제에는 힌트가 없습니다.${RESET}"; exit 0; fi
  state_set "q${cur}_hint" 1
  echo ""; echo -e "  ${ORANGE}${BOLD}[HINT Q${cur}]${RESET}"; thin
  "q${cur}_hint" | sed 's/^/  /'
  thin; echo ""
}

cmd_status() {
  local cur; cur=$(state_get current)
  [[ -z "$cur" ]] && { echo -e "${ORANGE}아직 시작하지 않았습니다.  bash exam.sh start${RESET}"; exit 0; }
  local st; st=$(state_get started); local tot=$(( $(now) - ${st:-$(now)} ))
  echo ""; sep
  echo -e "  ${BOLD}${EXAM_TITLE} — 진행 현황${RESET}   ${DIM}경과 $(fmt_dur $tot)${RESET}"
  sep
  local i sumP=0 sumT=0
  for ((i=1;i<=EXAM_NQ;i++)); do
    local rec; rec=$(state_get "q$i"); local title; title=$("q${i}_title")
    if [[ -n "$rec" ]]; then
      local p="${rec%%/*}"; local rest="${rec#*/}"; local t="${rest%%:*}"; local el="${rest#*:}"
      sumP=$((sumP+p)); sumT=$((sumT+t))
      local mark; [[ "$p" == "$t" ]] && mark="${GREEN}✓${RESET}" || mark="${ORANGE}◐${RESET}"
      local flags=""; [[ -n "$(state_get "q${i}_skipped")" ]] && flags+=" skip"; [[ -n "$(state_get "q${i}_hint")" ]] && flags+=" hint"
      printf "  %b Q%d  %-34s %3s/%-3s %10s%b\n" "$mark" "$i" "$title" "$p" "$t" "$(fmt_dur $el)" "${flags:+  ${DIM}[${flags# }]${RESET}}"
    elif [[ "$i" == "$cur" ]]; then
      printf "  %b Q%d  %-34s %b\n" "${BLUE}◉${RESET}" "$i" "$title" "${BLUE}← 지금${RESET}"
    else
      printf "  %b Q%d  %-34s\n" "${DIM}○${RESET}" "$i" "$title"
    fi
  done
  thin
  echo -e "  누적 ${BOLD}${sumP}${RESET} ${EXAM_UNIT} 통과"
  echo ""
}

cmd_finish() {
  local st; st=$(state_get started); local tot=$(( $(now) - ${st:-$(now)} ))
  local i sumP=0 sumT=0 slowest=0 slowQ=0
  echo ""; sep
  echo -e "  ${BOLD}${EXAM_TITLE} — 최종 리포트${RESET}"
  sep
  for ((i=1;i<=EXAM_NQ;i++)); do
    local rec; rec=$(state_get "q$i"); local title; title=$("q${i}_title")
    if [[ -z "$rec" ]]; then
      run_grade "$i" >/dev/null; record_q "$i" "$Q_PASS" "$Q_TOTAL"; rec=$(state_get "q$i")
    fi
    local p="${rec%%/*}"; local rest="${rec#*/}"; local t="${rest%%:*}"; local el="${rest#*:}"
    sumP=$((sumP+p)); sumT=$((sumT+t))
    (( el > slowest )) && { slowest=$el; slowQ=$i; }
    local mark; [[ "$p" == "$t" ]] && mark="${GREEN}✓${RESET}" || mark="${ORANGE}◐${RESET}"
    local flags=""; [[ -n "$(state_get "q${i}_skipped")" ]] && flags+=" skip"; [[ -n "$(state_get "q${i}_hint")" ]] && flags+=" hint"
    local tries; tries=$(state_get "q${i}_tries"); [[ -n "$tries" && "$tries" -gt 1 ]] && flags+=" ${tries}회"
    printf "  %b Q%d  %-34s %3s/%-3s %10s%b\n" "$mark" "$i" "$title" "$p" "$t" "$(fmt_dur $el)" "${flags:+  ${DIM}[${flags# }]${RESET}}"
  done
  thin
  local pct=0; (( sumT > 0 )) && pct=$(( sumP * 100 / sumT ))
  echo -e "  ${BOLD}합계 ${sumP} / ${sumT} ${EXAM_UNIT}  (${pct}%)${RESET}   총 소요 $(fmt_dur $tot)"
  (( slowQ > 0 )) && echo -e "  ${DIM}가장 오래 걸린 문제: Q${slowQ} ($(fmt_dur $slowest))${RESET}"
  if (( pct >= 66 )); then echo -e "  ${GREEN}${BOLD}합격선(66%) 통과${RESET}"; else echo -e "  ${RED}${BOLD}합격선(66%) 미달${RESET}"; fi
  sep
  echo -e "  ${DIM}지나온 문제 전체: cat work/questions-so-far.txt   ·   리소스 정리: bash exam.sh clean${RESET}"
  echo ""
  state_set finished "$(now)"
}

cmd_reset() { rm -f "$STATE" "$QLOG"; echo -e "${GREEN}진행 기록을 지웠습니다.${RESET}"; }

cmd_clean() {
  echo ""
  sep
  echo -e "  ${BOLD}${EXAM_TITLE} — 원상복구${RESET}"
  sep
  kubectl get nodes &>/dev/null || {
    echo -e "${RED}[ERROR] kubectl 을 실행할 수 없습니다.${RESET}"; exit 1; }
  echo -e "\n${CYAN}[CLEAN] 클러스터의 시험 리소스를 삭제합니다...${RESET}"
  exam_cleanup
  rm -f "$STATE" "$QLOG"
  echo -e "${GREEN}[CLEAN] 완료 — 진행 기록도 지웠습니다.${RESET}"
  echo ""
}

exam_main() {
  case "${1:-}" in
    start)  cmd_start ;;
    show)   cmd_show ;;
    check)  cmd_check ;;
    skip)   cmd_skip ;;
    hint)   cmd_hint ;;
    status) cmd_status ;;
    finish) cmd_finish ;;
    clean)  cmd_clean ;;
    reset)  cmd_reset ;;
    *)
      echo ""
      echo -e "  ${BOLD}${EXAM_TITLE}${RESET}"
      echo ""
      echo -e "  ${CYAN}bash exam.sh start${RESET}    환경 준비 + 1번 문제 출제"
      echo -e "  ${CYAN}bash exam.sh check${RESET}    현재 문제 채점 (만점이면 자동으로 다음 문제)"
      echo -e "  ${CYAN}bash exam.sh show${RESET}     현재 문제 다시 보기"
      echo -e "  ${CYAN}bash exam.sh skip${RESET}     현재 점수로 확정하고 다음으로"
      echo -e "  ${CYAN}bash exam.sh hint${RESET}     힌트 (사용 기록이 남음)"
      echo -e "  ${CYAN}bash exam.sh status${RESET}   진행 현황"
      echo -e "  ${CYAN}bash exam.sh finish${RESET}   최종 리포트"
      echo -e "  ${CYAN}bash exam.sh clean${RESET}    시험 리소스 전부 삭제 + 진행 기록 삭제 (원상복구)"
      echo -e "  ${CYAN}bash exam.sh reset${RESET}    진행 기록만 삭제"
      echo ""
      ;;
  esac
}
