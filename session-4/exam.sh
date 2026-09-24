#!/usr/bin/env bash
# CKA 4세션 시험 — 순차 진행형
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 4세션 시험 — PVC/Deployment YAML · Requests/Limits · Probe"
EXAM_NQ=3

exam_cleanup() {
  if kubectl get namespace api &>/dev/null; then
    echo "  네임스페이스 api 삭제 중... (수십 초 걸릴 수 있음)"
    kubectl delete namespace api --wait=true &>/dev/null || true
  fi
  for i in 1 2 3; do kubectl delete pv "api-pv-${i}" --ignore-not-found &>/dev/null || true; done
  kdel storageclass api-storage
  echo "  api 네임스페이스 · api-storage · api-pv-1~3 삭제"
}

exam_setup() {
  kubectl create namespace api &>/dev/null || true
  echo "  api 네임스페이스 생성"
  kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: api-storage }
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
reclaimPolicy: Retain
EOF
  for i in 1 2 3; do
    kubectl apply -f - &>/dev/null <<EOF
apiVersion: v1
kind: PersistentVolume
metadata: { name: api-pv-${i}, labels: { usage: api-exam } }
spec:
  capacity: { storage: 2Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: api-storage
  hostPath: { path: /mnt/api-data-${i}, type: DirectoryOrCreate }
EOF
  done
  echo "  StorageClass api-storage + PV 3개(2Gi) 생성"
  kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: api-worker, namespace: api, labels: { app: api-worker } }
spec:
  replicas: 2
  selector: { matchLabels: { app: api-worker } }
  template:
    metadata: { labels: { app: api-worker } }
    spec:
      containers:
      - name: worker
        image: nginx:1.24
        ports: [ { containerPort: 80 } ]
EOF
  echo "  Q2 용 api-worker Deployment 생성 (리소스 제한 없음)"
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Create a Deployment with the PVC mounted from the start"; }
q1_text() { cat <<'EOF'
A StorageClass named api-storage already exists in the cluster.

In the api namespace, create a PersistentVolumeClaim named api-data that
requests 1Gi with access mode ReadWriteOnce using that StorageClass.

Then create a Deployment named api-server (image nginx:1.24, 1 replica)
whose manifest already includes the PVC as a volume, mounted at
/var/www/data.

The Deployment must be created with the volume from the start — do not
add it afterwards.

Conditions:
  PVC             api-data / storageClassName api-storage / 1Gi / ReadWriteOnce
  Deployment      api-server / nginx:1.24 / replicas 1
  The Deployment manifest must contain volumes + volumeMounts at creation.
  mountPath       /var/www/data
  Careful: creating it first and adding the volume later does not count
  (the Deployment must still be at revision 1).

Verify:
  kubectl get pvc api-data -n api
  kubectl rollout history deployment/api-server -n api
  kubectl exec -n api deploy/api-server -- df -h /var/www/data
EOF
}
q1_title_ko() { echo "PVC 를 만들고 Deployment YAML 에서 바로 연결"; }
q1_text_ko() { cat <<'EOF'
A StorageClass named api-storage already exists in the cluster.

In the api namespace, create a PersistentVolumeClaim named api-data that
requests 1Gi with access mode ReadWriteOnce using that StorageClass.

Then create a Deployment named api-server (image nginx:1.24, 1 replica)
whose manifest already includes the PVC as a volume, mounted at
/var/www/data.

The Deployment must be created with the volume from the start — do not
add it afterwards.

[조건]
  PVC             api-data / storageClassName api-storage / 1Gi / ReadWriteOnce
  Deployment      api-server / nginx:1.24 / replicas 1
  Deployment YAML 안에 volumes + volumeMounts 를 처음부터 포함해 생성
  mountPath       /var/www/data
  주의: 먼저 만들고 나중에 볼륨을 추가하면 오답 (revision 이 1 이어야 함)

[확인]
  kubectl get pvc api-data -n api
  kubectl rollout history deployment/api-server -n api
  kubectl exec -n api deploy/api-server -- df -h /var/www/data
EOF
}
q1_hint() { cat <<'EOF'
kubectl create deployment api-server --image=nginx:1.24 --replicas=1 -n api \
  --dry-run=client -o yaml > api-server.yaml
# spec.template.spec 에 volumes / containers[0] 에 volumeMounts 추가 후
kubectl apply -f api-server.yaml
EOF
}
q1_grade() {
  check "api-data PVC 가 api 네임스페이스에 존재한다" "kubectl get pvc api-data -n api"
  check_output "api-data 가 api-storage StorageClass 를 사용한다" \
    "kubectl get pvc api-data -n api -o jsonpath='{.spec.storageClassName}'" "^api-storage$"
  check_output "api-data accessModes 가 ReadWriteOnce 이다" \
    "kubectl get pvc api-data -n api -o jsonpath='{.spec.accessModes[0]}'" "^ReadWriteOnce$"
  check_output "api-data 요청 용량이 1Gi 이다" \
    "kubectl get pvc api-data -n api -o jsonpath='{.spec.resources.requests.storage}'" "^1Gi$"
  check_output "api-data 가 Bound 상태이다" \
    "kubectl get pvc api-data -n api -o jsonpath='{.status.phase}'" "^Bound$"
  check "api-server Deployment 가 api 네임스페이스에 존재한다" "kubectl get deployment api-server -n api"
  check_output "api-server 이미지가 nginx:1.24 이다" \
    "kubectl get deployment api-server -n api -o jsonpath='{.spec.template.spec.containers[0].image}'" "^nginx:1\.24$"
  wait_ready "-l app=api-server" api || true
  check_output "api-server 파드가 Ready 이다" \
    "kubectl get deployment api-server -n api -o jsonpath='{.status.readyReplicas}'" "^1$"
  check_output "api-server 가 api-data PVC 를 볼륨으로 참조한다" \
    "kubectl get deployment api-server -n api -o jsonpath='{.spec.template.spec.volumes[*].persistentVolumeClaim.claimName}'" "api-data"
  check_output "api-server 컨테이너가 /var/www/data 에 마운트하고 있다" \
    "kubectl get deployment api-server -n api -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}'" "/var/www/data"
  local rev; rev=$(kubectl get deployment api-server -n api -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null || echo "")
  check_result "Deployment 를 볼륨 포함 상태로 한 번에 생성했다 (revision 1)" "$([[ "$rev" == "1" ]] && echo 0 || echo 1)" "revision ${rev:-없음} — 생성 후 수정한 흔적"
  local pod out=""; pod=$(kubectl get pods -n api -l app=api-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  [[ -n "$pod" ]] && out=$(kubectl exec "$pod" -n api -- sh -c 'echo mounted > /var/www/data/.probe && cat /var/www/data/.probe' 2>/dev/null || echo "")
  check_result "파드 내부 /var/www/data 에 실제로 쓰고 읽을 수 있다 (실제 마운트 검증)" "$([[ "$out" == "mounted" ]] && echo 0 || echo 1)"
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Add resource requests and limits to an existing Deployment"; }
q2_text() { cat <<'EOF'
A Deployment named api-worker already exists in the api namespace with 2
replicas and no resource requests or limits.

Update it so that its container (worker) has:
  requests    cpu 100m, memory 128Mi
  limits      cpu 200m, memory 256Mi

All pods must be rolled out and Ready with the new resource settings.

Conditions:
  target          api-worker Deployment in the api namespace (already exists)
  requests        cpu 100m / memory 128Mi
  limits          cpu 200m / memory 256Mi
  After the change both pods must be Ready with the new settings.

Verify:
  kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources}'
  kubectl get pods -n api -l app=api-worker -o jsonpath='{.items[*].status.qosClass}'
EOF
}
q2_title_ko() { echo "기존 Deployment 에 Requests / Limits 추가"; }
q2_text_ko() { cat <<'EOF'
A Deployment named api-worker already exists in the api namespace with 2
replicas and no resource requests or limits.

Update it so that its container (worker) has:
  requests    cpu 100m, memory 128Mi
  limits      cpu 200m, memory 256Mi

All pods must be rolled out and Ready with the new resource settings.

[조건]
  대상            api 네임스페이스의 api-worker Deployment (이미 존재)
  requests        cpu 100m / memory 128Mi
  limits          cpu 200m / memory 256Mi
  변경 후 파드 2개가 모두 새 설정으로 Ready

[확인]
  kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources}'
  kubectl get pods -n api -l app=api-worker -o jsonpath='{.items[*].status.qosClass}'
EOF
}
q2_hint() { cat <<'EOF'
kubectl set resources deployment api-worker -n api \
  --requests=cpu=100m,memory=128Mi --limits=cpu=200m,memory=256Mi
kubectl rollout status deployment/api-worker -n api
EOF
}
q2_grade() {
  check "api-worker Deployment 가 api 네임스페이스에 존재한다" "kubectl get deployment api-worker -n api"
  check_output "requests.cpu 가 100m 이다" \
    "kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}'" "^100m$"
  check_output "requests.memory 가 128Mi 이다" \
    "kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}'" "^128Mi$"
  check_output "limits.cpu 가 200m 이다" \
    "kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}'" "^200m$"
  check_output "limits.memory 가 256Mi 이다" \
    "kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'" "^256Mi$"
  wait_ready "-l app=api-worker" api || true
  check_output "api-worker 파드 2개가 모두 Ready 이다 (롤아웃 완료)" \
    "kubectl get deployment api-worker -n api -o jsonpath='{.status.readyReplicas}'" "^2$"
  check_output "실행 중인 파드에 limits.memory 256Mi 가 실제 반영되어 있다" \
    "kubectl get pods -n api -l app=api-worker -o jsonpath='{range .items[*]}{.spec.containers[0].resources.limits.memory}{\"\\n\"}{end}' | sort -u | tr -d '\\n'" "^256Mi$"
  check_output "파드 QoS 클래스가 Burstable 이다 (requests < limits)" \
    "kubectl get pods -n api -l app=api-worker -o jsonpath='{range .items[*]}{.status.qosClass}{\"\\n\"}{end}' | sort -u | tr -d '\\n'" "^Burstable$"
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Configure liveness and readiness probes"; }
q3_text() { cat <<'EOF'
In the api namespace, create a Pod named health-pod using image nginx:1.24
with the following probes configured on its container:

  livenessProbe    HTTP GET on path / port 80
                   initialDelaySeconds 5, periodSeconds 10, failureThreshold 3
  readinessProbe   HTTP GET on path / port 80
                   initialDelaySeconds 3, periodSeconds 5

The Pod must become Ready and must not restart.

Verify:
  kubectl get pod health-pod -n api
  kubectl describe pod health-pod -n api | grep -E 'Liveness|Readiness'
EOF
}
q3_title_ko() { echo "Liveness / Readiness Probe 작성"; }
q3_text_ko() { cat <<'EOF'
In the api namespace, create a Pod named health-pod using image nginx:1.24
with the following probes configured on its container:

  livenessProbe    HTTP GET on path / port 80
                   initialDelaySeconds 5, periodSeconds 10, failureThreshold 3
  readinessProbe   HTTP GET on path / port 80
                   initialDelaySeconds 3, periodSeconds 5

The Pod must become Ready and must not restart.

[확인]
  kubectl get pod health-pod -n api
  kubectl describe pod health-pod -n api | grep -E 'Liveness|Readiness'
EOF
}
q3_hint() { cat <<'EOF'
kubectl run health-pod --image=nginx:1.24 -n api --dry-run=client -o yaml > health-pod.yaml
# containers[0] 에 livenessProbe / readinessProbe 추가 후
kubectl apply -f health-pod.yaml
EOF
}
q3_grade() {
  check "health-pod Pod 가 api 네임스페이스에 존재한다" "kubectl get pod health-pod -n api"
  check_output "health-pod 이미지가 nginx:1.24 이다" \
    "kubectl get pod health-pod -n api -o jsonpath='{.spec.containers[0].image}'" "^nginx:1\.24$"
  local b='kubectl get pod health-pod -n api -o jsonpath='
  check_output "livenessProbe 가 httpGet path / 이다" "${b}'{.spec.containers[0].livenessProbe.httpGet.path}'" "^/$"
  check_output "livenessProbe 포트가 80 이다" "${b}'{.spec.containers[0].livenessProbe.httpGet.port}'" "^80$"
  check_output "livenessProbe initialDelaySeconds 가 5 이다" "${b}'{.spec.containers[0].livenessProbe.initialDelaySeconds}'" "^5$"
  check_output "livenessProbe periodSeconds 가 10 이다" "${b}'{.spec.containers[0].livenessProbe.periodSeconds}'" "^10$"
  check_output "livenessProbe failureThreshold 가 3 이다" "${b}'{.spec.containers[0].livenessProbe.failureThreshold}'" "^3$"
  check_output "readinessProbe 가 httpGet path / 이다" "${b}'{.spec.containers[0].readinessProbe.httpGet.path}'" "^/$"
  check_output "readinessProbe 포트가 80 이다" "${b}'{.spec.containers[0].readinessProbe.httpGet.port}'" "^80$"
  check_output "readinessProbe initialDelaySeconds 가 3 이다" "${b}'{.spec.containers[0].readinessProbe.initialDelaySeconds}'" "^3$"
  check_output "readinessProbe periodSeconds 가 5 이다" "${b}'{.spec.containers[0].readinessProbe.periodSeconds}'" "^5$"
  wait_ready "health-pod" api || true
  check_output "health-pod 가 Ready 상태이다 (readinessProbe 통과)" "${b}'{.status.containerStatuses[0].ready}'" "^true$"
  check_output "health-pod 재시작 횟수가 0 이다 (livenessProbe 통과)" "${b}'{.status.containerStatuses[0].restartCount}'" "^0$"
}

exam_main "$@"
