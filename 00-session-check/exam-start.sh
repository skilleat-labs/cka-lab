#!/usr/bin/env bash
# CKA 1세션 확인 실습 — 명령어(imperative)로 Pod / Deployment / Service 만들기
# 사용법: bash exam-start.sh [--hints]
set -euo pipefail

HINTS=false
for arg in "$@"; do [[ "$arg" == "--hints" ]] && HINTS=true; done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

RED='\033[0;31m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

sep() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

echo ""
sep
echo -e "  ${BOLD}CKA 1세션 확인 실습 — 명령어로 만들 수 있는가${RESET}"
echo -e "  kubectl run · kubectl label · kubectl create deployment · kubectl expose"
sep

# ── 클러스터 연결 확인 ────────────────────────────────────────────
echo -e "\n${CYAN}[INFO] 현재 노드 상태:${RESET}"
kubectl get nodes -o wide 2>/dev/null || {
  echo -e "${RED}[ERROR] kubectl을 실행할 수 없습니다. kubeconfig를 확인하세요.${RESET}"
  exit 1
}

# ── 기존 리소스 정리 ─────────────────────────────────────────────
echo -e "\n${CYAN}[CLEANUP] 기존 실습 리소스를 정리합니다...${RESET}"
kubectl delete pod web-pod -n default --ignore-not-found 2>/dev/null || true
kubectl delete deployment web-app -n default --ignore-not-found 2>/dev/null || true
kubectl delete service web-svc -n default --ignore-not-found 2>/dev/null || true
kubectl delete pod svc-check -n default --ignore-not-found 2>/dev/null || true
echo -e "${GREEN}[CLEANUP] 완료${RESET}"

echo ""
sep

# ════════════════════════════════════════════════════════════════
# P1: 명령어로 Pod 생성 + 명령어로 레이블 부착
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}[P1] 명령어로 Pod를 만들고, 명령어로 레이블을 붙인다${RESET}\n"
echo -e "${BOLD}문제:${RESET}"
echo -e "  1) ${BOLD}web-pod${RESET} Pod를 ${BOLD}kubectl run 명령어로${RESET} default 네임스페이스에 생성하시오."
echo -e "     - 이미지: ${BOLD}nginx:1.24${RESET}"
echo -e "     - 컨테이너 포트: ${BOLD}80${RESET} 노출"
echo -e "     - 환경변수: ${BOLD}APP_ENV=prod${RESET}"
echo -e "     - ${ORANGE}조건: YAML 파일을 만들지 말고 한 줄 명령어로 생성할 것${RESET}"
echo -e "       (kubectl run이 자동으로 붙이는 ${BOLD}run=web-pod${RESET} 레이블이 남아 있어야 함)"
echo ""
echo -e "  2) 생성이 끝난 뒤 ${BOLD}kubectl label 명령어로${RESET} 아래 레이블 2개를 추가하시오."
echo -e "     - ${BOLD}tier=frontend${RESET}"
echo -e "     - ${BOLD}env=production${RESET}"
echo ""
echo -e "  3) ${BOLD}env=production${RESET} 레이블이 붙은 Pod만 조회해 결과를 확인하시오."
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get pod web-pod --show-labels"
echo -e "  kubectl get pods -l env=production"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT P1]${RESET}"
  echo -e "  # Pod 생성 (한 줄)"
  echo -e "  kubectl run web-pod --image=nginx:1.24 --port=80 --env=\"APP_ENV=prod\""
  echo ""
  echo -e "  # 레이블 추가 (한 번에 여러 개 가능)"
  echo -e "  kubectl label pod web-pod tier=frontend env=production"
  echo ""
  echo -e "  # 이미 있는 레이블 값을 바꿀 때는 --overwrite"
  echo -e "  kubectl label pod web-pod env=production --overwrite"
  echo ""
  echo -e "  # 레이블로 조회"
  echo -e "  kubectl get pods -l env=production"
fi

sep

# ════════════════════════════════════════════════════════════════
# P2: 명령어로 Deployment 생성 + 스케일
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${ORANGE}[P2] 명령어로 Deployment를 조건에 맞게 만든다${RESET}\n"
echo -e "${BOLD}문제:${RESET}"
echo -e "  1) ${BOLD}web-app${RESET} Deployment를 ${BOLD}kubectl create deployment 명령어로${RESET} 생성하시오."
echo -e "     - 네임스페이스: default"
echo -e "     - 이미지: ${BOLD}nginx:1.24${RESET}"
echo -e "     - 레플리카: ${BOLD}3${RESET}"
echo -e "     - 컨테이너 포트: ${BOLD}80${RESET} 노출"
echo ""
echo -e "  2) 생성 후 ${BOLD}kubectl scale 명령어로${RESET} 레플리카를 ${BOLD}4${RESET}로 늘리시오."
echo ""
echo -e "  3) 모든 파드가 Ready 상태가 될 때까지 롤아웃 상태를 확인하시오."
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get deployment web-app"
echo -e "  kubectl rollout status deployment/web-app"
echo -e "  kubectl get pods -l app=web-app"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT P2]${RESET}"
  echo -e "  # Deployment 생성 (--port로 containerPort까지 지정)"
  echo -e "  kubectl create deployment web-app --image=nginx:1.24 --replicas=3 --port=80"
  echo ""
  echo -e "  # 스케일"
  echo -e "  kubectl scale deployment web-app --replicas=4"
  echo ""
  echo -e "  # 롤아웃 확인"
  echo -e "  kubectl rollout status deployment/web-app"
  echo ""
  echo -e "  # 명령어를 YAML로 미리 보고 싶을 때 (실전 필수 기술)"
  echo -e "  kubectl create deployment web-app --image=nginx:1.24 --dry-run=client -o yaml"
fi

sep

# ════════════════════════════════════════════════════════════════
# P3: 명령어로 Service 붙이기
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[P3] P2의 Deployment에 명령어로 Service를 붙인다${RESET}\n"
echo -e "${BOLD}문제:${RESET}"
echo -e "  1) P2에서 만든 ${BOLD}web-app${RESET} Deployment를 ${BOLD}kubectl expose 명령어로${RESET} 노출하시오."
echo -e "     - Service 이름: ${BOLD}web-svc${RESET}"
echo -e "     - 타입: ${BOLD}ClusterIP${RESET}"
echo -e "     - port: ${BOLD}80${RESET} → targetPort: ${BOLD}80${RESET}"
echo -e "     - selector는 Deployment의 레이블(${BOLD}app=web-app${RESET})과 일치해야 함"
echo ""
echo -e "  2) Service의 Endpoints에 ${BOLD}파드 IP 4개${RESET}가 모두 등록됐는지 확인하시오."
echo ""
echo -e "  3) 임시 파드에서 ${BOLD}web-svc${RESET} 이름으로 HTTP 접속이 되는지 실제로 확인하시오."
echo -e "     (채점 스크립트가 동일한 통신 테스트를 수행합니다)"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get svc web-svc"
echo -e "  kubectl get endpoints web-svc"
echo -e "  kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- web-svc"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT P3]${RESET}"
  echo -e "  # Deployment를 그대로 노출 (selector 자동 설정)"
  echo -e "  kubectl expose deployment web-app --name=web-svc --port=80 --target-port=80 --type=ClusterIP"
  echo ""
  echo -e "  # Endpoints 확인 — 여기가 비어 있으면 selector가 틀린 것"
  echo -e "  kubectl get endpoints web-svc"
  echo -e "  kubectl describe svc web-svc"
  echo ""
  echo -e "  # 실제 통신 테스트"
  echo -e "  kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- web-svc"
  echo ""
  echo -e "  ${BOLD}포인트:${RESET} expose는 대상 리소스의 레이블을 selector로 그대로 복사한다."
  echo -e "  Service가 있는데 Endpoints가 비어 있으면 99% selector ↔ 파드 레이블 불일치다."
fi

sep
echo ""
echo -e "${BOLD}실습 준비 완료!${RESET}  문제를 풀고 ${CYAN}bash verify.sh${RESET} 로 채점하세요."
echo -e "힌트가 필요하면 ${CYAN}bash exam-start.sh --hints${RESET}"
echo ""
