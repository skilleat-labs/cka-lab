#!/usr/bin/env bash
# ============================================================
# CKA Mock Exam 3 — 종합 심화
# 실행: bash exam-start.sh
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

hr() { printf '%0.s─' {1..70}; echo; }

echo -e "${BOLD}${BLUE}"
hr
echo "  CKA Mock Exam 3 — 종합 심화"
echo "  문제 수: 7문항  |  총 배점: 100점  |  목표 시간: 50분"
hr
echo -e "${NC}"

# ─── 이전 리소스 정리 ────────────────────────────────────────
echo -e "${YELLOW}[준비] 이전 실습 리소스 정리 중...${NC}"

kubectl delete deployment web-app broken-deploy --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
kubectl delete hpa web-app --ignore-not-found=true 2>/dev/null || true
kubectl delete storageclass fast-ssd --ignore-not-found=true 2>/dev/null || true
kubectl delete pvc fast-pvc --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
kubectl delete clusterrolebinding cluster-reader-crb --ignore-not-found=true 2>/dev/null || true
kubectl delete clusterrole cluster-reader --ignore-not-found=true 2>/dev/null || true
kubectl delete serviceaccount reader-sa --ignore-not-found=true 2>/dev/null || true
kubectl delete daemonset log-collector --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
kubectl delete service broken-svc --ignore-not-found=true 2>/dev/null || true
kubectl delete pod crash-pod --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
rm -f /tmp/upgrade-plan.txt

echo -e "${GREEN}[준비] 정리 완료${NC}"
echo ""

# ─── 환경 세팅 ───────────────────────────────────────────────
echo -e "${YELLOW}[환경 세팅] Q5 트러블슈팅 환경 생성 중...${NC}"

# Q5: broken-deploy + broken-svc (selector 불일치)
# Deployment 레이블은 app=broken-deploy 이지만,
# Service selector는 app=broken-wrong 으로 고의로 불일치 설정
kubectl create deployment broken-deploy --image=nginx:latest --replicas=2 2>/dev/null || true

# 잠시 대기 후 서비스 생성 (YAML로 직접 생성해서 selector를 의도적으로 잘못 설정)
kubectl apply -f - <<'YAML' 2>/dev/null || true
apiVersion: v1
kind: Service
metadata:
  name: broken-svc
  namespace: default
spec:
  selector:
    app: broken-wrong
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
YAML

echo -e "${YELLOW}[환경 세팅] Q6 CrashLoopBackOff Pod 생성 중...${NC}"
# Q6: 잘못된 command로 CrashLoopBackOff 유발
kubectl apply -f - <<'YAML' 2>/dev/null || true
apiVersion: v1
kind: Pod
metadata:
  name: crash-pod
  namespace: default
spec:
  containers:
  - name: crash-pod
    image: busybox
    command: ["wrongcmd"]
YAML

echo -e "${GREEN}[환경 세팅] 완료${NC}"
echo ""
echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}${CYAN}  시험 시작! 아래 7문제를 순서대로 풀어보세요.${NC}"
echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
echo ""

# ─── 문제 출력 ───────────────────────────────────────────────
echo -e "${BOLD}${GREEN}Q1. HPA 설정 [Workloads · 10점]${NC}"
hr
cat << 'EOF'
다음 조건으로 Deployment와 HPA를 생성하세요.

  Deployment:
    • 이름: web-app
    • 이미지: nginx:1.24
    • 복제본: 2
    • 네임스페이스: default

  HPA (Horizontal Pod Autoscaler):
    • 대상: deployment/web-app
    • 최소 복제본: 2
    • 최대 복제본: 5
    • CPU 사용률 임계값: 70%

  힌트:
    kubectl autoscale deployment web-app --min=2 --max=5 --cpu-percent=70

[ 검증 ]
  - kubectl get deployment web-app
  - kubectl get hpa web-app
EOF
echo ""

echo -e "${BOLD}${GREEN}Q2. StorageClass + PVC [Storage · 15점]${NC}"
hr
cat << 'EOF'
다음 조건으로 StorageClass와 PVC를 생성하세요.

  StorageClass:
    • 이름: fast-ssd
    • provisioner: docker.io/hostpath
    • reclaimPolicy: Delete

  PVC:
    • 이름: fast-pvc
    • 용량: 1Gi
    • accessMode: ReadWriteOnce
    • storageClassName: fast-ssd
    • 네임스페이스: default

[ 검증 ]
  - kubectl get storageclass fast-ssd
  - kubectl get pvc fast-pvc
    (환경에 따라 Pending이 정상일 수 있음)
EOF
echo ""

echo -e "${BOLD}${GREEN}Q3. RBAC ClusterRole [Architecture · 20점]${NC}"
hr
cat << 'EOF'
다음 세 가지 RBAC 리소스를 생성하세요.

  ServiceAccount:
    • 이름: reader-sa
    • 네임스페이스: default

  ClusterRole:
    • 이름: cluster-reader
    • 리소스: pods, nodes, services
    • 동사(verbs): get, list, watch

  ClusterRoleBinding:
    • 이름: cluster-reader-crb
    • ClusterRole: cluster-reader
    • Subject: ServiceAccount default:reader-sa

[ 검증 ]
  - kubectl auth can-i list nodes \
      --as=system:serviceaccount:default:reader-sa
    → yes
  - kubectl auth can-i list pods \
      --as=system:serviceaccount:default:reader-sa
    → yes
EOF
echo ""

echo -e "${BOLD}${GREEN}Q4. DaemonSet 생성 [Workloads · 15점]${NC}"
hr
cat << 'EOF'
다음 조건으로 DaemonSet을 생성하세요.

  • 이름: log-collector
  • 네임스페이스: default
  • 이미지: busybox
  • command: ["sh", "-c", "while true; do echo $(date); sleep 60; done"]
  • 레이블(selector/template): app=log-collector

  힌트: DaemonSet은 kubectl create 명령 없음 → YAML 작성 필요
        kubectl explain daemonset.spec

[ 검증 ]
  - kubectl get daemonset log-collector
    → DESIRED와 CURRENT가 노드 수와 일치
  - kubectl get pods -l app=log-collector
EOF
echo ""

echo -e "${BOLD}${GREEN}Q5. Service Endpoint 수정 [Troubleshooting · 20점]${NC}"
hr
cat << 'EOF'
현재 broken-svc의 Endpoints가 비어 있습니다. (broken-deploy는 정상 실행 중)

  원인: Service selector가 Deployment Pod의 레이블과 불일치

  작업:
    (1) 문제 진단:
        kubectl get endpoints broken-svc     → <none> 확인
        kubectl get svc broken-svc -o yaml   → selector 확인
        kubectl get pod -l app=broken-deploy → Pod 레이블 확인

    (2) Service selector를 app=broken-deploy 로 수정:
        kubectl patch svc broken-svc \
          -p '{"spec":{"selector":{"app":"broken-deploy"}}}'

[ 검증 ]
  - kubectl get endpoints broken-svc → Pod IP 2개 이상 표시
EOF
echo ""

echo -e "${BOLD}${GREEN}Q6. CrashLoopBackOff 수정 [Troubleshooting · 10점]${NC}"
hr
cat << 'EOF'
crash-pod가 CrashLoopBackOff 상태입니다. 원인을 파악하고 수정하세요.

  진단:
    kubectl logs crash-pod --previous      → 에러 확인
    kubectl describe pod crash-pod         → command 확인

  원인: command가 wrongcmd (존재하지 않는 명령어)

  작업: crash-pod를 삭제하고 올바른 command(sleep 3600)로 재생성

  힌트:
    kubectl delete pod crash-pod --force --grace-period=0
    kubectl run crash-pod --image=busybox --command -- sleep 3600

[ 검증 ]
  - kubectl get pod crash-pod → STATUS가 Running
EOF
echo ""

echo -e "${BOLD}${GREEN}Q7. 클러스터 업그레이드 계획 [Architecture · 10점]${NC}"
hr
cat << 'EOF'
kubeadm을 사용하여 클러스터 업그레이드 계획을 확인하고 결과를 파일에 저장하세요.

  작업:
    kubeadm upgrade plan > /tmp/upgrade-plan.txt 2>&1

  힌트:
    - 컨트롤플레인 노드에서 실행해야 합니다.
    - 현재 클러스터 버전과 업그레이드 가능한 버전이 출력됩니다.

[ 검증 ]
  - cat /tmp/upgrade-plan.txt
  - 파일에 쿠버네티스 버전 정보가 포함되어야 합니다.
EOF
echo ""

echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}  채점: bash verify.sh${NC}"
echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────────────────${NC}"
