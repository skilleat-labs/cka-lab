#!/usr/bin/env bash
# ============================================================
# CKA Mock Exam 1 — 기초 워크로드
# 실행: bash exam-start.sh
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

hr() { printf '%0.s─' {1..70}; echo; }

echo -e "${BOLD}${BLUE}"
hr
echo "  CKA Mock Exam 1 — 기초 워크로드"
echo "  문제 수: 7문항  |  총 배점: 100점  |  목표 시간: 40분"
hr
echo -e "${NC}"

# ─── 이전 리소스 정리 ────────────────────────────────────────
echo -e "${YELLOW}[준비] 이전 실습 리소스 정리 중...${NC}"

kubectl delete deployment nginx-deploy --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
kubectl delete service nginx-svc --ignore-not-found=true 2>/dev/null || true
kubectl delete configmap app-config --ignore-not-found=true 2>/dev/null || true
kubectl delete pod config-pod --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
kubectl delete pvc task-pvc --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
kubectl delete pv task-pv --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
kubectl delete rolebinding app-rb --ignore-not-found=true 2>/dev/null || true
kubectl delete role app-role --ignore-not-found=true 2>/dev/null || true
kubectl delete serviceaccount app-sa --ignore-not-found=true 2>/dev/null || true
kubectl delete pod broken-app --ignore-not-found=true --force --grace-period=0 2>/dev/null || true

echo -e "${GREEN}[준비] 정리 완료${NC}"
echo ""

# ─── 환경 세팅: 트러블슈팅용 broken-app Pod 생성 ─────────────
echo -e "${YELLOW}[환경 세팅] Q7 환경 생성 중...${NC}"
kubectl run broken-app --image=nginx:broken --restart=Never 2>/dev/null || true

echo -e "${GREEN}[환경 세팅] 완료${NC}"
echo ""
echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}${CYAN}  시험 시작! 아래 7문제를 순서대로 풀어보세요.${NC}"
echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
echo ""

# ─── 문제 출력 ───────────────────────────────────────────────
echo -e "${BOLD}${GREEN}Q1. Deployment 생성 [Workloads · 15점]${NC}"
hr
cat << 'EOF'
다음 조건에 맞는 Deployment를 생성하세요.

  • 이름: nginx-deploy
  • 이미지: nginx:1.24
  • 복제본: 3
  • 네임스페이스: default

[ 검증 ]
  - kubectl get deployment nginx-deploy -n default
  - READY 컬럼이 3/3 이어야 합니다.
EOF
echo ""

echo -e "${BOLD}${GREEN}Q2. Service 생성 [Networking · 10점]${NC}"
hr
cat << 'EOF'
Q1에서 생성한 Deployment를 노출하는 Service를 생성하세요.

  • 이름: nginx-svc
  • 타입: ClusterIP
  • 포트: 80
  • 셀렉터: app=nginx-deploy
  • 네임스페이스: default

[ 검증 ]
  - kubectl get svc nginx-svc
  - kubectl get endpoints nginx-svc  → Pod IP 3개가 보여야 합니다.
EOF
echo ""

echo -e "${BOLD}${GREEN}Q3. ConfigMap + Pod [Workloads · 10점]${NC}"
hr
cat << 'EOF'
다음 두 가지 작업을 수행하세요.

  (1) ConfigMap 생성:
      • 이름: app-config
      • 데이터:
          APP_ENV=prod
          APP_PORT=8080

  (2) Pod 생성:
      • 이름: config-pod
      • 이미지: busybox
      • 명령: sleep 3600
      • app-config 전체를 envFrom으로 주입

[ 검증 ]
  - kubectl exec config-pod -- printenv APP_ENV   → prod
  - kubectl exec config-pod -- printenv APP_PORT  → 8080
EOF
echo ""

echo -e "${BOLD}${GREEN}Q4. PersistentVolume + PVC [Storage · 15점]${NC}"
hr
cat << 'EOF'
다음 조건으로 PV와 PVC를 생성하세요.

  PersistentVolume:
    • 이름: task-pv
    • 용량: 500Mi
    • 접근 모드: ReadWriteOnce
    • 타입: hostPath, path=/tmp/task-data
    • storageClassName: manual

  PersistentVolumeClaim:
    • 이름: task-pvc
    • 용량 요청: 500Mi
    • 접근 모드: ReadWriteOnce
    • storageClassName: manual

[ 검증 ]
  - kubectl get pv task-pv    → STATUS가 Bound
  - kubectl get pvc task-pvc  → STATUS가 Bound
EOF
echo ""

echo -e "${BOLD}${GREEN}Q5. RBAC [Architecture · 15점]${NC}"
hr
cat << 'EOF'
다음 세 가지 RBAC 리소스를 default 네임스페이스에 생성하세요.

  ServiceAccount:
    • 이름: app-sa

  Role:
    • 이름: app-role
    • 리소스: pods
    • 동사(verbs): get, list

  RoleBinding:
    • 이름: app-rb
    • Role: app-role
    • Subject: ServiceAccount app-sa

[ 검증 ]
  - kubectl auth can-i list pods \
      --as=system:serviceaccount:default:app-sa -n default
    → yes
EOF
echo ""

echo -e "${BOLD}${GREEN}Q6. 노드 drain [Architecture · 10점]${NC}"
hr
cat << 'EOF'
다음 순서로 노드 유지보수 작업을 수행하세요.

  (1) worker-1 노드를 drain합니다.
      • DaemonSet Pod는 무시
      • emptyDir 데이터는 삭제 허용

  (2) 유지보수 완료 후 worker-1을 다시 스케줄 가능 상태로 전환합니다.

[ 힌트 ]
  kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
  kubectl uncordon worker-1

[ 검증 ]
  - kubectl get nodes → worker-1이 Ready 상태 (SchedulingDisabled 아님)
EOF
echo ""

echo -e "${BOLD}${GREEN}Q7. Pod 트러블슈팅 [Troubleshooting · 25점]${NC}"
hr
cat << 'EOF'
현재 broken-app Pod가 ErrImagePull / ImagePullBackOff 상태입니다.

  작업:
    이미지를 nginx:latest 로 수정하여 Pod가 Running 상태가 되도록 하세요.

  힌트:
    - kubectl describe pod broken-app 으로 원인 파악
    - kubectl edit pod broken-app  또는
    - kubectl patch pod broken-app -p '...'
    - 변경 불가 필드는 Pod를 삭제 후 재생성

[ 검증 ]
  - kubectl get pod broken-app → STATUS가 Running
EOF
echo ""

echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}  채점: bash verify.sh${NC}"
echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
