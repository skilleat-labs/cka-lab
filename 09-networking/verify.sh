#!/usr/bin/env bash
# CKA 6강 실습 채점 스크립트
# 사용법: bash verify.sh
set -uo pipefail

# ── 색상 ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; ORANGE='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

PASS=0; FAIL=0; TOTAL=0

sep() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

check() {
  local desc="$1"; local cmd="$2"
  TOTAL=$((TOTAL+1))
  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}[PASS]${RESET} $desc"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}[FAIL]${RESET} $desc"
    FAIL=$((FAIL+1))
  fi
}

check_output() {
  local desc="$1"; local cmd="$2"; local pattern="$3"
  TOTAL=$((TOTAL+1))
  local out
  out=$(eval "$cmd" 2>/dev/null || echo "")
  if echo "$out" | grep -qE "$pattern"; then
    echo -e "  ${GREEN}[PASS]${RESET} $desc"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}[FAIL]${RESET} $desc  ${ORANGE}(기대: $pattern)${RESET}"
    FAIL=$((FAIL+1))
  fi
}

echo ""
sep
echo -e "  ${BOLD}CKA 6강 실습 채점${RESET}"
sep

# ════════════════════════════════════════════════════════════════
# P1: ClusterIP 서비스
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}[P1] ClusterIP 서비스${RESET}"

# 1-1. web Deployment 존재 확인
check \
  "web Deployment가 default 네임스페이스에 존재한다" \
  "kubectl get deployment web -n default"

# 1-2. web Deployment 레플리카 3개 확인
check_output \
  "web Deployment replicas가 3이다" \
  "kubectl get deployment web -n default -o jsonpath='{.spec.replicas}'" \
  "^3$"

# 1-3. web Deployment 이미지 확인
check_output \
  "web Deployment 이미지가 nginx:1.24이다" \
  "kubectl get deployment web -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" \
  "nginx:1\.24"

# 1-4. web-svc Service 존재 확인
check \
  "web-svc Service가 default 네임스페이스에 존재한다" \
  "kubectl get service web-svc -n default"

# 1-5. web-svc 타입이 ClusterIP인지 확인
check_output \
  "web-svc 타입이 ClusterIP이다" \
  "kubectl get service web-svc -n default -o jsonpath='{.spec.type}'" \
  "ClusterIP"

# 1-6. web-svc 포트 80 확인
check_output \
  "web-svc port가 80이다" \
  "kubectl get service web-svc -n default -o jsonpath='{.spec.ports[0].port}'" \
  "^80$"

# 1-7. web-svc selector가 app=web인지 확인
check_output \
  "web-svc selector가 app=web이다" \
  "kubectl get service web-svc -n default -o jsonpath='{.spec.selector.app}'" \
  "^web$"

# 1-8. Endpoints에 Pod IP가 등록되었는지 확인 (비어있지 않음)
check_output \
  "web-svc Endpoints에 Pod IP가 등록되었다" \
  "kubectl get endpoints web-svc -n default -o jsonpath='{.subsets[0].addresses[0].ip}'" \
  "\."

echo ""
sep

# ════════════════════════════════════════════════════════════════
# P2: NodePort 서비스
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${ORANGE}[P2] NodePort 서비스${RESET}"

# 2-1. api Deployment 존재 확인
check \
  "api Deployment가 default 네임스페이스에 존재한다" \
  "kubectl get deployment api -n default"

# 2-2. api Deployment 레플리카 2개 확인
check_output \
  "api Deployment replicas가 2이다" \
  "kubectl get deployment api -n default -o jsonpath='{.spec.replicas}'" \
  "^2$"

# 2-3. api Deployment 이미지 확인
check_output \
  "api Deployment 이미지가 nginx:1.24이다" \
  "kubectl get deployment api -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" \
  "nginx:1\.24"

# 2-4. api-svc Service 존재 확인
check \
  "api-svc Service가 default 네임스페이스에 존재한다" \
  "kubectl get service api-svc -n default"

# 2-5. api-svc 타입이 NodePort인지 확인
check_output \
  "api-svc 타입이 NodePort이다" \
  "kubectl get service api-svc -n default -o jsonpath='{.spec.type}'" \
  "NodePort"

# 2-6. api-svc nodePort가 30080인지 확인
check_output \
  "api-svc nodePort가 30080이다" \
  "kubectl get service api-svc -n default -o jsonpath='{.spec.ports[0].nodePort}'" \
  "^30080$"

# 2-7. api-svc port가 80인지 확인
check_output \
  "api-svc port가 80이다" \
  "kubectl get service api-svc -n default -o jsonpath='{.spec.ports[0].port}'" \
  "^80$"

# 2-8. api-svc selector가 app=api인지 확인
check_output \
  "api-svc selector가 app=api이다" \
  "kubectl get service api-svc -n default -o jsonpath='{.spec.selector.app}'" \
  "^api$"

echo ""
sep

# ════════════════════════════════════════════════════════════════
# P3: NetworkPolicy
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${RED}[P3] NetworkPolicy${RESET}"

# 3-1. backend Deployment 존재 확인
check \
  "backend Deployment가 default 네임스페이스에 존재한다" \
  "kubectl get deployment backend -n default"

# 3-2. backend Deployment 이미지 확인
check_output \
  "backend Deployment 이미지가 nginx:1.24이다" \
  "kubectl get deployment backend -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" \
  "nginx:1\.24"

# 3-3. backend-policy NetworkPolicy 존재 확인
check \
  "backend-policy NetworkPolicy가 default 네임스페이스에 존재한다" \
  "kubectl get networkpolicy backend-policy -n default"

# 3-4. NetworkPolicy podSelector가 app=backend인지 확인
check_output \
  "backend-policy podSelector가 app=backend이다" \
  "kubectl get networkpolicy backend-policy -n default -o jsonpath='{.spec.podSelector.matchLabels.app}'" \
  "^backend$"

# 3-5. policyTypes에 Ingress 포함 확인
check_output \
  "backend-policy policyTypes에 Ingress가 포함된다" \
  "kubectl get networkpolicy backend-policy -n default -o jsonpath='{.spec.policyTypes}'" \
  "Ingress"

# 3-6. ingress 규칙이 존재하는지 확인
check_output \
  "backend-policy에 ingress 규칙이 존재한다" \
  "kubectl get networkpolicy backend-policy -n default -o jsonpath='{.spec.ingress}'" \
  "podSelector|from"

# 3-7. ingress from podSelector가 app=frontend인지 확인
check_output \
  "ingress from podSelector가 app=frontend이다" \
  "kubectl get networkpolicy backend-policy -n default -o json" \
  "frontend"

echo ""
sep

# ════════════════════════════════════════════════════════════════
# P4: DNS 검증
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[P4] DNS 검증${RESET}"

# 4-1. dns-test Pod 존재 확인
check \
  "dns-test Pod가 default 네임스페이스에 존재한다" \
  "kubectl get pod dns-test -n default"

# 4-2. dns-test Pod Running 상태 확인
check_output \
  "dns-test Pod가 Running 상태이다" \
  "kubectl get pod dns-test -n default -o jsonpath='{.status.phase}'" \
  "^Running$"

# 4-3. dns-test Pod 이미지 확인
check_output \
  "dns-test Pod 이미지가 busybox:1.36이다" \
  "kubectl get pod dns-test -n default -o jsonpath='{.spec.containers[0].image}'" \
  "busybox"

# 4-4. dns-test Pod Ready 확인
check_output \
  "dns-test Pod가 Ready 상태이다" \
  "kubectl get pod dns-test -n default -o jsonpath='{.status.containerStatuses[0].ready}'" \
  "^true$"

echo ""
sep

# ════════════════════════════════════════════════════════════════
# 최종 결과
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${BOLD}채점 결과:  PASS ${PASS} / TOTAL ${TOTAL}${RESET}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}🎉 모든 문제 통과! 완벽합니다.${RESET}"
else
  echo -e "  ${RED}${BOLD}실패 항목: ${FAIL}개${RESET}"
  echo -e "  위 [FAIL] 항목을 수정하고 다시 ${CYAN}bash verify.sh${RESET} 를 실행하세요."
  echo ""
  echo -e "  ${ORANGE}힌트: bash exam-start.sh --hints 로 도움말을 확인하세요.${RESET}"
fi

echo ""
sep
echo ""

# DNS 수동 검증 안내 (P4 Running 시)
if kubectl get pod dns-test -n default &>/dev/null; then
  DNS_STATUS=$(kubectl get pod dns-test -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [[ "$DNS_STATUS" == "Running" ]]; then
    echo -e "  ${CYAN}[DNS 수동 검증]${RESET}  다음 명령으로 DNS 해석을 직접 확인하세요:"
    echo -e "  kubectl exec -it dns-test -- nslookup web-svc"
    echo -e "  kubectl exec -it dns-test -- nslookup web-svc.default.svc.cluster.local"
    echo ""
  fi
fi

exit $FAIL
