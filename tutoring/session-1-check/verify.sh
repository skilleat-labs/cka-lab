#!/usr/bin/env bash
# CKA 1세션 확인 실습 채점 스크립트
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
echo -e "  ${BOLD}CKA 1세션 확인 실습 채점${RESET}"
sep

# ════════════════════════════════════════════════════════════════
# P1: 명령어로 Pod 생성 + 레이블 부착
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}[P1] 명령어로 Pod 생성 + 레이블 부착${RESET}"

check \
  "web-pod Pod가 default 네임스페이스에 존재한다" \
  "kubectl get pod web-pod -n default"

check_output \
  "web-pod 이미지가 nginx:1.24이다" \
  "kubectl get pod web-pod -n default -o jsonpath='{.spec.containers[0].image}'" \
  "^nginx:1\.24$"

check_output \
  "web-pod가 Running 상태이다" \
  "kubectl get pod web-pod -n default -o jsonpath='{.status.phase}'" \
  "^Running$"

check_output \
  "web-pod가 Ready 상태이다" \
  "kubectl get pod web-pod -n default -o jsonpath='{.status.containerStatuses[0].ready}'" \
  "^true$"

check_output \
  "web-pod containerPort 80이 노출되어 있다 (--port=80)" \
  "kubectl get pod web-pod -n default -o jsonpath='{.spec.containers[0].ports[0].containerPort}'" \
  "^80$"

check_output \
  "web-pod에 환경변수 APP_ENV=prod가 설정되어 있다 (--env)" \
  "kubectl get pod web-pod -n default -o jsonpath='{range .spec.containers[0].env[*]}{.name}={.value}{\"\\n\"}{end}'" \
  "^APP_ENV=prod$"

check_output \
  "kubectl run으로 생성한 흔적(run=web-pod 레이블)이 남아 있다" \
  "kubectl get pod web-pod -n default -o jsonpath='{.metadata.labels.run}'" \
  "^web-pod$"

check_output \
  "web-pod에 레이블 tier=frontend가 붙어 있다 (kubectl label)" \
  "kubectl get pod web-pod -n default -o jsonpath='{.metadata.labels.tier}'" \
  "^frontend$"

check_output \
  "web-pod에 레이블 env=production이 붙어 있다 (kubectl label)" \
  "kubectl get pod web-pod -n default -o jsonpath='{.metadata.labels.env}'" \
  "^production$"

check_output \
  "레이블 셀렉터 -l env=production 으로 web-pod가 조회된다" \
  "kubectl get pods -n default -l env=production -o jsonpath='{.items[*].metadata.name}'" \
  "web-pod"

echo ""
sep

# ════════════════════════════════════════════════════════════════
# P2: 명령어로 Deployment 생성 + 스케일
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${ORANGE}[P2] 명령어로 Deployment 생성 + 스케일${RESET}"

check \
  "web-app Deployment가 default 네임스페이스에 존재한다" \
  "kubectl get deployment web-app -n default"

check_output \
  "web-app 이미지가 nginx:1.24이다" \
  "kubectl get deployment web-app -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" \
  "^nginx:1\.24$"

check_output \
  "web-app replicas가 4이다 (kubectl scale)" \
  "kubectl get deployment web-app -n default -o jsonpath='{.spec.replicas}'" \
  "^4$"

check_output \
  "web-app 파드 4개가 모두 Ready 상태이다" \
  "kubectl get deployment web-app -n default -o jsonpath='{.status.readyReplicas}'" \
  "^4$"

check_output \
  "web-app containerPort 80이 노출되어 있다 (--port=80)" \
  "kubectl get deployment web-app -n default -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'" \
  "^80$"

check_output \
  "web-app 파드 레이블이 app=web-app이다 (create deployment 기본값)" \
  "kubectl get deployment web-app -n default -o jsonpath='{.spec.selector.matchLabels.app}'" \
  "^web-app$"

check_output \
  "레이블 셀렉터 -l app=web-app 으로 파드 4개가 조회된다" \
  "kubectl get pods -n default -l app=web-app --no-headers 2>/dev/null | wc -l | tr -d ' '" \
  "^4$"

echo ""
sep

# ════════════════════════════════════════════════════════════════
# P3: 명령어로 Service 붙이기
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[P3] Deployment에 Service 연결${RESET}"

check \
  "web-svc Service가 default 네임스페이스에 존재한다" \
  "kubectl get service web-svc -n default"

check_output \
  "web-svc 타입이 ClusterIP이다" \
  "kubectl get service web-svc -n default -o jsonpath='{.spec.type}'" \
  "^ClusterIP$"

check_output \
  "web-svc port가 80이다" \
  "kubectl get service web-svc -n default -o jsonpath='{.spec.ports[0].port}'" \
  "^80$"

check_output \
  "web-svc targetPort가 80이다" \
  "kubectl get service web-svc -n default -o jsonpath='{.spec.ports[0].targetPort}'" \
  "^80$"

check_output \
  "web-svc selector가 app=web-app이다 (Deployment와 연결됨)" \
  "kubectl get service web-svc -n default -o jsonpath='{.spec.selector.app}'" \
  "^web-app$"

# Endpoints — 파드 IP가 실제로 4개 등록됐는지 (EndpointSlice/Endpoints 모두 대응)
EP_COUNT=$(kubectl get endpoints web-svc -n default -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
TOTAL=$((TOTAL+1))
if [[ "${EP_COUNT}" == "4" ]]; then
  echo -e "  ${GREEN}[PASS]${RESET} web-svc Endpoints에 파드 IP 4개가 등록되어 있다"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}[FAIL]${RESET} web-svc Endpoints에 파드 IP 4개가 등록되어 있다  ${ORANGE}(실제: ${EP_COUNT}개)${RESET}"
  echo -e "         ${ORANGE}→ Endpoints가 0개면 Service selector와 파드 레이블이 어긋난 것입니다.${RESET}"
  FAIL=$((FAIL+1))
fi

echo ""
sep

# ════════════════════════════════════════════════════════════════
# 실제 통신 검증 (상태가 아닌 실제 트래픽으로 채점)
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${CYAN}[통신 검증] 임시 파드에서 web-svc로 실제 HTTP 요청${RESET}"

kubectl delete pod svc-check -n default --ignore-not-found &>/dev/null || true

TOTAL=$((TOTAL+1))
CURL_OUT=$(kubectl run svc-check -n default --image=busybox:1.36 --restart=Never --rm -i \
  --timeout=90s --command -- wget -qO- --timeout=5 http://web-svc 2>/dev/null || echo "")

if echo "$CURL_OUT" | grep -qi "nginx"; then
  echo -e "  ${GREEN}[PASS]${RESET} 클러스터 내부에서 http://web-svc 접속 성공 (nginx 응답 확인)"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}[FAIL]${RESET} 클러스터 내부에서 http://web-svc 접속 실패"
  echo -e "         ${ORANGE}→ 확인: kubectl get endpoints web-svc / kubectl describe svc web-svc${RESET}"
  echo -e "         ${ORANGE}→ CoreDNS 상태: kubectl get pods -n kube-system -l k8s-app=kube-dns${RESET}"
  FAIL=$((FAIL+1))
fi
kubectl delete pod svc-check -n default --ignore-not-found &>/dev/null || true

echo ""
sep

# ════════════════════════════════════════════════════════════════
# 최종 결과
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${BOLD}채점 결과:  PASS ${PASS} / TOTAL ${TOTAL}${RESET}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}모든 항목 통과! 명령어로 Pod·Deployment·Service를 다룰 수 있습니다.${RESET}"
else
  echo -e "  ${RED}${BOLD}실패 항목: ${FAIL}개${RESET}"
  echo -e "  위 [FAIL] 항목을 수정하고 다시 ${CYAN}bash verify.sh${RESET} 를 실행하세요."
  echo -e "  ${ORANGE}힌트: bash exam-start.sh --hints${RESET}"
fi

echo ""
sep
echo ""

exit $FAIL
