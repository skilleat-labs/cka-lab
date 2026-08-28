#!/usr/bin/env bash
# CKA 11강 실습 초기화
set -euo pipefail
HINTS=false
for arg in "$@"; do [[ "$arg" == "--hints" ]] && HINTS=true; done

echo "================================================="
echo " CKA 11강 실습: 트러블슈팅"
echo "================================================="

# 기존 리소스 정리
kubectl delete pod broken-pod fixed-pod pull-fail -n default --ignore-not-found 2>/dev/null || true
kubectl delete deployment target-app -n default --ignore-not-found 2>/dev/null || true
kubectl delete service target-svc -n default --ignore-not-found 2>/dev/null || true

echo "[INFO] 기존 리소스 정리 완료"

# P1용: 고장난 Pod 생성 (잘못된 command)
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: broken-pod
  namespace: default
spec:
  containers:
  - name: app
    image: nginx:1.24
    command: ["invalid-command"]
YAML

# P2용: 잘못된 이미지 Pod 생성
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pull-fail
  namespace: default
spec:
  containers:
  - name: app
    image: nginx:nonexistent-tag-xyz-9999
YAML

# P3용: Deployment + 잘못된 selector의 Service
kubectl create deployment target-app --image=nginx:1.24 --replicas=2 -n default 2>/dev/null || true
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: target-svc
  namespace: default
spec:
  selector:
    app: WRONG-LABEL
  ports:
  - port: 80
    targetPort: 80
YAML

echo ""
echo "================================================="
echo " 실습 문제"
echo "================================================="
echo ""
echo "P1. broken-pod가 CrashLoopBackOff 상태입니다."
echo "    원인을 파악하고 올바른 Pod(fixed-pod)를 생성하여 Running 상태로 만드세요."
echo "    - fixed-pod: image=nginx:1.24, 정상 동작"
echo ""
echo "P2. pull-fail Pod가 ImagePullBackOff 상태입니다."
echo "    Pod를 올바른 이미지(nginx:1.24)로 수정하여 Running 상태로 만드세요."
echo ""
echo "P3. target-svc Service의 Endpoints가 비어있습니다."
echo "    원인을 파악하고 Service selector를 수정하여 Endpoints에 Pod IP가 등록되게 하세요."
echo ""
echo "P4. 현재 클러스터 노드 상태를 확인하라."
echo "    NotReady 노드가 있다면 원인 파악 명령어를 실행하세요."
echo "    - 목표: Ready 노드 최소 2개 이상 확인"
echo ""

if $HINTS; then
  echo "================================================="
  echo " 힌트"
  echo "================================================="
  echo ""
  echo "[P1 힌트]"
  echo "  kubectl describe pod broken-pod   # Events 확인"
  echo "  kubectl logs broken-pod           # 로그 확인"
  echo "  kubectl logs broken-pod --previous  # 이전 컨테이너 로그"
  echo "  # fixed-pod 생성:"
  echo "  kubectl run fixed-pod --image=nginx:1.24 --restart=Never"
  echo ""
  echo "[P2 힌트]"
  echo "  kubectl describe pod pull-fail   # Events에서 이미지 오류 확인"
  echo "  # 방법 1: 삭제 후 재생성"
  echo "  kubectl delete pod pull-fail"
  echo "  kubectl run pull-fail --image=nginx:1.24 --restart=Never"
  echo "  # 방법 2: kubectl patch"
  echo "  kubectl patch pod pull-fail -p '{\"spec\":{\"containers\":[{\"name\":\"app\",\"image\":\"nginx:1.24\"}]}}'"
  echo ""
  echo "[P3 힌트]"
  echo "  kubectl get endpoints target-svc   # Endpoints 확인"
  echo "  kubectl get svc target-svc -o yaml  # selector 확인"
  echo "  kubectl get pods -l app=target-app  # target-app 레이블 확인"
  echo "  # Service selector 수정:"
  echo "  kubectl patch svc target-svc -p '{\"spec\":{\"selector\":{\"app\":\"target-app\"}}}'"
  echo ""
  echo "[P4 힌트]"
  echo "  kubectl get nodes -o wide"
  echo "  kubectl describe node <node-name>   # Conditions 확인"
  echo "  # SSH 접속 후:"
  echo "  systemctl status kubelet"
  echo "  journalctl -u kubelet -n 50"
  echo ""
fi

echo "[INFO] 준비 완료. 'bash verify.sh' 로 채점하세요."
