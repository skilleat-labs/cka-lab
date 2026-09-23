#!/usr/bin/env bash
# CKA 5강 실습 — 스토리지 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 5강 실습 — 스토리지 (PV/PVC · StorageClass · StatefulSet · emptyDir)"
EXAM_NQ=4

exam_cleanup() {
  kdel pod shared-vol -n default
  kdel statefulset web-sts -n default
  kdel pvc data-pvc sc-pvc -n default
  kdel pvc www-storage-web-sts-0 www-storage-web-sts-1 www-storage-web-sts-2 -n default
  kdel pv data-pv
  kdel storageclass local-storage
  echo "  data-pv / data-pvc / local-storage / sc-pvc / web-sts / shared-vol 삭제"
}
exam_setup() { echo "  (미리 만들어둘 것 없음)"; }

# ══════════════════════════════════════════════════════════════
q1_title() { echo "PersistentVolume and PVC, bound"; }
q1_text() { cat <<'EOF'
Create a PersistentVolume and a PersistentVolumeClaim and make them Bound.

PersistentVolume
  name              data-pv
  type              hostPath, path=/tmp/k8s-data
  capacity          1Gi
  accessMode        ReadWriteOnce
  reclaimPolicy     Retain

PersistentVolumeClaim
  name              data-pvc  (namespace default)
  request           1Gi
  accessMode        ReadWriteOnce

Verify:
  kubectl get pv data-pv
  kubectl get pvc data-pvc      -> STATUS Bound
EOF
}
q1_title_ko() { echo "PersistentVolume + PVC 바인딩"; }
q1_text_ko() { cat <<'EOF'
PV 와 PVC 를 만들어 Bound 시키시오.

PersistentVolume
  이름              data-pv
  타입              hostPath, path=/tmp/k8s-data
  용량              1Gi
  accessMode        ReadWriteOnce
  reclaimPolicy     Retain

PersistentVolumeClaim
  이름              data-pvc  (default 네임스페이스)
  용량 요청         1Gi
  accessMode        ReadWriteOnce

[확인]
  kubectl get pv data-pv
  kubectl get pvc data-pvc      → STATUS Bound
EOF
}
q1_grade() {
  check "PV data-pv 존재" "kubectl get pv data-pv"
  check_output "용량 1Gi" "kubectl get pv data-pv -o jsonpath='{.spec.capacity.storage}'" '^1Gi$'
  check_output "accessMode ReadWriteOnce" "kubectl get pv data-pv -o jsonpath='{.spec.accessModes[0]}'" '^ReadWriteOnce$'
  check_output "hostPath /tmp/k8s-data" "kubectl get pv data-pv -o jsonpath='{.spec.hostPath.path}'" '^/tmp/k8s-data$'
  check_output "reclaimPolicy Retain" "kubectl get pv data-pv -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'" '^Retain$'
  check "PVC data-pvc 존재 (default)" "kubectl get pvc data-pvc -n default"
  check_output "PVC 가 Bound" "kubectl get pvc data-pvc -n default -o jsonpath='{.status.phase}'" '^Bound$'
  check_output "data-pvc 가 data-pv 에 묶였다" \
    "kubectl get pvc data-pvc -n default -o jsonpath='{.spec.volumeName}'" '^data-pv$'
}
q1_hint() { cat <<'EOF'
# PV 는 kubectl create 가 없다 — YAML 을 쓴다
#   kind: PersistentVolume / spec.capacity.storage: 1Gi
#   spec.accessModes: [ReadWriteOnce] / spec.hostPath.path: /tmp/k8s-data
#   spec.persistentVolumeReclaimPolicy: Retain
# PVC 는 요청 용량·accessMode 가 PV 와 맞아야 Bound 된다.
kubectl get pv,pvc
kubectl describe pvc data-pvc      # Bound 가 안 되면 Events 를 본다
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "StorageClass and a PVC that uses it"; }
q2_text() { cat <<'EOF'
Create a StorageClass and a PVC that requests it.

StorageClass
  name                local-storage
  provisioner         kubernetes.io/no-provisioner
  volumeBindingMode   WaitForFirstConsumer

PersistentVolumeClaim
  name                sc-pvc  (namespace default)
  storageClassName    local-storage
  request             500Mi
  accessMode          ReadWriteOnce

The PVC stays Pending until a Pod uses it — that is expected with
WaitForFirstConsumer.

Verify:
  kubectl get storageclass local-storage
  kubectl get pvc sc-pvc
EOF
}
q2_title_ko() { echo "StorageClass + 그것을 쓰는 PVC"; }
q2_text_ko() { cat <<'EOF'
StorageClass 와 그것을 요청하는 PVC 를 만드시오.

StorageClass
  이름                local-storage
  provisioner         kubernetes.io/no-provisioner
  volumeBindingMode   WaitForFirstConsumer

PersistentVolumeClaim
  이름                sc-pvc  (default 네임스페이스)
  storageClassName    local-storage
  용량 요청           500Mi
  accessMode          ReadWriteOnce

파드가 쓰기 전까지 PVC 는 Pending 으로 남는다 — WaitForFirstConsumer 라
정상이다.

[확인]
  kubectl get storageclass local-storage
  kubectl get pvc sc-pvc
EOF
}
q2_grade() {
  check "StorageClass local-storage 존재" "kubectl get storageclass local-storage"
  check_output "provisioner no-provisioner" \
    "kubectl get storageclass local-storage -o jsonpath='{.provisioner}'" 'kubernetes.io/no-provisioner'
  check_output "volumeBindingMode WaitForFirstConsumer" \
    "kubectl get storageclass local-storage -o jsonpath='{.volumeBindingMode}'" '^WaitForFirstConsumer$'
  check "PVC sc-pvc 존재 (default)" "kubectl get pvc sc-pvc -n default"
  check_output "sc-pvc 의 storageClassName" \
    "kubectl get pvc sc-pvc -n default -o jsonpath='{.spec.storageClassName}'" '^local-storage$'
  check_output "요청 용량 500Mi" \
    "kubectl get pvc sc-pvc -n default -o jsonpath='{.spec.resources.requests.storage}'" '^500Mi$'
  check_output "accessMode ReadWriteOnce" \
    "kubectl get pvc sc-pvc -n default -o jsonpath='{.spec.accessModes[0]}'" '^ReadWriteOnce$'
}
q2_hint() { cat <<'EOF'
#   kind: StorageClass
#   provisioner: kubernetes.io/no-provisioner
#   volumeBindingMode: WaitForFirstConsumer
kubectl get sc
kubectl describe pvc sc-pvc     # "waiting for first consumer" 면 정상
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "StatefulSet with volumeClaimTemplates"; }
q3_text() { cat <<'EOF'
In the default namespace, create a StatefulSet named web-sts.

  replicas              3
  image                 nginx:1.24
  volumeClaimTemplate   name www-storage / 1Gi / ReadWriteOnce
  mountPath             /usr/share/nginx/html

Three PVCs must be created automatically:
  www-storage-web-sts-0 / -1 / -2

Verify:
  kubectl get statefulset web-sts
  kubectl get pvc
EOF
}
q3_title_ko() { echo "StatefulSet + volumeClaimTemplates"; }
q3_text_ko() { cat <<'EOF'
default 네임스페이스에 web-sts StatefulSet 을 만드시오.

  replicas              3
  이미지                nginx:1.24
  volumeClaimTemplate   이름 www-storage / 1Gi / ReadWriteOnce
  mountPath             /usr/share/nginx/html

PVC 3개가 자동 생성되어야 한다:
  www-storage-web-sts-0 / -1 / -2

[확인]
  kubectl get statefulset web-sts
  kubectl get pvc
EOF
}
q3_grade() {
  check "StatefulSet web-sts 존재" "kubectl get statefulset web-sts -n default"
  check_output "replicas 3" "kubectl get statefulset web-sts -n default -o jsonpath='{.spec.replicas}'" '^3$'
  check_output "이미지 nginx:1.24" \
    "kubectl get statefulset web-sts -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" '^nginx:1\.24$'
  check_output "volumeClaimTemplate 이름 www-storage" \
    "kubectl get statefulset web-sts -n default -o jsonpath='{.spec.volumeClaimTemplates[0].metadata.name}'" '^www-storage$'
  check_output "요청 용량 1Gi" \
    "kubectl get statefulset web-sts -n default -o jsonpath='{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}'" '^1Gi$'
  check_output "mountPath /usr/share/nginx/html" \
    "kubectl get statefulset web-sts -n default -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}'" '/usr/share/nginx/html'
  check "PVC www-storage-web-sts-0 자동 생성" "kubectl get pvc www-storage-web-sts-0 -n default"
  check "PVC www-storage-web-sts-1 자동 생성" "kubectl get pvc www-storage-web-sts-1 -n default"
  check "PVC www-storage-web-sts-2 자동 생성" "kubectl get pvc www-storage-web-sts-2 -n default"
}
q3_hint() { cat <<'EOF'
# StatefulSet 도 kubectl create 가 없다 — YAML.
#   spec.serviceName, spec.selector.matchLabels, spec.template.metadata.labels 가 모두 맞아야 한다
#   spec.volumeClaimTemplates:
#   - metadata: { name: www-storage }
#     spec: { accessModes: [ReadWriteOnce], resources: { requests: { storage: 1Gi } } }
# PVC 가 Bound 되려면 그만큼의 PV 가 있어야 한다. 여기서는 PVC 생성까지만 채점한다.
kubectl get pvc
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Two containers sharing an emptyDir volume"; }
q4_text() { cat <<'EOF'
In the default namespace, create a Pod named shared-vol with two containers
that share one emptyDir volume.

  volume        name shared, type emptyDir, mounted at /shared in both
  container 1   name writer / busybox
                sh -c 'while true; do date >> /shared/log.txt; sleep 5; done'
  container 2   name reader / busybox
                sh -c 'tail -f /shared/log.txt'

The Pod must be Running with both containers ready.

Verify:
  kubectl get pod shared-vol
  kubectl logs shared-vol -c reader
EOF
}
q4_title_ko() { echo "emptyDir 를 공유하는 컨테이너 2개"; }
q4_text_ko() { cat <<'EOF'
default 네임스페이스에 shared-vol 파드를 만들되, 컨테이너 2개가
emptyDir 볼륨 하나를 공유하게 하시오.

  볼륨          이름 shared, 타입 emptyDir, 양쪽 다 /shared 에 마운트
  컨테이너 1    이름 writer / busybox
                sh -c 'while true; do date >> /shared/log.txt; sleep 5; done'
  컨테이너 2    이름 reader / busybox
                sh -c 'tail -f /shared/log.txt'

파드는 Running 이고 두 컨테이너가 모두 Ready 여야 한다.

[확인]
  kubectl get pod shared-vol
  kubectl logs shared-vol -c reader
EOF
}
q4_grade() {
  check "파드 shared-vol 존재" "kubectl get pod shared-vol -n default"
  wait_ready "shared-vol" default
  check_output "Running" "kubectl get pod shared-vol -n default -o jsonpath='{.status.phase}'" '^Running$'
  check_output "컨테이너가 2개" \
    "kubectl get pod shared-vol -n default -o jsonpath='{.spec.containers[*].name}' | wc -w" '^\s*2$'
  check_output "writer 컨테이너" \
    "kubectl get pod shared-vol -n default -o jsonpath='{.spec.containers[*].name}'" 'writer'
  check_output "reader 컨테이너" \
    "kubectl get pod shared-vol -n default -o jsonpath='{.spec.containers[*].name}'" 'reader'
  check_output "emptyDir 볼륨 사용" \
    "kubectl get pod shared-vol -n default -o jsonpath='{.spec.volumes[0].emptyDir}'" '\{'
  if kubectl get pod shared-vol -n default &>/dev/null; then
    check_output "writer 가 실제로 /shared/log.txt 에 쓰고 있다" \
      "kubectl exec shared-vol -n default -c writer -- cat /shared/log.txt 2>/dev/null | head -1" '[0-9]'
  else
    check_result "writer 가 /shared/log.txt 에 쓰고 있다" 1 "파드가 없음"
  fi
}
q4_hint() { cat <<'EOF'
#   spec:
#     volumes:
#     - name: shared
#       emptyDir: {}
#     containers:
#     - name: writer
#       image: busybox
#       command: ["sh","-c","while true; do date >> /shared/log.txt; sleep 5; done"]
#       volumeMounts: [{ name: shared, mountPath: /shared }]
#     - name: reader ... (같은 볼륨을 같은 경로에 마운트)
kubectl logs shared-vol -c reader
EOF
}

exam_main "$@"
