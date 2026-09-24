#!/usr/bin/env bash
# CKA 5강 실습 초기화 스크립트
# 사용법: bash exam-start.sh [--hints]
set -euo pipefail

HINTS=false
for arg in "$@"; do
  [[ "$arg" == "--hints" ]] && HINTS=true
done

echo "=========================================="
echo "  CKA 5강 실습: 스토리지 — 데이터를 영속하라"
echo "=========================================="
echo ""
echo "[CLEANUP] 이전 실습 리소스 정리 중..."

# 이전 리소스 정리
kubectl delete pvc data-pvc sc-pvc -n default --ignore-not-found 2>/dev/null || true
kubectl delete pvc -l app=web-sts -n default --ignore-not-found 2>/dev/null || true
kubectl delete pvc www-storage-web-sts-0 www-storage-web-sts-1 www-storage-web-sts-2 -n default --ignore-not-found 2>/dev/null || true
kubectl delete pv data-pv --ignore-not-found 2>/dev/null || true
kubectl delete storageclass local-storage --ignore-not-found 2>/dev/null || true
kubectl delete statefulset web-sts -n default --ignore-not-found 2>/dev/null || true
kubectl delete pod shared-vol -n default --ignore-not-found 2>/dev/null || true

# hostPath 디렉터리 생성
sudo mkdir -p /tmp/k8s-data && sudo chmod 777 /tmp/k8s-data 2>/dev/null || mkdir -p /tmp/k8s-data

echo "[OK] 환경 초기화 완료"
echo ""

# ──────────────────────────────────────────────────────
echo "▶ 문제 목록 (P1 ~ P4)"
echo "------------------------------------------"
echo ""
echo "P1. PersistentVolume + PVC 생성 & 바인딩"
echo "    - PV 이름  : data-pv"
echo "    - 타입     : hostPath, path=/tmp/k8s-data"
echo "    - 용량     : 1Gi"
echo "    - accessMode: ReadWriteOnce"
echo "    - reclaimPolicy: Retain"
echo "    - PVC 이름 : data-pvc (namespace: default)"
echo "    - 용량     : 1Gi, ReadWriteOnce"
echo "    - 목표     : kubectl get pvc data-pvc → STATUS: Bound"
echo ""
echo "P2. StorageClass + PVC 생성"
echo "    - SC 이름  : local-storage"
echo "    - provisioner: kubernetes.io/no-provisioner"
echo "    - volumeBindingMode: WaitForFirstConsumer"
echo "    - PVC 이름 : sc-pvc (namespace: default)"
echo "    - storageClassName: local-storage"
echo "    - 용량     : 500Mi, ReadWriteOnce"
echo ""
echo "P3. StatefulSet + volumeClaimTemplates"
echo "    - 이름     : web-sts (namespace: default)"
echo "    - replicas : 3"
echo "    - 이미지   : nginx:1.24"
echo "    - volumeClaimTemplate 이름: www-storage"
echo "    - 용량     : 1Gi, ReadWriteOnce"
echo "    - mountPath: /usr/share/nginx/html"
echo "    - 목표     : 3개 PVC 자동 생성 (www-storage-web-sts-0/1/2)"
echo ""
echo "P4. emptyDir 공유 볼륨 Pod"
echo "    - Pod 이름 : shared-vol (namespace: default)"
echo "    - 컨테이너1: writer (busybox)"
echo "      command: sh -c 'while true; do date >> /shared/log.txt; sleep 5; done'"
echo "    - 컨테이너2: reader (busybox)"
echo "      command: sh -c 'tail -f /shared/log.txt'"
echo "    - emptyDir volume 이름: shared, mountPath: /shared"
echo "    - 목표     : Pod Running, 두 컨테이너 정상 동작"
echo ""
echo "------------------------------------------"

# ──────────────────────────────────────────────────────
if [ "$HINTS" = true ]; then
  echo ""
  echo "==============================="
  echo "  💡 HINTS (--hints 모드)"
  echo "==============================="
  echo ""

  echo "── P1 힌트: PV YAML ──"
  cat <<'HINT_P1_PV'
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /tmp/k8s-data
    type: DirectoryOrCreate
HINT_P1_PV

  echo ""
  echo "── P1 힌트: PVC YAML ──"
  cat <<'HINT_P1_PVC'
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
HINT_P1_PVC

  echo ""
  echo "── P2 힌트: StorageClass YAML ──"
  cat <<'HINT_P2_SC'
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
HINT_P2_SC

  echo ""
  echo "── P2 힌트: PVC YAML ──"
  cat <<'HINT_P2_PVC'
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sc-pvc
  namespace: default
spec:
  storageClassName: local-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
HINT_P2_PVC

  echo ""
  echo "── P3 힌트: StatefulSet YAML ──"
  cat <<'HINT_P3_STS'
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web-sts
  namespace: default
spec:
  serviceName: web
  replicas: 3
  selector:
    matchLabels:
      app: web-sts
  template:
    metadata:
      labels:
        app: web-sts
    spec:
      containers:
      - name: nginx
        image: nginx:1.24
        volumeMounts:
        - name: www-storage
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: www-storage
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 1Gi
HINT_P3_STS

  echo ""
  echo "── P4 힌트: emptyDir Pod YAML ──"
  cat <<'HINT_P4_POD'
---
apiVersion: v1
kind: Pod
metadata:
  name: shared-vol
  namespace: default
spec:
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c"]
    args: ["while true; do date >> /shared/log.txt; sleep 5; done"]
    volumeMounts:
    - name: shared
      mountPath: /shared
  - name: reader
    image: busybox
    command: ["sh", "-c", "tail -f /shared/log.txt"]
    volumeMounts:
    - name: shared
      mountPath: /shared
  volumes:
  - name: shared
    emptyDir: {}
HINT_P4_POD

fi

echo ""
echo "[INFO] 준비 완료. 문제를 풀고 'bash verify.sh' 로 채점하세요."
