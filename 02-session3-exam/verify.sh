#!/usr/bin/env bash
# CKA 3세션 시험 채점 스크립트
# 사용법: bash verify.sh
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; ORANGE='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

PASS=0; FAIL=0; TOTAL=0; SKIP=0

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
MODE_FILE="$WORK_DIR/.gateway-mode"
GW_MODE="none"
[[ -f "$MODE_FILE" ]] && GW_MODE="$(cat "$MODE_FILE" 2>/dev/null || echo none)"

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

skip() {
  SKIP=$((SKIP+1))
  echo -e "  ${ORANGE}[SKIP]${RESET} $1"
}

echo ""
sep
echo -e "  ${BOLD}CKA 3세션 시험 채점${RESET}"
sep

# ════════════════════════════════════════════════════════════════
# Q1: Deployment + Service
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}[Q1] Deployment 와 Service 연결${RESET}"

check \
  "shop-web Deployment 가 shop 네임스페이스에 존재한다" \
  "kubectl get deployment shop-web -n shop"

check_output \
  "shop-web 이미지가 nginx:1.24 이다" \
  "kubectl get deployment shop-web -n shop -o jsonpath='{.spec.template.spec.containers[0].image}'" \
  "^nginx:1\.24$"

check_output \
  "shop-web replicas 가 2 이다" \
  "kubectl get deployment shop-web -n shop -o jsonpath='{.spec.replicas}'" \
  "^2$"

check_output \
  "shop-web 파드 2개가 모두 Ready 이다" \
  "kubectl get deployment shop-web -n shop -o jsonpath='{.status.readyReplicas}'" \
  "^2$"

check_output \
  "shop-web containerPort 80 이 노출되어 있다" \
  "kubectl get deployment shop-web -n shop -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'" \
  "^80$"

check \
  "shop-svc Service 가 shop 네임스페이스에 존재한다" \
  "kubectl get service shop-svc -n shop"

check_output \
  "shop-svc 타입이 ClusterIP 이다" \
  "kubectl get service shop-svc -n shop -o jsonpath='{.spec.type}'" \
  "^ClusterIP$"

check_output \
  "shop-svc port 가 80 이다" \
  "kubectl get service shop-svc -n shop -o jsonpath='{.spec.ports[0].port}'" \
  "^80$"

check_output \
  "shop-svc targetPort 가 80 이다" \
  "kubectl get service shop-svc -n shop -o jsonpath='{.spec.ports[0].targetPort}'" \
  "^80$"

EP=$(kubectl get endpoints shop-svc -n shop -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
TOTAL=$((TOTAL+1))
if [[ "$EP" == "2" ]]; then
  echo -e "  ${GREEN}[PASS]${RESET} shop-svc Endpoints 에 파드 IP 2개가 등록되어 있다"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}[FAIL]${RESET} shop-svc Endpoints 에 파드 IP 2개가 등록되어 있다  ${ORANGE}(실제: ${EP}개 — selector 확인)${RESET}"
  FAIL=$((FAIL+1))
fi

# 실제 통신 검증
kubectl delete pod svc-probe -n shop --ignore-not-found &>/dev/null || true
TOTAL=$((TOTAL+1))
PROBE=$(kubectl run svc-probe -n shop --image=busybox:1.36 --restart=Never --rm -i \
  --timeout=90s --command -- wget -qO- --timeout=5 http://shop-svc 2>/dev/null || echo "")
if echo "$PROBE" | grep -qi "nginx"; then
  echo -e "  ${GREEN}[PASS]${RESET} 클러스터 내부에서 http://shop-svc 접속 성공 (실제 통신 검증)"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}[FAIL]${RESET} 클러스터 내부에서 http://shop-svc 접속 실패"
  FAIL=$((FAIL+1))
fi
kubectl delete pod svc-probe -n shop --ignore-not-found &>/dev/null || true

echo ""
sep

# ════════════════════════════════════════════════════════════════
# Q2: StorageClass → PVC → Deployment 연결
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${ORANGE}[Q2] StorageClass 로 PVC 생성 후 Deployment 연결${RESET}"

check \
  "shop-data PVC 가 shop 네임스페이스에 존재한다" \
  "kubectl get pvc shop-data -n shop"

check_output \
  "shop-data 가 exam-storage StorageClass 를 사용한다" \
  "kubectl get pvc shop-data -n shop -o jsonpath='{.spec.storageClassName}'" \
  "^exam-storage$"

check_output \
  "shop-data accessModes 가 ReadWriteOnce 이다" \
  "kubectl get pvc shop-data -n shop -o jsonpath='{.spec.accessModes[0]}'" \
  "^ReadWriteOnce$"

check_output \
  "shop-data 요청 용량이 1Gi 이다" \
  "kubectl get pvc shop-data -n shop -o jsonpath='{.spec.resources.requests.storage}'" \
  "^1Gi$"

check_output \
  "shop-data 가 Bound 상태이다" \
  "kubectl get pvc shop-data -n shop -o jsonpath='{.status.phase}'" \
  "^Bound$"

check_output \
  "shop-data 가 exam-pv-* PV 에 바인딩되었다" \
  "kubectl get pvc shop-data -n shop -o jsonpath='{.spec.volumeName}'" \
  "^exam-pv-[123]$"

check_output \
  "shop-web Deployment 가 shop-data PVC 를 볼륨으로 참조한다" \
  "kubectl get deployment shop-web -n shop -o jsonpath='{.spec.template.spec.volumes[*].persistentVolumeClaim.claimName}'" \
  "shop-data"

check_output \
  "shop-web 컨테이너가 /data 에 마운트하고 있다" \
  "kubectl get deployment shop-web -n shop -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}'" \
  "/data"

# 파드 내부에서 실제 쓰기/읽기 검증
TOTAL=$((TOTAL+1))
POD=$(kubectl get pods -n shop -l app=shop-web -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
PROBE2=""
if [[ -n "$POD" ]]; then
  PROBE2=$(kubectl exec "$POD" -n shop -- sh -c 'echo mounted > /data/.probe && cat /data/.probe' 2>/dev/null || echo "")
fi
if echo "$PROBE2" | grep -q "^mounted$"; then
  echo -e "  ${GREEN}[PASS]${RESET} 파드 내부 /data 에 실제로 쓰고 읽을 수 있다 (실제 마운트 검증)"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}[FAIL]${RESET} 파드 내부 /data 에 실제로 쓰고 읽을 수 있다  ${ORANGE}(볼륨이 마운트되지 않았거나 파드가 없음)${RESET}"
  FAIL=$((FAIL+1))
fi

echo ""
sep

# ════════════════════════════════════════════════════════════════
# Q3: Gateway API 외부 노출
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[Q3] Gateway API 외부 노출${RESET}"

if [[ "$GW_MODE" == "none" ]]; then
  echo -e "  ${ORANGE}Gateway API 가 설치되지 않아 Q3 채점을 건너뜁니다.${RESET}"
  echo -e "  ${ORANGE}bash exam-start.sh 를 인터넷 연결 상태에서 다시 실행하세요.${RESET}"
  SKIP=$((SKIP+8))
else
  check \
    "shop-gw Gateway 가 shop 네임스페이스에 존재한다" \
    "kubectl get gateway shop-gw -n shop"

  check_output \
    "shop-gw 의 gatewayClassName 이 nginx 이다" \
    "kubectl get gateway shop-gw -n shop -o jsonpath='{.spec.gatewayClassName}'" \
    "^nginx$"

  check_output \
    "shop-gw 리스너 포트가 80 이다" \
    "kubectl get gateway shop-gw -n shop -o jsonpath='{.spec.listeners[0].port}'" \
    "^80$"

  check_output \
    "shop-gw 리스너 프로토콜이 HTTP 이다" \
    "kubectl get gateway shop-gw -n shop -o jsonpath='{.spec.listeners[0].protocol}'" \
    "^HTTP$"

  check \
    "shop-route HTTPRoute 가 shop 네임스페이스에 존재한다" \
    "kubectl get httproute shop-route -n shop"

  check_output \
    "shop-route 가 shop-gw Gateway 에 연결되어 있다" \
    "kubectl get httproute shop-route -n shop -o jsonpath='{.spec.parentRefs[*].name}'" \
    "shop-gw"

  check_output \
    "shop-route 의 backendRef 가 shop-svc 이다" \
    "kubectl get httproute shop-route -n shop -o jsonpath='{.spec.rules[0].backendRefs[0].name}'" \
    "^shop-svc$"

  check_output \
    "shop-route 의 backendRef 포트가 80 이다" \
    "kubectl get httproute shop-route -n shop -o jsonpath='{.spec.rules[0].backendRefs[0].port}'" \
    "^80$"

  if [[ "$GW_MODE" == "full" ]]; then
    check_output \
      "shop-gw 가 컨트롤러에 의해 Accepted 되었다" \
      "kubectl get gateway shop-gw -n shop -o jsonpath='{.status.conditions[?(@.type==\"Accepted\")].status}'" \
      "True"

    check_output \
      "shop-route 의 참조가 정상 해석되었다 (ResolvedRefs)" \
      "kubectl get httproute shop-route -n shop -o jsonpath='{.status.parents[0].conditions[?(@.type==\"ResolvedRefs\")].status}'" \
      "True"

    # nodePort 30081 서비스 확인 (게이트웨이가 만든 Service 이름은 환경마다 다르므로 값으로 찾는다)
    TOTAL=$((TOTAL+1))
    NP_SVC=$(kubectl get svc -n shop -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.type}{" "}{.spec.ports[*].nodePort}{"\n"}{end}' 2>/dev/null | awk '$2=="NodePort" && $0 ~ /30081/ {print $1}' | head -1)
    if [[ -n "$NP_SVC" ]]; then
      echo -e "  ${GREEN}[PASS]${RESET} nodePort 30081 로 노출된 Service 가 있다 (${NP_SVC})"
      PASS=$((PASS+1))
    else
      echo -e "  ${RED}[FAIL]${RESET} nodePort 30081 로 노출된 Service 가 있다  ${ORANGE}(kubectl get svc -n shop 확인)${RESET}"
      FAIL=$((FAIL+1))
    fi

    # 실제 외부 접속 검증
    TOTAL=$((TOTAL+1))
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | awk '{print $1}')
    GW_RESP=""
    if [[ -n "$NODE_IP" ]]; then
      if command -v curl &>/dev/null; then
        GW_RESP=$(curl -s --max-time 8 "http://${NODE_IP}:30081" 2>/dev/null || echo "")
      else
        GW_RESP=$(wget -qO- --timeout=8 "http://${NODE_IP}:30081" 2>/dev/null || echo "")
      fi
    fi
    if echo "$GW_RESP" | grep -qi "nginx"; then
      echo -e "  ${GREEN}[PASS]${RESET} 외부에서 http://${NODE_IP}:30081 접속 성공 (실제 트래픽 검증)"
      PASS=$((PASS+1))
    else
      echo -e "  ${RED}[FAIL]${RESET} 외부에서 http://${NODE_IP:-NodeIP}:30081 접속 실패"
      echo -e "         ${ORANGE}→ kubectl describe gateway shop-gw -n shop 로 Programmed 상태 확인${RESET}"
      echo -e "         ${ORANGE}→ kubectl get pods -n shop 로 게이트웨이 파드 기동 확인${RESET}"
      FAIL=$((FAIL+1))
    fi
  else
    skip "shop-gw Accepted 상태 (컨트롤러 미설치)"
    skip "shop-route ResolvedRefs 상태 (컨트롤러 미설치)"
    skip "nodePort 30081 Service (컨트롤러 미설치)"
    skip "외부 접속 실제 검증 (컨트롤러 미설치)"
  fi
fi

echo ""
sep

# ════════════════════════════════════════════════════════════════
# 최종 결과
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${BOLD}채점 결과:  PASS ${PASS} / TOTAL ${TOTAL}${RESET}"
[[ $SKIP -gt 0 ]] && echo -e "  ${ORANGE}건너뛴 항목: ${SKIP}개 (Gateway API 환경 미준비)${RESET}"
echo ""

if [[ $FAIL -eq 0 && $TOTAL -gt 0 ]]; then
  echo -e "  ${GREEN}${BOLD}전 항목 통과! Deployment·Service·PVC·Gateway API 모두 정확합니다.${RESET}"
else
  echo -e "  ${RED}${BOLD}실패 항목: ${FAIL}개${RESET}"
  echo -e "  위 [FAIL] 항목을 수정하고 다시 ${CYAN}bash verify.sh${RESET} 를 실행하세요."
  echo -e "  ${ORANGE}복습이 필요하면: bash exam-start.sh --hints${RESET}"
fi

echo ""
sep
echo ""

exit $FAIL
