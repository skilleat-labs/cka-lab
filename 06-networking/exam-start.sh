#!/usr/bin/env bash
# CKA 6강 실습 — 서비스와 네트워킹
# 사용법: bash exam-start.sh [--hints]
set -euo pipefail

HINTS=false
for arg in "$@"; do
  [[ "$arg" == "--hints" ]] && HINTS=true
done

# ── 색상 정의 ────────────────────────────────────────────────────
RED='\033[0;31m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

sep() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

echo ""
sep
echo -e "  ${BOLD}CKA 6강 실습 — 서비스와 네트워킹${RESET}"
echo -e "  ClusterIP · NodePort · NetworkPolicy · DNS"
sep

# ── 기존 리소스 정리 ─────────────────────────────────────────────
echo -e "\n${CYAN}[CLEANUP] 기존 실습 리소스를 정리합니다...${RESET}"
kubectl delete deployment web api backend -n default --ignore-not-found 2>/dev/null || true
kubectl delete service web-svc api-svc -n default --ignore-not-found 2>/dev/null || true
kubectl delete networkpolicy backend-policy -n default --ignore-not-found 2>/dev/null || true
kubectl delete pod dns-test -n default --ignore-not-found 2>/dev/null || true
echo -e "${GREEN}[CLEANUP] 완료${RESET}"

echo ""
sep

# ════════════════════════════════════════════════════════════════
# P1: ClusterIP 서비스
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}[P1] ClusterIP 서비스${RESET}\n"
echo -e "${BOLD}문제:${RESET}"
echo -e "  1) ${BOLD}web${RESET} Deployment를 ${BOLD}default${RESET} 네임스페이스에 생성하시오."
echo -e "     - 이미지: nginx:1.24"
echo -e "     - 레플리카: 3"
echo -e "     - 레이블: app=web"
echo ""
echo -e "  2) ${BOLD}web-svc${RESET} ClusterIP Service를 생성하시오."
echo -e "     - 타입: ClusterIP (생략 가능)"
echo -e "     - selector: app=web"
echo -e "     - port: 80 → targetPort: 80"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get deployment web"
echo -e "  kubectl get svc web-svc"
echo -e "  kubectl get endpoints web-svc   # Pod IP 3개 확인"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT P1]${RESET}"
  echo -e "  # Deployment 빠른 생성:"
  echo -e "  kubectl create deployment web --image=nginx:1.24 --replicas=3"
  echo -e "  # Service 빠른 생성:"
  echo -e "  kubectl expose deployment web --name=web-svc --port=80 --target-port=80 --type=ClusterIP"
  echo ""
  echo -e "  # 또는 YAML로 생성:"
  echo -e "  cat <<'EOF' | kubectl apply -f -"
  echo -e "  apiVersion: v1"
  echo -e "  kind: Service"
  echo -e "  metadata:"
  echo -e "    name: web-svc"
  echo -e "    namespace: default"
  echo -e "  spec:"
  echo -e "    type: ClusterIP"
  echo -e "    selector:"
  echo -e "      app: web"
  echo -e "    ports:"
  echo -e "    - port: 80"
  echo -e "      targetPort: 80"
  echo -e "  EOF"
fi

sep

# ════════════════════════════════════════════════════════════════
# P2: NodePort 서비스
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${ORANGE}[P2] NodePort 서비스${RESET}\n"
echo -e "${BOLD}문제:${RESET}"
echo -e "  1) ${BOLD}api${RESET} Deployment를 ${BOLD}default${RESET} 네임스페이스에 생성하시오."
echo -e "     - 이미지: nginx:1.24"
echo -e "     - 레플리카: 2"
echo -e "     - 레이블: app=api"
echo ""
echo -e "  2) ${BOLD}api-svc${RESET} NodePort Service를 생성하시오."
echo -e "     - 타입: NodePort"
echo -e "     - selector: app=api"
echo -e "     - port: 80 → targetPort: 80"
echo -e "     - nodePort: ${BOLD}30080${RESET}  (반드시 이 값 사용)"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get svc api-svc   # PORT(S): 80:30080/TCP 확인"
echo -e "  kubectl get nodes -o wide # 노드 IP 확인 후 curl http://<NodeIP>:30080"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT P2]${RESET}"
  echo -e "  # kubectl expose는 nodePort 지정 불가 → YAML 사용 권장"
  echo -e "  kubectl create deployment api --image=nginx:1.24 --replicas=2"
  echo ""
  echo -e "  cat <<'EOF' | kubectl apply -f -"
  echo -e "  apiVersion: v1"
  echo -e "  kind: Service"
  echo -e "  metadata:"
  echo -e "    name: api-svc"
  echo -e "    namespace: default"
  echo -e "  spec:"
  echo -e "    type: NodePort"
  echo -e "    selector:"
  echo -e "      app: api"
  echo -e "    ports:"
  echo -e "    - port: 80"
  echo -e "      targetPort: 80"
  echo -e "      nodePort: 30080"
  echo -e "  EOF"
fi

sep

# ════════════════════════════════════════════════════════════════
# P3: NetworkPolicy
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${RED}[P3] NetworkPolicy${RESET}\n"
echo -e "${BOLD}문제:${RESET}"
echo -e "  1) ${BOLD}backend${RESET} Deployment를 생성하시오."
echo -e "     - 이미지: nginx:1.24"
echo -e "     - 레플리카: 1"
echo -e "     - 레이블: app=backend"
echo ""
echo -e "  2) ${BOLD}backend-policy${RESET} NetworkPolicy를 생성하시오."
echo -e "     - 적용 대상: app=backend 레이블 Pod"
echo -e "     - policyTypes: Ingress"
echo -e "     - 허용 인그레스: app=${BOLD}frontend${RESET} 레이블 Pod에서 오는 트래픽만 허용"
echo -e "     - 다른 모든 파드에서의 인바운드는 차단"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get networkpolicy backend-policy"
echo -e "  kubectl describe networkpolicy backend-policy"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT P3]${RESET}"
  echo -e "  kubectl create deployment backend --image=nginx:1.24 --replicas=1"
  echo ""
  echo -e "  cat <<'EOF' | kubectl apply -f -"
  echo -e "  apiVersion: networking.k8s.io/v1"
  echo -e "  kind: NetworkPolicy"
  echo -e "  metadata:"
  echo -e "    name: backend-policy"
  echo -e "    namespace: default"
  echo -e "  spec:"
  echo -e "    podSelector:"
  echo -e "      matchLabels:"
  echo -e "        app: backend"
  echo -e "    policyTypes:"
  echo -e "    - Ingress"
  echo -e "    ingress:"
  echo -e "    - from:"
  echo -e "      - podSelector:"
  echo -e "          matchLabels:"
  echo -e "            app: frontend"
  echo -e "  EOF"
fi

sep

# ════════════════════════════════════════════════════════════════
# P4: DNS 검증
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[P4] DNS 검증${RESET}\n"
echo -e "${BOLD}문제:${RESET}"
echo -e "  1) ${BOLD}dns-test${RESET} Pod를 생성하시오."
echo -e "     - 이미지: busybox:1.36"
echo -e "     - command: sleep 3600"
echo -e "     - 네임스페이스: default"
echo ""
echo -e "  2) Pod 내부에서 nslookup을 실행해 ${BOLD}web-svc${RESET} DNS가 해석되는지 확인하시오."
echo -e "     - 기대 결과: web-svc의 ClusterIP가 반환되어야 함"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get pod dns-test   # Running 상태 확인"
echo -e "  kubectl exec -it dns-test -- nslookup web-svc"
echo -e "  kubectl exec -it dns-test -- nslookup web-svc.default.svc.cluster.local"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT P4]${RESET}"
  echo -e "  # 명령어로 빠른 생성:"
  echo -e "  kubectl run dns-test --image=busybox:1.36 --command -- sleep 3600"
  echo ""
  echo -e "  # 또는 YAML:"
  echo -e "  cat <<'EOF' | kubectl apply -f -"
  echo -e "  apiVersion: v1"
  echo -e "  kind: Pod"
  echo -e "  metadata:"
  echo -e "    name: dns-test"
  echo -e "    namespace: default"
  echo -e "  spec:"
  echo -e "    containers:"
  echo -e "    - name: dns-test"
  echo -e "      image: busybox:1.36"
  echo -e "      command: [\"sleep\", \"3600\"]"
  echo -e "  EOF"
fi

sep
echo ""
echo -e "${BOLD}실습 준비 완료!${RESET}  문제를 풀고 ${CYAN}bash verify.sh${RESET} 로 채점하세요."
echo ""
