#!/usr/bin/env bash
# CKA 1세션 확인 실습 채점 스크립트
# 사용법: bash verify.sh
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; ORANGE='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

SET="s"          # s = 1일차 숙제(S1~S3) / e = 오늘 시험(E1~E3) / all = 전체
for arg in "$@"; do
  case "$arg" in
    --exam) SET="e" ;;
    --all)  SET="all" ;;
  esac
done

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
if [[ "$SET" == "e" ]]; then
  echo -e "  ${BOLD}CKA 2세션 시험 채점${RESET}"
else
  echo -e "  ${BOLD}CKA 1세션 확인 실습 채점${RESET}"
fi
sep

if [[ "$SET" == "s" || "$SET" == "all" ]]; then

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

fi   # ── S1~S3 채점 끝

if [[ "$SET" == "e" || "$SET" == "all" ]]; then

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

echo ""
sep
echo -e "  ${BOLD}오늘의 시험 채점 — 2세션 범위${RESET}"
sep

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

fi   # ── E1~E3 채점 끝


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
