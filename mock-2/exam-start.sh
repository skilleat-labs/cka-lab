#!/usr/bin/env bash
# ============================================================
# CKA Mock Exam 2 — 스케줄링 & 네트워크
# 실행: bash exam-start.sh
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

hr() { printf '%0.s─' {1..70}; echo; }

echo -e "${BOLD}${BLUE}"
hr
echo "  CKA Mock Exam 2 — 스케줄링 & 네트워크"
echo "  문제 수: 7문항  |  총 배점: 100점  |  목표 시간: 45분"
hr
echo -e "${NC}"

# ─── 이전 리소스 정리 ────────────────────────────────────────
echo -e "${YELLOW}[준비] 이전 실습 리소스 정리 중...${NC}"

kubectl delete pod affinity-pod toleration-pod --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
kubectl delete networkpolicy deny-all allow-web --ignore-not-found=true 2>/dev/null || true
kubectl delete ingress shop-ingress --ignore-not-found=true 2>/dev/null || true
kubectl delete statefulset mysql-sts --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
kubectl delete service mysql-headless --ignore-not-found=true 2>/dev/null || true
kubectl delete pvc -l app=mysql-sts --ignore-not-found=true --force --grace-period=0 2>/dev/null || true

# Q4를 위한 서비스(존재하지 않아도 무방)
kubectl delete service shop-svc api-svc --ignore-not-found=true 2>/dev/null || true

echo -e "${GREEN}[준비] 정리 완료${NC}"
echo ""

# ─── 환경 세팅 ───────────────────────────────────────────────
echo -e "${YELLOW}[환경 세팅] Q4용 더미 서비스 생성 중...${NC}"

# Ingress 테스트를 위한 백엔드 서비스 (더미)
kubectl run shop-backend --image=nginx:latest --labels="app=shop" --restart=Never 2>/dev/null || true
kubectl expose pod shop-backend --name=shop-svc --port=80 2>/dev/null || true
kubectl run api-backend --image=nginx:latest --labels="app=api" --restart=Never 2>/dev/null || true
kubectl expose pod api-backend --name=api-svc --port=8080 --target-port=80 2>/dev/null || true

# Q7: worker-2 NotReady 시뮬레이션 (클러스터에 해당 노드가 있을 때만)
WORKER2=$(kubectl get node worker-2 --ignore-not-found=true -o name 2>/dev/null || echo '')
if [ -n "$WORKER2" ]; then
  echo -e "${YELLOW}  [환경] worker-2 노드 발견. Q7 시나리오 준비됨.${NC}"
fi

echo -e "${GREEN}[환경 세팅] 완료${NC}"
echo ""
echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}${CYAN}  시험 시작! 아래 7문제를 순서대로 풀어보세요.${NC}"
echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
echo ""

# ─── 문제 출력 ───────────────────────────────────────────────
echo -e "${BOLD}${GREEN}Q1. Node Affinity Pod [Workloads · 15점]${NC}"
hr
cat << 'EOF'
다음 조건의 Pod를 생성하세요.

  • 이름: affinity-pod
  • 이미지: nginx:latest
  • 네임스페이스: default
  • 스케줄링 조건: disktype=ssd 레이블을 가진 노드에
    requiredDuringSchedulingIgnoredDuringExecution 방식으로 배치

  힌트: kubectl explain pod.spec.affinity.nodeAffinity

[ 검증 ]
  - kubectl get pod affinity-pod -o wide
    → 해당 레이블의 노드에 스케줄됨 (노드가 없으면 Pending이 정상)
  - kubectl get pod affinity-pod -o yaml | grep -A20 affinity
EOF
echo ""

echo -e "${BOLD}${GREEN}Q2. Taint + Toleration [Workloads · 15점]${NC}"
hr
cat << 'EOF'
다음 조건의 Pod를 생성하세요.

  • 이름: toleration-pod
  • 이미지: busybox
  • 명령: sleep 3600
  • 네임스페이스: default
  • Toleration:
      key:    dedicated
      value:  gpu
      effect: NoSchedule
      operator: Equal

  힌트: kubectl explain pod.spec.tolerations

[ 검증 ]
  - kubectl get pod toleration-pod -o yaml | grep -A10 tolerations
EOF
echo ""

echo -e "${BOLD}${GREEN}Q3. NetworkPolicy [Networking · 20점]${NC}"
hr
cat << 'EOF'
default 네임스페이스에 다음 두 가지 NetworkPolicy를 생성하세요.

  (1) deny-all:
      • 모든 Pod에 대해 Ingress 트래픽 전체 차단
      • podSelector: {} (빈 selector = 전체 적용)
      • policyTypes: [Ingress]

  (2) allow-web:
      • app=db 레이블 Pod가 수신 측
      • app=web 레이블 Pod에서 포트 3306/TCP만 허용
      • policyTypes: [Ingress]

[ 검증 ]
  - kubectl get networkpolicy
  - kubectl describe networkpolicy deny-all
  - kubectl describe networkpolicy allow-web
EOF
echo ""

echo -e "${BOLD}${GREEN}Q4. Ingress 생성 [Networking · 15점]${NC}"
hr
cat << 'EOF'
다음 조건으로 Ingress를 생성하세요.

  • 이름: shop-ingress
  • 네임스페이스: default
  • 라우팅 규칙:
      /shop  → 서비스 shop-svc, 포트 80
      /api   → 서비스 api-svc, 포트 8080
  • pathType: Prefix

  힌트: kubectl create ingress --help

[ 검증 ]
  - kubectl get ingress shop-ingress
  - kubectl describe ingress shop-ingress
EOF
echo ""

echo -e "${BOLD}${GREEN}Q5. StatefulSet [Workloads · 15점]${NC}"
hr
cat << 'EOF'
다음 조건으로 StatefulSet을 생성하세요.

  • 이름: mysql-sts
  • 이미지: mysql:8.0
  • 복제본: 2
  • 네임스페이스: default
  • 환경변수: MYSQL_ROOT_PASSWORD=rootpass
  • volumeClaimTemplates:
      이름: data
      용량: 1Gi
      accessMode: ReadWriteOnce
      mountPath: /var/lib/mysql
  • headless Service (clusterIP: None):
      이름: mysql-headless, 포트: 3306

  힌트: StatefulSet은 --dry-run 또는 문서에서 YAML 복사 추천

[ 검증 ]
  - kubectl get statefulset mysql-sts
  - kubectl get pvc  → data-mysql-sts-0, data-mysql-sts-1
EOF
echo ""

echo -e "${BOLD}${GREEN}Q6. etcd 백업 [Architecture · 10점]${NC}"
hr
cat << 'EOF'
etcd 스냅샷을 /tmp/mock2-etcd.db 에 저장하세요.

  인증서 경로:
    CA cert:    /etc/kubernetes/pki/etcd/ca.crt
    Cert:       /etc/kubernetes/pki/etcd/server.crt
    Key:        /etc/kubernetes/pki/etcd/server.key
  etcd endpoint: https://127.0.0.1:2379

  힌트:
    ETCDCTL_API=3 etcdctl snapshot save /tmp/mock2-etcd.db \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=... --cert=... --key=...

[ 검증 ]
  - ls -lh /tmp/mock2-etcd.db
  - ETCDCTL_API=3 etcdctl snapshot status /tmp/mock2-etcd.db
EOF
echo ""

echo -e "${BOLD}${GREEN}Q7. Node NotReady 복구 [Troubleshooting · 10점]${NC}"
hr
cat << 'EOF'
worker-2 노드가 NotReady 상태입니다. 원인을 파악하고 복구하세요.

  진단 순서:
    (1) kubectl describe node worker-2  → Conditions 확인
    (2) ssh worker-2
    (3) systemctl status kubelet
    (4) journalctl -u kubelet -n 50     → 에러 메시지 확인
    (5) systemctl start kubelet
        systemctl enable kubelet
    (6) 컨트롤플레인으로 돌아와서 확인

[ 검증 ]
  - kubectl get nodes → worker-2가 Ready 상태

  ※ 단일 노드 환경에서는 이 문제를 스킵하거나
    minikube 환경에서는 kubectl get nodes로 현재 상태만 확인합니다.
EOF
echo ""

echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}  채점: bash verify.sh${NC}"
echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
