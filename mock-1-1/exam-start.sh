#!/usr/bin/env bash
# ============================================================
# CKA Mock Exam 1-1 — 기초 워크로드 (mock-1 변형판)
# 실행: bash exam-start.sh
#
# mock-1 과 같은 7가지 유형이지만 이름·값·조건이 전부 다르다.
# mock-1 정답을 그대로 붙여넣으면 틀리도록 설계했다.
# ============================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

hr() { printf '%0.s─' {1..70}; echo; }

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

echo -e "${BOLD}${BLUE}"
hr
echo "  CKA Mock Exam 1-1 — 기초 워크로드 (변형판)"
echo "  문제 수: 7문항  |  총 배점: 100점  |  목표 시간: 40분"
hr
echo -e "${NC}"

# ── 클러스터 확인 ─────────────────────────────────────────────
kubectl get nodes &>/dev/null || {
  echo -e "${RED}[ERROR] kubectl 을 실행할 수 없습니다. kubeconfig 를 확인하세요.${NC}"
  exit 1
}

# ── 정리 ─────────────────────────────────────────────────────
echo -e "${YELLOW}[준비] 이전 실습 리소스 정리 중...${NC}"
if kubectl get namespace retail &>/dev/null; then
  kubectl delete namespace retail --wait=true &>/dev/null || true
fi
kubectl delete pv report-pv --ignore-not-found &>/dev/null || true
kubectl uncordon worker-2 &>/dev/null || true
echo -e "${GREEN}[준비] 정리 완료${NC}"
echo ""

# ── 환경 세팅 ─────────────────────────────────────────────────
echo -e "${YELLOW}[환경 세팅] retail 네임스페이스 생성${NC}"
kubectl create namespace retail &>/dev/null || true

echo -e "${YELLOW}[환경 세팅] Q7 용 고장난 파드 생성 중...${NC}"
# 이미지 저장소 이름 오타 (nginz) → ImagePullBackOff
kubectl run web-broken --image=nginz:1.24 --restart=Never -n retail &>/dev/null || true
echo -e "${GREEN}[환경 세팅] 완료${NC}"
echo ""

hr
echo -e "  ${BOLD}시험 시작! 아래 7문제를 순서대로 풀어보세요.${NC}"
echo -e "  ${CYAN}문제지: cat QUESTIONS.txt${NC}"
hr
echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${GREEN}Q1. Deployment 생성 [Workloads · 15점]${NC}"
hr
cat << 'EOF'
retail 네임스페이스에 다음 조건으로 Deployment 를 생성하세요.

  • 이름: store-front
  • 이미지: nginx:1.25
  • 복제본: 4
  • 컨테이너 포트: 80

[ 검증 ]
  - kubectl get deployment store-front -n retail   → READY 4/4
EOF
echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${GREEN}Q2. Service 생성 [Networking · 10점]${NC}"
hr
cat << 'EOF'
Q1 의 Deployment 를 노출하는 Service 를 생성하세요.

  • 이름: store-svc
  • 타입: ClusterIP
  • port: 8080  →  targetPort: 80     (포트가 다르다는 점에 주의)
  • 셀렉터: app=store-front
  • 네임스페이스: retail

[ 검증 ]
  - kubectl get svc store-svc -n retail        → PORT(S) 8080/TCP
  - kubectl get endpoints store-svc -n retail  → Pod IP 4개
EOF
echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${GREEN}Q3. ConfigMap + Pod [Workloads · 10점]${NC}"
hr
cat << 'EOF'
retail 네임스페이스에서 다음 두 가지 작업을 수행하세요.

  (1) ConfigMap 생성
      • 이름: store-config
      • 데이터:
          APP_MODE=staging
          APP_PORT=9090

  (2) Pod 생성
      • 이름: store-cfg
      • 이미지: busybox:1.36
      • 명령: sleep 7200
      • store-config 전체를 envFrom 으로 주입

[ 검증 ]
  - kubectl exec store-cfg -n retail -- printenv APP_MODE   → staging
  - kubectl exec store-cfg -n retail -- printenv APP_PORT   → 9090
EOF
echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${GREEN}Q4. PersistentVolume + PVC [Storage · 15점]${NC}"
hr
cat << 'EOF'
다음 조건으로 PV 와 PVC 를 생성하고 Bound 시키세요.

  PersistentVolume
    • 이름: report-pv
    • 용량: 1Gi
    • 접근 모드: ReadWriteMany
    • 타입: hostPath, path=/tmp/report-data
    • storageClassName: local-manual

  PersistentVolumeClaim
    • 이름: report-pvc
    • 네임스페이스: retail
    • 용량 요청: 1Gi
    • 접근 모드: ReadWriteMany
    • storageClassName: local-manual

[ 검증 ]
  - kubectl get pv report-pv              → STATUS Bound
  - kubectl get pvc report-pvc -n retail  → STATUS Bound
EOF
echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${GREEN}Q5. RBAC [Architecture · 15점]${NC}"
hr
cat << 'EOF'
retail 네임스페이스에 다음 세 가지 RBAC 리소스를 생성하세요.

  ServiceAccount
    • 이름: deploy-sa

  Role
    • 이름: deploy-reader
    • 리소스: deployments      (apps API 그룹)
    • 동사(verbs): get, list, watch

  RoleBinding
    • 이름: deploy-reader-rb
    • Role: deploy-reader
    • Subject: ServiceAccount deploy-sa

[ 검증 ]
  - kubectl auth can-i list deployments \
      --as=system:serviceaccount:retail:deploy-sa -n retail   → yes
  - kubectl auth can-i list pods \
      --as=system:serviceaccount:retail:deploy-sa -n retail   → no
EOF
echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${GREEN}Q6. 노드 drain [Architecture · 10점]${NC}"
hr
cat << 'EOF'
다음 순서로 노드 유지보수 작업을 수행하세요.

  (1) worker-2 노드를 drain 합니다.
      • DaemonSet Pod 는 무시
      • emptyDir 데이터는 삭제 허용

  (2) 유지보수 완료 후 worker-2 를 다시 스케줄 가능 상태로 전환합니다.

[ 검증 ]
  - kubectl get nodes   → worker-2 가 Ready, SchedulingDisabled 아님
EOF
echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${GREEN}Q7. Pod 트러블슈팅 [Troubleshooting · 25점]${NC}"
hr
cat << 'EOF'
retail 네임스페이스의 web-broken Pod 가 ErrImagePull / ImagePullBackOff
상태입니다.

  작업:
    원인을 파악하고, 이미지를 nginx:1.24 로 수정하여 Pod 가 Running
    상태가 되도록 하세요.

[ 검증 ]
  - kubectl get pod web-broken -n retail   → STATUS Running
EOF
echo ""

hr
echo -e "  ${CYAN}채점: bash verify.sh${NC}"
hr
echo ""
