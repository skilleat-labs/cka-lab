#!/usr/bin/env bash
# CKA 12강 실습 — 스토리지 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 12강 실습 — 스토리지 (PV/PVC · 기본 StorageClass · StatefulSet · emptyDir · 주어진 파일에 PVC 붙이기)"
EXAM_NQ=5

# Q5 — 학생이 고쳐서 apply 할 Deployment 파일 (setup 이 만든다. 학생에게는 work/records-deploy.yaml)
DEPLOY_FILE="$WORK_DIR/records-deploy.yaml"
# Q2 — 시험 시작 전에 클러스터에 원래 있던 기본 StorageClass 이름 (cleanup 이 되돌린다)
SC_REC="$WORK_DIR/.sc-default-before"

# 지금 기본으로 지정된 StorageClass 이름들 (한 줄에 하나)
sc_defaults() {
  kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}={.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null \
    | grep '=true$' | cut -d= -f1
}

exam_cleanup() {
  kdel pod shared-vol -n default
  kdel statefulset web-sts -n default
  kdel pvc data-pvc sc-pvc -n default
  kdel pvc www-storage-web-sts-0 www-storage-web-sts-1 www-storage-web-sts-2 -n default
  kdel pv data-pv
  kdel storageclass local-storage legacy-hdd
  # Q5 — 네임스페이스(Deployment·PVC 포함)와 미리 만든 PV, 문제 파일
  kubectl get namespace records &>/dev/null && kubectl delete namespace records --wait=false &>/dev/null
  kdel pv records-pv
  rm -f "$DEPLOY_FILE"
  # Q2 — 학생이 해제한 '원래 기본 StorageClass' 를 되돌린다 (시작 때 적어 둔 것만)
  local sc restored=""
  if [[ -f "$SC_REC" ]]; then
    while IFS= read -r sc; do
      [[ -z "$sc" ]] && continue
      kubectl annotate storageclass "$sc" storageclass.kubernetes.io/is-default-class=true --overwrite &>/dev/null \
        && restored+="$sc "
    done < "$SC_REC"
    rm -f "$SC_REC"
  fi
  echo "  data-pv / data-pvc / local-storage / legacy-hdd / sc-pvc / web-sts / shared-vol 삭제"
  echo "  records 네임스페이스 / records-pv / work/records-deploy.yaml 삭제"
  [[ -n "$restored" ]] && echo "  원래 기본 StorageClass 복구: $restored"
  return 0
}

exam_setup() {
  # ── Q2: 원래 기본 StorageClass 를 적어 둔다 → cleanup 이 복구한다
  #   (이 세트가 만드는 legacy-hdd · local-storage 는 제외 — 지난 시도의 잔여물일 수 있다)
  sc_defaults | grep -vxE 'legacy-hdd|local-storage' > "$SC_REC" 2>/dev/null || true

  # ── Q2: 이미 기본으로 지정된 StorageClass (학생이 해제해야 한다)
  # ── Q5: 관리자가 미리 만든 PV 와 네임스페이스
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: legacy-hdd
  annotations: { storageclass.kubernetes.io/is-default-class: "true" }
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: Namespace
metadata: { name: records }
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: records-pv
  labels: { app: records }
spec:
  storageClassName: records-hdd
  capacity: { storage: 250Mi }
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  hostPath: { path: /tmp/records-data, type: DirectoryOrCreate }
YAML

  # ── Q5: 볼륨이 없는 Deployment 매니페스트 — 적용하지 않고 파일로만 둔다
  cat > "$DEPLOY_FILE" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: records-app
  namespace: records
  labels:
    app: records-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: records-app
  template:
    metadata:
      labels:
        app: records-app
    spec:
      containers:
      - name: web
        image: nginx:1.24
        ports:
        - containerPort: 80
YAML

  echo "  Q2  StorageClass legacy-hdd (현재 기본으로 지정됨)"
  echo "  Q5  records 네임스페이스 · PV records-pv · work/records-deploy.yaml (아직 적용 안 됨)"
  local others
  others=$(tr '\n' ' ' < "$SC_REC" 2>/dev/null)
  [[ -n "${others// /}" ]] && echo -e "  ${ORANGE}참고: 이 클러스터에는 원래 기본 StorageClass 가 있습니다 → ${others}(Q2 에서 함께 해제해야 합니다 · clean 때 복구됩니다)${RESET}"
  return 0
}

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
  storageClassName  manual

PersistentVolumeClaim
  name              data-pvc  (namespace default)
  request           1Gi
  accessMode        ReadWriteOnce
  storageClassName  manual

Note: this cluster has a default StorageClass. A PVC without
storageClassName would receive it and never bind to data-pv.

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
  storageClassName  manual

PersistentVolumeClaim
  이름              data-pvc  (default 네임스페이스)
  용량 요청         1Gi
  accessMode        ReadWriteOnce
  storageClassName  manual

참고: 이 클러스터에는 기본 StorageClass 가 있다. PVC 에 storageClassName 을
적지 않으면 그 기본 클래스가 붙어서 data-pv 에 묶이지 않는다.

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
  check_output "PV storageClassName manual" "kubectl get pv data-pv -o jsonpath='{.spec.storageClassName}'" '^manual$'
  check "PVC data-pvc 존재 (default)" "kubectl get pvc data-pvc -n default"
  check_output "PVC storageClassName manual" "kubectl get pvc data-pvc -n default -o jsonpath='{.spec.storageClassName}'" '^manual$'
  check_output "PVC 가 Bound" "kubectl get pvc data-pvc -n default -o jsonpath='{.status.phase}'" '^Bound$'
  check_output "data-pvc 가 data-pv 에 묶였다" \
    "kubectl get pvc data-pvc -n default -o jsonpath='{.spec.volumeName}'" '^data-pv$'
}
q1_hint() { cat <<'EOF'
# PV 는 kubectl create 가 없다 — YAML 을 쓴다
#   kind: PersistentVolume / spec.capacity.storage: 1Gi
#   spec.accessModes: [ReadWriteOnce] / spec.hostPath.path: /tmp/k8s-data
#   spec.persistentVolumeReclaimPolicy: Retain / spec.storageClassName: manual
# PVC 는 storageClassName·요청 용량·accessMode 가 PV 와 맞아야 Bound 된다.
# PVC 에 storageClassName 을 빼먹으면 기본 클래스(legacy-hdd 등)가 붙어 Pending 이다
#   → PVC 의 storageClassName 은 수정이 안 된다. 지우고 다시 만든다.
kubectl get pv,pvc
kubectl describe pvc data-pvc      # Bound 가 안 되면 Events 를 본다
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "StorageClass as the only default, and a PVC"; }
q2_text() { cat <<'EOF'
Create a StorageClass, make it the cluster default, and create a PVC
that requests it.

StorageClass
  name                local-storage
  provisioner         kubernetes.io/no-provisioner
  volumeBindingMode   WaitForFirstConsumer

Default
  local-storage must be the ONLY default StorageClass of the cluster.
  Another StorageClass is currently marked as default — unset it.
  Do not delete any existing StorageClass.

PersistentVolumeClaim
  name                sc-pvc  (namespace default)
  storageClassName    local-storage
  request             500Mi
  accessMode          ReadWriteOnce

The PVC stays Pending until a Pod uses it — that is expected with
WaitForFirstConsumer.

Verify:
  kubectl get storageclass          -> (default) only on local-storage
  kubectl get pvc sc-pvc
EOF
}
q2_title_ko() { echo "StorageClass 를 유일한 기본으로 + PVC"; }
q2_text_ko() { cat <<'EOF'
StorageClass 를 만들어 클러스터의 기본으로 지정하고, 그것을 요청하는
PVC 를 만드시오.

StorageClass
  이름                local-storage
  provisioner         kubernetes.io/no-provisioner
  volumeBindingMode   WaitForFirstConsumer

기본 지정
  local-storage 가 클러스터의 '유일한' 기본 StorageClass 여야 한다.
  지금 다른 StorageClass 가 기본으로 지정돼 있다 — 그 지정을 해제한다.
  기존 StorageClass 는 지우지 않는다.

PersistentVolumeClaim
  이름                sc-pvc  (default 네임스페이스)
  storageClassName    local-storage
  용량 요청           500Mi
  accessMode          ReadWriteOnce

파드가 쓰기 전까지 PVC 는 Pending 으로 남는다 — WaitForFirstConsumer 라
정상이다.

[확인]
  kubectl get storageclass          → (default) 가 local-storage 에만
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
  check_output "local-storage 가 기본으로 지정됐다 (is-default-class=true)" \
    "kubectl get storageclass local-storage -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'" '^true$'
  check "legacy-hdd 는 지우지 않았다" "kubectl get storageclass legacy-hdd"
  local defaults
  defaults=$(sc_defaults | tr '\n' ' ')
  check_result "기본 StorageClass 가 local-storage 하나뿐 (현재: ${defaults:-없음})" \
    "$([[ "$defaults" == "local-storage " ]] && echo 0 || echo 1)" "다른 클래스의 is-default-class 를 false 로"
}
q2_hint() { cat <<'EOF'
# 만들 때부터 기본으로 — 애너테이션 한 줄
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer

# 지금 기본인 클래스를 찾아서 해제한다 — (default) 표시를 본다
kubectl get sc
kubectl patch storageclass <기존-기본> \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

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

# ══════════════════════════════════════════════════════════════
q5_title() { echo "PVC for an existing PV, mounted via a given manifest"; }
q5_text() { cat <<'EOF'
An administrator has already created the PersistentVolume records-pv.
The Deployment records-app (namespace records) is not running — its
manifest is in the file:

  work/records-deploy.yaml

  (a) In the records namespace create a PersistentVolumeClaim named
      records-pvc that binds to records-pv.
        access mode   ReadWriteOnce
        request       250Mi
      Inspect records-pv for anything else the claim needs to match.

  (b) Edit work/records-deploy.yaml so that the Pod mounts records-pvc
        volume name   data
        mountPath     /usr/share/nginx/html   (container web)
      Then apply the file. Do not create the Deployment any other way.

The records-app Pod must be Running with the PVC mounted.

Verify:
  kubectl get pv records-pv
  kubectl -n records get pvc records-pvc        -> STATUS Bound
  kubectl -n records get deploy,pod
EOF
}
q5_title_ko() { echo "기존 PV 에 맞는 PVC + 주어진 Deployment 파일 수정"; }
q5_text_ko() { cat <<'EOF'
관리자가 PersistentVolume records-pv 를 미리 만들어 두었다.
records 네임스페이스의 Deployment records-app 은 아직 실행되지 않았고,
매니페스트가 아래 파일에 있다.

  work/records-deploy.yaml

  (a) records 네임스페이스에 records-pv 에 묶이는 PVC records-pvc 를 만든다.
        accessMode    ReadWriteOnce
        용량 요청     250Mi
      그 밖에 맞춰야 할 값은 records-pv 를 직접 보고 찾는다.

  (b) work/records-deploy.yaml 을 고쳐 파드가 records-pvc 를 마운트하게 한다.
        볼륨 이름     data
        mountPath     /usr/share/nginx/html   (컨테이너 web)
      그다음 그 파일을 apply 한다. 다른 방법으로 Deployment 를 만들지 않는다.

records-app 파드가 PVC 를 마운트한 채 Running 이어야 한다.

[확인]
  kubectl get pv records-pv
  kubectl -n records get pvc records-pvc        → STATUS Bound
  kubectl -n records get deploy,pod
EOF
}
q5_grade() {
  check "PVC records-pvc 존재 (records)" "kubectl -n records get pvc records-pvc"
  check_output "요청 250Mi · ReadWriteOnce" \
    "kubectl -n records get pvc records-pvc -o jsonpath='{.spec.resources.requests.storage}/{.spec.accessModes[0]}'" '^250Mi/ReadWriteOnce$'
  check_output "storageClassName 이 PV 와 같다 (records-hdd)" \
    "kubectl -n records get pvc records-pvc -o jsonpath='{.spec.storageClassName}'" '^records-hdd$'
  check_output "records-pv 에 Bound" \
    "kubectl -n records get pvc records-pvc -o jsonpath='{.status.phase}/{.spec.volumeName}'" '^Bound/records-pv$'
  local fileok=1
  [[ -f "$DEPLOY_FILE" ]] && grep -qE 'claimName:[[:space:]]*"?records-pvc' "$DEPLOY_FILE" && fileok=0
  check_result "work/records-deploy.yaml 파일에 claimName: records-pvc 를 넣었다" "$fileok" \
    "파일을 직접 고쳐서 apply 해야 한다 (kubectl edit 로는 파일이 바뀌지 않는다)"
  check "Deployment records-app 존재" "kubectl -n records get deployment records-app"
  check_output "파드 템플릿 볼륨이 records-pvc 를 쓴다" \
    "kubectl -n records get deployment records-app -o jsonpath='{.spec.template.spec.volumes[*].persistentVolumeClaim.claimName}'" '(^| )records-pvc( |$)'
  check_output "컨테이너 web 의 mountPath /usr/share/nginx/html" \
    "kubectl -n records get deployment records-app -o jsonpath='{.spec.template.spec.containers[?(@.name==\"web\")].volumeMounts[*].mountPath}'" '(^| )/usr/share/nginx/html( |$)'
  wait_ready "-l app=records-app" records
  check_output "Deployment 가 준비됨 (ready 1/1)" \
    "kubectl -n records get deployment records-app -o jsonpath='{.status.readyReplicas}/{.spec.replicas}'" '^1/1$'
  check_output "Running 파드가 records-pvc 를 마운트했다" \
    "kubectl -n records get pods -l app=records-app -o jsonpath='{range .items[?(@.status.phase==\"Running\")]}{.spec.volumes[*].persistentVolumeClaim.claimName}{\" \"}{end}'" 'records-pvc'
}
q5_hint() { cat <<'EOF'
# (a) PV 를 먼저 읽는다 — 클래스·용량·모드를 맞춰야 묶인다
kubectl get pv records-pv
kubectl get pv records-pv -o jsonpath='{.spec.storageClassName}{"\n"}'
#   storageClassName 을 빼먹으면 기본 클래스가 붙어 Pending → 지우고 다시 만든다
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: records-pvc, namespace: records }
spec:
  storageClassName: <PV 와 같은 값>
  accessModes: ["ReadWriteOnce"]
  resources: { requests: { storage: 250Mi } }

# (b) 파일에 두 블록을 추가한다 — volumes 는 template.spec 아래, volumeMounts 는 컨테이너 아래
#      volumes:
#      - name: data
#        persistentVolumeClaim:
#          claimName: records-pvc
#      containers:
#      - name: web
#        ...
#        volumeMounts:
#        - name: data
#          mountPath: /usr/share/nginx/html
vi work/records-deploy.yaml
kubectl apply -f work/records-deploy.yaml
kubectl -n records rollout status deploy records-app
EOF
}

exam_main "$@"
