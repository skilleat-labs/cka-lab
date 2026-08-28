#!/usr/bin/env bash
# CKA 3강 실습 초기화 스크립트
# 사용법: bash exam-start.sh [--hints]
set -euo pipefail

HINTS=false
for arg in "$@"; do [[ "$arg" == "--hints" ]] && HINTS=true; done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

echo "================================================="
echo " CKA 3강 실습: 워크로드 배포와 관리"
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

kubectl delete deployment web-app -n default --ignore-not-found 2>/dev/null || true
kubectl delete pod db-client -n default --ignore-not-found 2>/dev/null || true
kubectl delete configmap db-config -n default --ignore-not-found 2>/dev/null || true
kubectl delete cronjob date-printer -n default --ignore-not-found 2>/dev/null || true
kubectl delete jobs -n default -l job-name 2>/dev/null || true
# date-printer로 생성된 Job 정리
kubectl get jobs -n default -o name 2>/dev/null | grep "date-printer" | xargs kubectl delete -n default 2>/dev/null || true

# monitoring namespace 및 DaemonSet 정리
if kubectl get namespace monitoring &>/dev/null; then
  kubectl delete daemonset node-exporter -n monitoring --ignore-not-found 2>/dev/null || true
  kubectl delete namespace monitoring --ignore-not-found 2>/dev/null || true
fi

echo "[SETUP] 정리 완료"
echo ""

echo "================================================="
echo " 실습 문제"
echo "================================================="
echo ""
echo "P1. Deployment를 생성하고 Scale, Rolling Update, Rollback을 수행하라."
echo "    - name: web-app / image: nginx:1.24 / replicas: 3"
echo "    - 레플리카를 5로 스케일"
echo "    - 이미지를 nginx:1.25로 롤링 업데이트"
echo "    - 이전 버전(nginx:1.24)으로 롤백"
echo ""
echo "P2. ConfigMap을 생성하고 파드에 환경변수로 주입하라."
echo "    - ConfigMap name: db-config / namespace: default"
echo "    - 데이터: DB_HOST=mysql, DB_PORT=3306"
echo "    - 파드 name: db-client / image: busybox"
echo "    - envFrom으로 ConfigMap 전체 주입"
echo "    - command: [\"sh\",\"-c\",\"env | grep DB && sleep 3600\"]"
echo ""
echo "P3. 매 분마다 date를 출력하는 CronJob을 생성하라."
echo "    - name: date-printer / namespace: default"
echo "    - schedule: '*/1 * * * *'"
echo "    - image: busybox / command: [\"date\"]"
echo ""
echo "P4. monitoring 네임스페이스에 DaemonSet을 생성하라."
echo "    - name: node-exporter / namespace: monitoring"
echo "    - image: prom/node-exporter:latest"
echo "    - hostNetwork: true, hostPID: true"
echo "    - selector/labels: app=node-exporter"
echo ""

if $HINTS; then
  echo "================================================="
  echo " 힌트"
  echo "================================================="
  echo ""
  echo "[P1 힌트]"
  echo "  # 생성"
  echo "  kubectl create deployment web-app --image=nginx:1.24 --replicas=3"
  echo "  # 스케일"
  echo "  kubectl scale deployment web-app --replicas=5"
  echo "  # 이미지 업데이트 (컨테이너명 확인: kubectl describe deploy web-app)"
  echo "  kubectl set image deployment/web-app nginx=nginx:1.25"
  echo "  kubectl rollout status deployment/web-app"
  echo "  # 롤백"
  echo "  kubectl rollout undo deployment/web-app"
  echo ""
  echo "[P2 힌트]"
  echo "  kubectl create configmap db-config \\"
  echo "    --from-literal=DB_HOST=mysql --from-literal=DB_PORT=3306"
  echo "  # 파드 YAML의 spec.containers 아래에:"
  echo "  # envFrom:"
  echo "  # - configMapRef:"
  echo "  #     name: db-config"
  echo ""
  echo "[P3 힌트]"
  echo "  kubectl create cronjob date-printer \\"
  echo "    --image=busybox --schedule='*/1 * * * *' -- date"
  echo "  # 1~2분 후 확인:"
  echo "  kubectl get job | grep date-printer"
  echo ""
  echo "[P4 힌트]"
  echo "  kubectl create namespace monitoring"
  echo "  # DaemonSet YAML 핵심 구조:"
  echo "  # kind: DaemonSet"
  echo "  # spec:"
  echo "  #   selector:"
  echo "  #     matchLabels:"
  echo "  #       app: node-exporter"
  echo "  #   template:"
  echo "  #     metadata:"
  echo "  #       labels:"
  echo "  #         app: node-exporter  ← selector와 반드시 일치"
  echo "  #     spec:"
  echo "  #       hostNetwork: true"
  echo "  #       hostPID: true"
  echo "  #       containers:"
  echo "  #       - name: node-exporter"
  echo "  #         image: prom/node-exporter:latest"
  echo ""
fi

echo "[INFO] 준비 완료. 'bash verify.sh' 로 채점하세요."
