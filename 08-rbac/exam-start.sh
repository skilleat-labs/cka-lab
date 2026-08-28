#!/usr/bin/env bash
# CKA 8강 실습 초기화 스크립트 — RBAC와 보안
# 사용법: bash exam-start.sh [--hints]
set -euo pipefail

HINTS=false
for arg in "$@"; do [[ "$arg" == "--hints" ]] && HINTS=true; done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

echo "================================================="
echo " CKA 8강 실습: RBAC와 보안"
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

# ClusterRoleBinding 정리 (ClusterRole보다 먼저)
kubectl delete clusterrolebinding node-reader-binding --ignore-not-found 2>/dev/null || true

# ClusterRole 정리
kubectl delete clusterrole node-reader --ignore-not-found 2>/dev/null || true

# RoleBinding 정리
kubectl delete rolebinding pod-reader-binding -n default --ignore-not-found 2>/dev/null || true

# Role 정리
kubectl delete role pod-reader -n default --ignore-not-found 2>/dev/null || true

# Pod 정리
kubectl delete pod sa-test -n default --ignore-not-found 2>/dev/null || true

# ServiceAccount 정리
kubectl delete serviceaccount my-sa -n default --ignore-not-found 2>/dev/null || true

echo "[SETUP] 정리 완료"
echo ""

echo "================================================="
echo " 실습 문제"
echo "================================================="
echo ""

echo "P1. ServiceAccount를 생성하고 Pod에 적용하라."
echo "    ① ServiceAccount 생성:"
echo "       - name: my-sa / namespace: default"
echo "    ② Pod 생성:"
echo "       - name: sa-test / namespace: default"
echo "       - image: busybox"
echo "       - command: [\"sleep\", \"3600\"]"
echo "       - spec.serviceAccountName: my-sa"
echo ""

echo "P2. Role과 RoleBinding을 생성하라."
echo "    ① Role 생성:"
echo "       - name: pod-reader / namespace: default"
echo "       - apiGroups: [\"\"] (core group)"
echo "       - resources: [\"pods\"]"
echo "       - verbs: [\"get\", \"list\", \"watch\"]"
echo "    ② RoleBinding 생성:"
echo "       - name: pod-reader-binding / namespace: default"
echo "       - subjects[0].kind: ServiceAccount"
echo "       - subjects[0].name: my-sa"
echo "       - subjects[0].namespace: default"
echo "       - roleRef.kind: Role"
echo "       - roleRef.name: pod-reader"
echo ""

echo "P3. ClusterRole과 ClusterRoleBinding을 생성하라."
echo "    ① ClusterRole 생성:"
echo "       - name: node-reader (namespace 없음)"
echo "       - apiGroups: [\"\"]"
echo "       - resources: [\"nodes\"]"
echo "       - verbs: [\"get\", \"list\", \"watch\"]"
echo "    ② ClusterRoleBinding 생성:"
echo "       - name: node-reader-binding"
echo "       - subjects[0].kind: ServiceAccount"
echo "       - subjects[0].name: my-sa"
echo "       - subjects[0].namespace: default"
echo "       - roleRef.kind: ClusterRole"
echo "       - roleRef.name: node-reader"
echo ""

echo "P4. 권한을 검증하라."
echo "    아래 명령이 'yes'를 출력하는지 확인:"
echo "    kubectl auth can-i get pods \\"
echo "      --as=system:serviceaccount:default:my-sa \\"
echo "      -n default"
echo ""
echo "    추가 확인 (선택):"
echo "    kubectl auth can-i get nodes \\"
echo "      --as=system:serviceaccount:default:my-sa"
echo ""

# ── 힌트 ──────────────────────────────────────────────
if $HINTS; then
  echo "================================================="
  echo " 힌트"
  echo "================================================="
  echo ""

  echo "[P1 힌트]"
  echo "  # SA 생성:"
  echo "  kubectl create serviceaccount my-sa -n default"
  echo "  # Pod YAML 핵심:"
  echo "  # spec:"
  echo "  #   serviceAccountName: my-sa   ← 이 필드!"
  echo "  #   containers:"
  echo "  #   - name: busybox"
  echo "  #     image: busybox"
  echo "  #     command: [\"sleep\", \"3600\"]"
  echo "  # 또는 임시 YAML:"
  echo "  # kubectl run sa-test --image=busybox --command -- sleep 3600"
  echo "  # (단, serviceAccountName은 YAML로 직접 설정해야 함)"
  echo ""

  echo "[P2 힌트]"
  echo "  # Role 생성 (kubectl 명령):"
  echo "  kubectl create role pod-reader \\"
  echo "    --verb=get,list,watch \\"
  echo "    --resource=pods \\"
  echo "    -n default"
  echo "  # RoleBinding 생성:"
  echo "  kubectl create rolebinding pod-reader-binding \\"
  echo "    --role=pod-reader \\"
  echo "    --serviceaccount=default:my-sa \\"
  echo "    -n default"
  echo "  # SA 형식 주의: <namespace>:<sa-name>"
  echo ""

  echo "[P3 힌트]"
  echo "  # ClusterRole 생성 (kubectl 명령):"
  echo "  kubectl create clusterrole node-reader \\"
  echo "    --verb=get,list,watch \\"
  echo "    --resource=nodes"
  echo "  # ClusterRoleBinding 생성:"
  echo "  kubectl create clusterrolebinding node-reader-binding \\"
  echo "    --clusterrole=node-reader \\"
  echo "    --serviceaccount=default:my-sa"
  echo "  # 주의: ClusterRole/ClusterRoleBinding에는 namespace 없음!"
  echo ""

  echo "[P4 힌트]"
  echo "  # 권한 검증:"
  echo "  kubectl auth can-i get pods \\"
  echo "    --as=system:serviceaccount:default:my-sa \\"
  echo "    -n default"
  echo "  # SA 형식: system:serviceaccount:<namespace>:<sa-name>"
  echo "  # 전체 권한 목록:"
  echo "  kubectl auth can-i --list \\"
  echo "    --as=system:serviceaccount:default:my-sa"
  echo ""
fi

echo "[INFO] 준비 완료. 작업 디렉토리: $WORK_DIR"
echo "[INFO] 완료 후 'bash verify.sh' 로 채점하세요."
