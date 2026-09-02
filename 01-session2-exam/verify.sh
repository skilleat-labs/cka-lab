#!/usr/bin/env bash
# CKA 2세션 시험 채점 스크립트
# 사용법: bash verify.sh
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; ORANGE='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

PASS=0; FAIL=0; TOTAL=0

sep() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

check() {
  local desc="$1"; local cmd="$2"
  TOTAL=$((TOTAL+1))
  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}[PASS]${RESET} $desc"; PASS=$((PASS+1))
  else
    echo -e "  ${RED}[FAIL]${RESET} $desc"; FAIL=$((FAIL+1))
  fi
}

check_output() {
  local desc="$1"; local cmd="$2"; local pattern="$3"
  TOTAL=$((TOTAL+1))
  local out
  out=$(eval "$cmd" 2>/dev/null || echo "")
  if echo "$out" | grep -qE "$pattern"; then
    echo -e "  ${GREEN}[PASS]${RESET} $desc"; PASS=$((PASS+1))
  else
    echo -e "  ${RED}[FAIL]${RESET} $desc  ${ORANGE}(기대: $pattern / 실제: '${out}')${RESET}"
    FAIL=$((FAIL+1))
  fi
}

echo ""
sep
echo -e "  ${BOLD}CKA 2세션 시험 채점${RESET}"
sep

# 파드가 Ready 될 때까지 대기 (exec 검증 전)
wait_ready() {
  local pod="$1" ns="$2" i
  # 파드 자체가 없으면 기다리지 않고 즉시 종료
  kubectl get pod "$pod" -n "$ns" &>/dev/null || return 1
  for i in $(seq 1 20); do
    [[ "$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" == "true" ]] && return 0
    sleep 2
  done
  return 1
}


# ════════════════════════════════════════════════════════════════
# E1: 네임스페이스 + Deployment + NodePort Service
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}[E1] 네임스페이스 지정 · Deployment · NodePort${RESET}"

check \
  "namespace ops 가 존재한다" \
  "kubectl get namespace ops"

check \
  "cache-app Deployment 가 ops 네임스페이스에 존재한다" \
  "kubectl get deployment cache-app -n ops"

check_output \
  "cache-app 이미지가 nginx:1.24 이다" \
  "kubectl get deployment cache-app -n ops -o jsonpath='{.spec.template.spec.containers[0].image}'" \
  "^nginx:1\.24$"

check_output \
  "cache-app replicas 가 2 이다" \
  "kubectl get deployment cache-app -n ops -o jsonpath='{.spec.replicas}'" \
  "^2$"

check_output \
  "cache-app 파드 2개가 모두 Ready 이다" \
  "kubectl get deployment cache-app -n ops -o jsonpath='{.status.readyReplicas}'" \
  "^2$"

check_output \
  "cache-app containerPort 80 이 노출되어 있다" \
  "kubectl get deployment cache-app -n ops -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'" \
  "^80$"

# default 네임스페이스에 잘못 만들지 않았는지 (네임스페이스 지정 능력 판정)
TOTAL=$((TOTAL+1))
if kubectl get deployment cache-app -n ops &>/dev/null && ! kubectl get deployment cache-app -n default &>/dev/null; then
  echo -e "  ${GREEN}[PASS]${RESET} cache-app 이 ops 네임스페이스에만 존재한다"
  PASS=$((PASS+1))
elif kubectl get deployment cache-app -n default &>/dev/null; then
  echo -e "  ${RED}[FAIL]${RESET} cache-app 이 ops 네임스페이스에만 존재한다  ${ORANGE}(default 에도 있음 — -n ops 누락)${RESET}"
  FAIL=$((FAIL+1))
else
  echo -e "  ${RED}[FAIL]${RESET} cache-app 이 ops 네임스페이스에만 존재한다  ${ORANGE}(ops 에 없음)${RESET}"
  FAIL=$((FAIL+1))
fi

check \
  "cache-svc Service 가 ops 네임스페이스에 존재한다" \
  "kubectl get service cache-svc -n ops"

check_output \
  "cache-svc 타입이 NodePort 이다" \
  "kubectl get service cache-svc -n ops -o jsonpath='{.spec.type}'" \
  "^NodePort$"

check_output \
  "cache-svc port 가 80 이다" \
  "kubectl get service cache-svc -n ops -o jsonpath='{.spec.ports[0].port}'" \
  "^80$"

check_output \
  "cache-svc targetPort 가 80 이다" \
  "kubectl get service cache-svc -n ops -o jsonpath='{.spec.ports[0].targetPort}'" \
  "^80$"

check_output \
  "cache-svc nodePort 가 30090 이다" \
  "kubectl get service cache-svc -n ops -o jsonpath='{.spec.ports[0].nodePort}'" \
  "^30090$"

EP1=$(kubectl get endpoints cache-svc -n ops -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
TOTAL=$((TOTAL+1))
if [[ "${EP1}" == "2" ]]; then
  echo -e "  ${GREEN}[PASS]${RESET} cache-svc Endpoints 에 파드 IP 2개가 등록되어 있다"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}[FAIL]${RESET} cache-svc Endpoints 에 파드 IP 2개가 등록되어 있다  ${ORANGE}(실제: ${EP1}개 — selector 확인)${RESET}"
  FAIL=$((FAIL+1))
fi

echo ""
sep

# ════════════════════════════════════════════════════════════════
# E2: ConfigMap — env + volume
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${ORANGE}[E2] ConfigMap 환경변수 주입 + 볼륨 마운트${RESET}"

check \
  "namespace app 이 존재한다" \
  "kubectl get namespace app"

check \
  "app-config ConfigMap 이 app 네임스페이스에 존재한다" \
  "kubectl get configmap app-config -n app"

check_output \
  "app-config 에 APP_ENV=production 이 있다" \
  "kubectl get configmap app-config -n app -o jsonpath='{.data.APP_ENV}'" \
  "^production$"

check_output \
  "app-config 에 LOG_LEVEL=info 가 있다" \
  "kubectl get configmap app-config -n app -o jsonpath='{.data.LOG_LEVEL}'" \
  "^info$"

check \
  "config-pod Pod 가 app 네임스페이스에 존재한다" \
  "kubectl get pod config-pod -n app"

check_output \
  "config-pod 가 Running 상태이다" \
  "kubectl get pod config-pod -n app -o jsonpath='{.status.phase}'" \
  "^Running$"

wait_ready config-pod app || true

# (a) 환경변수 주입 — 파드 내부에서 실제 확인
check_output \
  "config-pod 안에서 APP_ENV=production 환경변수가 보인다 (실제 exec 검증)" \
  "kubectl exec config-pod -n app -- env 2>/dev/null" \
  "^APP_ENV=production$"

check_output \
  "config-pod 안에서 LOG_LEVEL=info 환경변수가 보인다 (실제 exec 검증)" \
  "kubectl exec config-pod -n app -- env 2>/dev/null" \
  "^LOG_LEVEL=info$"

# (b) 볼륨 마운트 — 파일로 존재하는지 실제 확인
check_output \
  "config-pod 의 /etc/app-config 에 ConfigMap 이 마운트되어 있다 (실제 exec 검증)" \
  "kubectl exec config-pod -n app -- ls /etc/app-config 2>/dev/null" \
  "APP_ENV"

check_output \
  "/etc/app-config/LOG_LEVEL 파일 내용이 info 이다 (실제 exec 검증)" \
  "kubectl exec config-pod -n app -- cat /etc/app-config/LOG_LEVEL 2>/dev/null" \
  "^info$"

echo ""
sep

# ════════════════════════════════════════════════════════════════
# E3: Secret — 특정 키만 선택 주입
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[E3] Secret 생성 + 특정 키만 주입${RESET}"

check \
  "db-secret Secret 이 app 네임스페이스에 존재한다" \
  "kubectl get secret db-secret -n app"

check_output \
  "db-secret 타입이 Opaque 이다 (generic)" \
  "kubectl get secret db-secret -n app -o jsonpath='{.type}'" \
  "^Opaque$"

check_output \
  "db-secret 의 DB_USER 가 admin 이다 (base64 디코딩 검증)" \
  "kubectl get secret db-secret -n app -o jsonpath='{.data.DB_USER}' 2>/dev/null | base64 -d" \
  "^admin$"

check_output \
  "db-secret 의 DB_PASSWORD 가 supersecret 이다 (base64 디코딩 검증)" \
  "kubectl get secret db-secret -n app -o jsonpath='{.data.DB_PASSWORD}' 2>/dev/null | base64 -d" \
  "^supersecret$"

check \
  "secret-pod Pod 가 app 네임스페이스에 존재한다" \
  "kubectl get pod secret-pod -n app"

check_output \
  "secret-pod 가 Running 상태이다" \
  "kubectl get pod secret-pod -n app -o jsonpath='{.status.phase}'" \
  "^Running$"

wait_ready secret-pod app || true

check_output \
  "secret-pod 안에서 DB_PASSWORD=supersecret 이 보인다 (실제 exec 검증)" \
  "kubectl exec secret-pod -n app -- env 2>/dev/null" \
  "^DB_PASSWORD=supersecret$"

# DB_USER 는 주입되면 안 됨 — envFrom 으로 전체 주입했는지 판정
TOTAL=$((TOTAL+1))
SP_ENV=$(kubectl exec secret-pod -n app -- env 2>/dev/null || echo "")
if echo "$SP_ENV" | grep -q "^DB_USER="; then
  echo -e "  ${RED}[FAIL]${RESET} DB_PASSWORD 만 주입되고 DB_USER 는 주입되지 않았다  ${ORANGE}(DB_USER 가 보임 — envFrom 전체 주입은 오답, env + secretKeyRef 사용)${RESET}"
  FAIL=$((FAIL+1))
elif echo "$SP_ENV" | grep -q "^DB_PASSWORD="; then
  echo -e "  ${GREEN}[PASS]${RESET} DB_PASSWORD 만 주입되고 DB_USER 는 주입되지 않았다 (필요한 키만 선택 주입)"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}[FAIL]${RESET} DB_PASSWORD 만 주입되고 DB_USER 는 주입되지 않았다  ${ORANGE}(파드에서 환경변수를 읽을 수 없음)${RESET}"
  FAIL=$((FAIL+1))
fi

echo ""
sep


echo ""
echo -e "  ${BOLD}채점 결과:  PASS ${PASS} / TOTAL ${TOTAL}${RESET}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}전 항목 통과! 네임스페이스·ConfigMap·Secret 모두 정확합니다.${RESET}"
else
  echo -e "  ${RED}${BOLD}실패 항목: ${FAIL}개${RESET}"
  echo -e "  위 [FAIL] 항목을 수정하고 다시 ${CYAN}bash verify.sh${RESET} 를 실행하세요."
  echo -e "  ${ORANGE}복습이 필요하면: bash exam-start.sh --hints${RESET}"
fi

echo ""
sep
echo ""

exit $FAIL
