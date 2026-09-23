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
#   qN_title()                문제 제목 한 줄 — 영어  (echo)
#   qN_text()                 문제 본문      — 영어  (cat <<'EOF' ...)
#   qN_title_ko() / qN_text_ko()   같은 내용의 한글판 (선택. 없으면 영어가 나온다)
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

# ── 지문 언어 — 기본 영어(실제 시험과 같게), ko 로 바꾸면 한글 ────
#   우선순위: EXAM_LANG 환경변수 > work/.progress 의 lang > en
exam_lang() {
  local l="${EXAM_LANG:-}"
  [[ -z "$l" ]] && l=$(state_get lang)
  [[ "$l" == "ko" ]] && echo ko || echo en
}
q_title() {   # q_title <n> [lang]
  local n="$1" l="${2:-$(exam_lang)}"
  if [[ "$l" == "ko" && "$(type -t "q${n}_title_ko")" == "function" ]]; then "q${n}_title_ko"; else "q${n}_title"; fi
}
q_text() {    # q_text <n> [lang]
  local n="$1" l="${2:-$(exam_lang)}"
  if [[ "$l" == "ko" && "$(type -t "q${n}_text_ko")" == "function" ]]; then "q${n}_text_ko"; else "q${n}_text"; fi
}
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

# ── 병렬 채점 ────────────────────────────────────────────────────
#   검사 항목은 서로 독립적인 읽기 전용 kubectl 호출이라 동시에 돌려도 된다.
#   등록 순서대로 결과를 모아 출력하므로 화면·점수는 순차 실행과 동일하다.
#   EXAM_PARALLEL=0 이면 예전처럼 하나씩 실행한다 (디버깅용).
EXAM_PARALLEL="${EXAM_PARALLEL:-1}"
EXAM_PARALLEL_MAX="${EXAM_PARALLEL_MAX:-4}"   # 동시 kubectl 프로세스 수 (VM 메모리 고려)
_CK_DIR=""; _CK_N=0

_ck_throttle() {   # 동시 실행 수를 EXAM_PARALLEL_MAX 로 제한
  while (( $(jobs -rp 2>/dev/null | wc -l) >= EXAM_PARALLEL_MAX )); do
    wait -n 2>/dev/null || sleep 0.05
  done
}
_ck_meta() {       # 항목 메타 기록 (번호는 호출부에서 증가시킨다 — 서브셸이면 안 되므로)
  printf '%s\n%s\n%s\n' "$2" "$3" "${4:-}" > "$_CK_DIR/$1.meta"
}
_pass() { local pts="$1"; Q_PASS=$((Q_PASS+pts)); }
_pts_label() { [[ "${EXAM_UNIT}" == "점" ]] && printf '[+%s점] ' "$1" || true; }
_zero_label() { [[ "${EXAM_UNIT}" == "점" ]] && printf '[ 0점] ' || true; }

# ── 채점 항목을 JSON 한 줄씩 남긴다 (web UI 가 읽는다. 터미널 출력에는 영향 없음) ──
JSONL="$WORK_DIR/.last-check.jsonl"
_json_esc() {
  printf '%s' "$1" | tr '\n\r\t' '   ' | sed 's/\\/\\\\/g; s/"/\\"/g' | cut -c1-300
}
_jrec() {  # desc ok(0/1) pts note
  printf '{"desc":"%s","ok":%s,"pts":%s,"note":"%s"}\n' \
    "$(_json_esc "$1")" "$([[ "$2" == "0" ]] && echo true || echo false)" "$3" "$(_json_esc "${4:-}")" \
    >> "$JSONL" 2>/dev/null || true
}

#   check        desc cmd            [pts]
#   check_output desc cmd pattern    [pts]
#   check_result desc ok(0/1) [note] [pts]
check() {
  local desc="$1" cmd="$2" pts="${3:-1}" i
  _CK_N=$((_CK_N+1)); i=$_CK_N; _ck_meta "$i" "$desc" "$pts"
  if [[ "$EXAM_PARALLEL" == "1" ]]; then
    _ck_throttle
    { eval "$cmd" &>/dev/null && echo 0 || echo 1; } > "$_CK_DIR/$i.rc" &
  else
    { eval "$cmd" &>/dev/null && echo 0 || echo 1; } > "$_CK_DIR/$i.rc"
  fi
}
check_output() {
  local desc="$1" cmd="$2" pattern="$3" pts="${4:-1}" i
  _CK_N=$((_CK_N+1)); i=$_CK_N; _ck_meta "$i" "$desc" "$pts" "$pattern"
  _ck_run_output() {
    local out; out=$(eval "$1" 2>/dev/null || echo "")
    printf '%s' "$out" > "$_CK_DIR/$2.out"
    echo "$out" | grep -qE "$3" && echo 0 || echo 1
  }
  if [[ "$EXAM_PARALLEL" == "1" ]]; then
    _ck_throttle
    _ck_run_output "$cmd" "$i" "$pattern" > "$_CK_DIR/$i.rc" &
  else
    _ck_run_output "$cmd" "$i" "$pattern" > "$_CK_DIR/$i.rc"
  fi
}
# 직접 판정한 결과를 기록할 때 (복잡한 검사용) — 값이 이미 계산돼 있으므로 즉시 기록
check_result() {
  local desc="$1" ok="$2" note="${3:-}" pts="${4:-1}" i
  _CK_N=$((_CK_N+1)); i=$_CK_N; _ck_meta "$i" "$desc" "$pts"
  printf '%s' "$note" > "$_CK_DIR/$i.note"
  if [[ "$ok" == "0" ]]; then echo 0 > "$_CK_DIR/$i.rc"; else echo 1 > "$_CK_DIR/$i.rc"; fi
}

# 등록 순서대로 결과를 모아 출력·집계한다 (run_grade 가 호출)
_ck_report() {
  local i rc desc pts pattern out note
  for ((i=1;i<=_CK_N;i++)); do
    rc=$(cat "$_CK_DIR/$i.rc" 2>/dev/null); rc="${rc:-1}"
    desc=""; pts=1; pattern=""
    { IFS= read -r desc; IFS= read -r pts; IFS= read -r pattern; } < "$_CK_DIR/$i.meta" 2>/dev/null
    pts="${pts:-1}"
    Q_TOTAL=$((Q_TOTAL+pts))
    if [[ "$rc" == "0" ]]; then
      echo -e "  ${GREEN}[PASS]${RESET} $(_pts_label "$pts")$desc"; _pass "$pts"; _jrec "$desc" 0 "$pts"
    else
      note=""
      if [[ -f "$_CK_DIR/$i.out" ]]; then
        out=$(cat "$_CK_DIR/$i.out" 2>/dev/null)
        note="기대: $pattern / 실제: ${out}"
        echo -e "  ${RED}[FAIL]${RESET} $(_zero_label)$desc  ${ORANGE}($note)${RESET}"
      elif [[ -s "$_CK_DIR/$i.note" ]]; then
        note=$(cat "$_CK_DIR/$i.note" 2>/dev/null)
        echo -e "  ${RED}[FAIL]${RESET} $(_zero_label)$desc  ${ORANGE}($note)${RESET}"
      else
        echo -e "  ${RED}[FAIL]${RESET} $(_zero_label)$desc"
      fi
      Q_FAILS+=("$desc"); _jrec "$desc" 1 "$pts" "$note"
    fi
  done
}

# 리소스 삭제를 백그라운드로 — cleanup 의 delete 들은 서로 독립적이라 동시에 돌려도 된다.
#   exam_cleanup 안에서 kdel 을 쓰면 엔진이 cleanup 직후 wait 로 모두 끝날 때까지 기다린다.
kdel() { kubectl delete "$@" --ignore-not-found &>/dev/null & }

# 파드 Ready 대기 (최대 40초) — 채점 전 안정화용. 파드가 없으면 즉시 반환
wait_ready() {
  local sel="$1" ns="${2:-default}" i
  [[ -z "$(kubectl get pods -n "$ns" $sel -o name 2>/dev/null)" ]] && return 1
  for i in $(seq 1 40); do
    local r; r=$(kubectl get pods -n "$ns" $sel -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | sort -u | tr -d '\n')
    [[ "$r" == "true" ]] && return 0
    sleep 1
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
  title=$(q_title "$n")
  echo ""
  sep
  echo -e "  ${BOLD}[Q${n}/${EXAM_NQ}]  ${title}${RESET}"
  sep
  echo ""
  q_text "$n" | sed 's/^/  /'
  echo ""
  thin
  echo -e "  풀고 나서:  ${CYAN}bash exam.sh check${RESET}      다시 보기: ${CYAN}bash exam.sh show${RESET}"
  echo -e "  넘어가기:   ${CYAN}bash exam.sh skip${RESET}       현황:     ${CYAN}bash exam.sh status${RESET}"
  echo -e "  문제 이동:  ${CYAN}bash exam.sh go <번호>${RESET}   ${DIM}prev / next 도 가능${RESET}"
  thin
  progress_bar "$n"
  echo ""
  # 지나온 문제는 파일에 쌓아서 다시 볼 수 있게
  if ! grep -q "^\[Q${n}\]" "$QLOG" 2>/dev/null; then
    { echo "[Q${n}] ${title}"; echo; q_text "$n"; echo; echo "────────────────────────────────────"; echo; } >> "$QLOG"
  fi
}

# ── 채점 실행 (결과를 Q_PASS/Q_TOTAL 에 남김) ────────────────────
run_grade() {
  local n="$1"
  Q_PASS=0; Q_TOTAL=0; Q_FAILS=(); _CK_N=0
  printf '{"q":%s}\n' "$n" > "$JSONL" 2>/dev/null || true
  _CK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cka-grade.XXXXXX")
  "q${n}_grade"
  wait                 # 병렬로 띄운 검사가 모두 끝날 때까지
  _ck_report           # 등록 순서대로 출력·집계
  rm -rf "$_CK_DIR"
}

# 문제 n 으로 이동 (되돌아가기 포함)
goto_q() {
  local n="$1" cur
  cur=$(state_get current)
  [[ -n "$cur" && "$cur" != "$n" ]] && q_close "$cur"
  state_set current "$n"
  state_set "q${n}_start" "$(now)"
  show_question "$n"
}
# 다음으로 — 아직 채점되지 않은 문제를 우선 찾고, 없으면 리포트
advance() {
  local n="$1" i
  for ((i=n+1;i<=EXAM_NQ;i++)); do
    [[ -z "$(state_get "q$i")" ]] && { goto_q "$i"; return; }
  done
  for ((i=1;i<=EXAM_NQ;i++)); do
    [[ -z "$(state_get "q$i")" ]] && { goto_q "$i"; return; }
  done
  q_close "$n"
  state_set current $((EXAM_NQ+1))
  cmd_finish
}

# 이 문제에 지금까지 쓴 총 시간 (문제를 오가도 누적된다)
q_elapsed() {
  local n="$1"
  local st; st=$(state_get "q${n}_start")
  local acc; acc=$(state_get "q${n}_acc"); acc="${acc:-0}"
  local stint=0
  [[ -n "$st" ]] && stint=$(( $(now) - st ))
  echo $(( acc + stint ))
}
# 문제를 떠날 때(또는 채점할 때) 머문 시간을 누적하고 시계를 다시 건다
q_close() {
  local n="$1"
  [[ -z "$n" ]] && return 0
  local st; st=$(state_get "q${n}_start"); [[ -z "$st" ]] && return 0
  local acc; acc=$(state_get "q${n}_acc"); acc="${acc:-0}"
  state_set "q${n}_acc" $(( acc + $(now) - st ))
  state_set "q${n}_start" "$(now)"
}
record_q() {
  local n="$1" pass="$2" total="$3"
  local el; el=$(q_elapsed "$n")
  q_close "$n"
  state_set "q$n" "${pass}/${total}:${el}"
}

# ── 명령들 ───────────────────────────────────────────────────────
cmd_start() {
  echo ""
  sep
  echo -e "  ${BOLD}${EXAM_TITLE}${RESET}"
  echo -e "  ${EXAM_NQ}문제 · 한 문제씩 풀고 채점하며 진행합니다"
  sep
  rm -f "$STATE" "$QLOG" "$JSONL"
  kubectl get nodes &>/dev/null || {
    echo -e "${RED}[ERROR] kubectl 을 실행할 수 없습니다. kubeconfig 를 확인하세요.${RESET}"; exit 1; }
  echo -e "\n${CYAN}[CLEAN] 이전 시험 리소스를 정리합니다...${RESET}"
  exam_cleanup; wait
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
  echo -e "  ${BOLD}[Q${cur}] 채점${RESET}  $(q_title "$cur")"
  sep
  run_grade "$cur"
  local el; el=$(q_elapsed "$cur")
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
    echo -e "  ▸ 다른 문제로 이동             ${CYAN}bash exam.sh go <번호>${RESET}  ${DIM}(나중에 돌아와 다시 채점할 수 있습니다)${RESET}"
    [[ "$(type -t "q${cur}_hint")" == "function" ]] && \
      echo -e "  ▸ 막혔으면                    ${CYAN}bash exam.sh hint${RESET}  ${DIM}(사용 기록이 남습니다)${RESET}"
    echo ""
  fi
}

cmd_go() {   # bash exam.sh go 3   ·  next  ·  prev
  local want="$1" cur
  cur=$(state_get current)
  [[ -z "$cur" ]] && { echo -e "${ORANGE}아직 시작하지 않았습니다.  bash exam.sh start${RESET}"; exit 1; }
  case "$want" in
    next) want=$(( cur + 1 )) ;;
    prev) want=$(( cur - 1 )) ;;
  esac
  if ! [[ "$want" =~ ^[0-9]+$ ]] || (( want < 1 || want > EXAM_NQ )); then
    echo -e "${ORANGE}1 ~ ${EXAM_NQ} 사이의 문제 번호를 주세요.  예) bash exam.sh go 2${RESET}"; exit 1
  fi
  local rec; rec=$(state_get "q$want")
  goto_q "$want"
  [[ -n "$rec" ]] && echo -e "  ${DIM}이미 채점된 문제입니다 (${rec%%:*}). 다시 채점하면 점수가 갱신됩니다.${RESET}\n"
  return 0
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
    local rec; rec=$(state_get "q$i"); local title; title=$(q_title "$i")
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
    local rec; rec=$(state_get "q$i"); local title; title=$(q_title "$i")
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
  exam_cleanup; wait
  rm -f "$STATE" "$QLOG"
  echo -e "${GREEN}[CLEAN] 완료 — 진행 기록도 지웠습니다.${RESET}"
  echo ""
}

# ── web UI 전용 (사람이 직접 쓸 일은 없다) ──────────────────────
cmd_qtext() {   # 장식·ANSI 없는 문제 원문.  cmd_qtext <n> [en|ko]
  local n="${1:-$(state_get current)}" lang="${2:-$(exam_lang)}"
  [[ -z "$n" ]] && n=1
  (( n > EXAM_NQ )) && return 0
  q_title "$n" "$lang"; echo "---8<---"; q_text "$n" "$lang"
}
cmd_hinttext() { # 장식 없는 힌트 (기록도 남긴다)
  local n; n=$(state_get current); [[ -z "$n" ]] && exit 1
  [[ "$(type -t "q${n}_hint")" != "function" ]] && { echo "(이 문제에는 힌트가 없습니다)"; exit 0; }
  state_set "q${n}_hint" 1
  "q${n}_hint"
}
cmd_lang() {    # 지문 언어 바꾸기 — bash exam.sh lang ko
  local l="$1"
  if [[ "$l" != "ko" && "$l" != "en" ]]; then
    echo "현재 지문 언어: $(exam_lang)   (바꾸려면: bash exam.sh lang en|ko)"; return 0
  fi
  state_set lang "$l"
  echo -e "${GREEN}지문 언어를 ${l} 로 바꿨습니다.${RESET}  다시 보기: bash exam.sh show"
}
cmd_meta() {    # key=value 로 세트 정보 출력
  echo "title=$EXAM_TITLE"
  echo "nq=$EXAM_NQ"
  echo "unit=$EXAM_UNIT"
  local i
  echo "lang=$(exam_lang)"
  for ((i=1;i<=EXAM_NQ;i++)); do
    echo "q${i}_title=$(q_title "$i" en)"
    echo "q${i}_titleKo=$(q_title "$i" ko)"
    [[ "$(type -t "q${i}_text_ko")" == "function" ]] && echo "q${i}_hasKo=1"
    [[ "$(type -t "q${i}_hint")" == "function" ]] && echo "q${i}_hasHint=1"
  done
}

exam_main() {
  case "${1:-}" in
    start)  cmd_start ;;
    show)   cmd_show ;;
    check)  cmd_check ;;
    skip)   cmd_skip ;;
    go)     cmd_go "${2:-}" ;;
    next)   cmd_go next ;;
    prev)   cmd_go prev ;;
    hint)   cmd_hint ;;
    status) cmd_status ;;
    finish) cmd_finish ;;
    clean)  cmd_clean ;;
    reset)  cmd_reset ;;
    qtext)    cmd_qtext "${2:-}" "${3:-}" ;;
    lang)     cmd_lang "${2:-}" ;;
    hinttext) cmd_hinttext ;;
    meta)     cmd_meta ;;
    *)
      echo ""
      echo -e "  ${BOLD}${EXAM_TITLE}${RESET}"
      echo ""
      echo -e "  ${CYAN}bash exam.sh start${RESET}    환경 준비 + 1번 문제 출제"
      echo -e "  ${CYAN}bash exam.sh check${RESET}    현재 문제 채점 (만점이면 자동으로 다음 문제)"
      echo -e "  ${CYAN}bash exam.sh show${RESET}     현재 문제 다시 보기"
      echo -e "  ${CYAN}bash exam.sh skip${RESET}     현재 점수로 확정하고 다음으로"
      echo -e "  ${CYAN}bash exam.sh go 2${RESET}     2번 문제로 이동 (되돌아가기 가능 · next / prev 도 됨)"
      echo -e "  ${CYAN}bash exam.sh hint${RESET}     힌트 (사용 기록이 남음)"
      echo -e "  ${CYAN}bash exam.sh status${RESET}   진행 현황"
      echo -e "  ${CYAN}bash exam.sh finish${RESET}   최종 리포트"
      echo -e "  ${CYAN}bash exam.sh clean${RESET}    시험 리소스 전부 삭제 + 진행 기록 삭제 (원상복구)"
      echo -e "  ${CYAN}bash exam.sh reset${RESET}    진행 기록만 삭제"
      echo -e "  ${CYAN}bash exam.sh lang ko${RESET}  지문을 한글로 (기본은 영어 — 실제 시험과 같게)"
      echo ""
      ;;
  esac
}
