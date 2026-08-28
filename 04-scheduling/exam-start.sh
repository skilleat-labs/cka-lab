#!/usr/bin/env bash
# CKA 4강 실습 초기화 스크립트
# 사용법: bash exam-start.sh [--hints]
set -euo pipefail

HINTS=false
for arg in "$@"; do [[ "$arg" == "--hints" ]] && HINTS=true; done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

echo "================================================="
echo " CKA 4강 실습: 스케줄링 — 어디에, 얼마나"
echo "================================================="
echo ""

# ── 현재 클러스터 상태 확인 ──────────────────────────
echo "[INFO] 현재 노드 상태:"
kubectl get nodes -o wide 2>/dev/null || {
  echo "[ERROR] kubectl을 실행할 수 없습니다. kubeconfig를 확인하세요."
  exit 1
}
echo ""

# ── 기존 리소스 정리 ──────────────────────────────────
echo "[SETUP] 이전 실습 리소스 정리 중..."

kubectl delete pod resource-pod  -n default --ignore-not-found 2>/dev/null || true
kubectl delete pod ssd-pod       -n default --ignore-not-found 2>/dev/null || true
kubectl delete pod gpu-pod       -n default --ignore-not-found 2>/dev/null || true
kubectl delete deployment nginx-hpa -n default --ignore-not-found 2>/dev/null || true
kubectl delete hpa nginx-hpa     -n default --ignore-not-found 2>/dev/null || true

# worker-1 nodeSelector 레이블 제거 (혹시 남아있을 경우)
kubectl label node worker-1 disktype- 2>/dev/null || true

# worker-2 taint 제거 (혹시 남아있을 경우)
kubectl taint node worker-2 dedicated=gpu:NoSchedule- 2>/dev/null || true

echo "[SETUP] 정리 완료"
echo ""

# ── 실습 환경 세팅 ────────────────────────────────────
echo "[SETUP] 실습 환경 구성 중..."

# worker-1 에 disktype=ssd 레이블 부여 (P2용)
kubectl label node worker-1 disktype=ssd --overwrite 2>/dev/null || true

# worker-2 에 dedicated=gpu:NoSchedule Taint 적용 (P3용)
kubectl taint node worker-2 dedicated=gpu:NoSchedule --overwrite 2>/dev/null || true

echo "[SETUP] 준비 완료"
echo "  - worker-1: disktype=ssd 레이블 설정됨"
echo "  - worker-2: dedicated=gpu:NoSchedule Taint 설정됨"
echo ""

echo "================================================="
echo " 실습 문제"
echo "================================================="
echo ""
echo "P1. Resource Requests/Limits가 설정된 파드를 생성하라."
echo "    - name: resource-pod / namespace: default"
echo "    - image: nginx:1.24"
echo "    - requests: cpu=100m, memory=128Mi"
echo "    - limits:   cpu=200m, memory=256Mi"
echo ""
echo "P2. Node Affinity를 사용하여 worker-1(disktype=ssd)에 파드를 배치하라."
echo "    - name: ssd-pod / namespace: default"
echo "    - image: nginx:1.24"
echo "    - requiredDuringSchedulingIgnoredDuringExecution"
echo "    - matchExpressions: disktype In [ssd]"
echo ""
echo "P3. worker-2의 Taint(dedicated=gpu:NoSchedule)를 허용하는 파드를 생성하라."
echo "    - name: gpu-pod / namespace: default"
echo "    - image: nginx:1.24"
echo "    - toleration: key=dedicated, operator=Equal, value=gpu, effect=NoSchedule"
echo ""
echo "P4. HPA(HorizontalPodAutoscaler)를 생성하라."
echo "    - Deployment name: nginx-hpa / image: nginx:1.24 / replicas: 2"
echo "    - HPA name: nginx-hpa / namespace: default"
echo "    - minReplicas: 2 / maxReplicas: 10"
echo "    - CPU 사용률 50% 기준 자동 스케일"
echo ""

if $HINTS; then
  echo "================================================="
  echo " 힌트"
  echo "================================================="
  echo ""
  echo "[P1 힌트]"
  echo "  # YAML 방식 (resources 필드는 kubectl run으로 설정 불가):"
  echo "  cat <<EOF | kubectl apply -f -"
  echo "  apiVersion: v1"
  echo "  kind: Pod"
  echo "  metadata:"
  echo "    name: resource-pod"
  echo "  spec:"
  echo "    containers:"
  echo "    - name: nginx"
  echo "      image: nginx:1.24"
  echo "      resources:"
  echo "        requests:"
  echo "          cpu: \"100m\""
  echo "          memory: \"128Mi\""
  echo "        limits:"
  echo "          cpu: \"200m\""
  echo "          memory: \"256Mi\""
  echo "  EOF"
  echo ""
  echo "[P2 힌트]"
  echo "  # worker-1 레이블 확인:"
  echo "  kubectl get node worker-1 --show-labels"
  echo "  # Node Affinity YAML 핵심:"
  echo "  # spec:"
  echo "  #   affinity:"
  echo "  #     nodeAffinity:"
  echo "  #       requiredDuringSchedulingIgnoredDuringExecution:"
  echo "  #         nodeSelectorTerms:"
  echo "  #         - matchExpressions:"
  echo "  #           - key: disktype"
  echo "  #             operator: In"
  echo "  #             values: [ssd]"
  echo ""
  echo "[P3 힌트]"
  echo "  # worker-2 Taint 확인:"
  echo "  kubectl describe node worker-2 | grep -A3 Taints"
  echo "  # Toleration YAML 핵심:"
  echo "  # spec:"
  echo "  #   tolerations:"
  echo "  #   - key: \"dedicated\""
  echo "  #     operator: \"Equal\""
  echo "  #     value: \"gpu\""
  echo "  #     effect: \"NoSchedule\""
  echo ""
  echo "[P4 힌트]"
  echo "  # Deployment 먼저 생성:"
  echo "  kubectl create deployment nginx-hpa --image=nginx:1.24 --replicas=2"
  echo "  # HPA 생성 (kubectl autoscale 명령어):"
  echo "  kubectl autoscale deployment nginx-hpa --min=2 --max=10 --cpu-percent=50"
  echo "  # 확인:"
  echo "  kubectl get hpa"
  echo ""
fi

echo "[INFO] 준비 완료. 'bash verify.sh' 로 채점하세요."
