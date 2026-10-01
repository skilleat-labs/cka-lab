#!/usr/bin/env bash
# CKA Final Test — 출제 주제 13선 5유형 30분 점검 (100점 · 6문항)
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
#
# 목적: 2026 합격 후기에서 확인된 13개 주제를 5개 유형으로 묶고, 6문제를 30분 안에 푸는지 본다.
#   유형① 워크로드 고치기   Q1 HPA
#   유형② 트래픽 열고 막기   Q2 NodePort · Q3 NetworkPolicy Egress(+DNS)
#   유형③ 스토리지 붙이기   Q4 PV/PVC 바인딩
#   유형④ 클러스터 운영     Q5 etcd 스냅샷
#   유형⑤ 조회해서 파일로   Q6 Pod 목록 저장
# 문제마다 네임스페이스가 따로라 순서와 상관없이 풀 수 있다.
set -uo pipefail
EXAM_UNIT="점"
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA Final Test — 출제 주제 5유형 30분 점검 (100점 · 6문항)"
EXAM_NQ=6
EXAM_LIMIT_MIN="${EXAM_LIMIT_MIN:-30}"   # 제한시간(분) — 0 이면 무제한

OUT_DIR=/tmp/finaltest
ETCD_SNAP=$OUT_DIR/etcd.db
WEB_FILE=$OUT_DIR/web-pods.txt
BAD_FILE=$OUT_DIR/not-running.txt
NAMESPACES="scaling storefront vault records fleet"

exam_cleanup() {
  local ns
  for ns in $NAMESPACES; do
    kubectl get namespace $ns &>/dev/null && kubectl delete namespace $ns --wait=false &>/dev/null
  done
  for ns in $NAMESPACES; do
    kubectl wait --for=delete namespace/$ns --timeout=90s &>/dev/null || true
  done
  # PV 는 네임스페이스가 지워져 PVC 가 풀린 뒤에 지운다
  kubectl delete pv pv-archive --ignore-not-found --wait=false &>/dev/null || true
  rm -rf "$OUT_DIR" 2>/dev/null || sudo -n rm -rf "$OUT_DIR" 2>/dev/null || true
  echo "  scaling · storefront · vault · records · fleet 네임스페이스"
  echo "  PV pv-archive / $OUT_DIR 삭제"
}

exam_setup() {
  mkdir -p "$OUT_DIR"

  # ── Q1: CPU request 가 없는 Deployment
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: scaling }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: api-server, namespace: scaling, labels: { app: api-server } }
spec:
  replicas: 1
  selector: { matchLabels: { app: api-server } }
  template:
    metadata: { labels: { app: api-server } }
    spec:
      containers:
        - name: api
          image: nginx:1.27
          ports: [ { containerPort: 80 } ]
YAML
  echo "  Q1  scaling/api-server 배치 (resources 없음)"

  # ── Q2: 8080 에서 응답하는 앱 + 접속 시험용 파드
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: storefront }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: catalog, namespace: storefront, labels: { app: catalog } }
spec:
  replicas: 2
  selector: { matchLabels: { app: catalog } }
  template:
    metadata: { labels: { app: catalog } }
    spec:
      containers:
        - name: catalog
          image: hashicorp/http-echo:1.0
          args: ["-listen=:8080", "-text=catalog-ok"]
          ports: [ { containerPort: 8080 } ]
---
apiVersion: v1
kind: Pod
metadata: { name: client, namespace: storefront, labels: { app: client } }
spec:
  containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 3600"] } ]
YAML
  echo "  Q2  storefront/catalog (컨테이너 포트 8080) · storefront/client 배치"

  # ── Q3: 잠글 worker, 허용할 db, 막을 web
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: vault }
---
apiVersion: v1
kind: Pod
metadata: { name: worker, namespace: vault, labels: { app: worker } }
spec:
  containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 3600"] } ]
---
apiVersion: v1
kind: Pod
metadata: { name: db, namespace: vault, labels: { app: db } }
spec:
  containers: [ { name: nginx, image: nginx:1.27, ports: [ { containerPort: 80 } ] } ]
---
apiVersion: v1
kind: Service
metadata: { name: db, namespace: vault }
spec:
  selector: { app: db }
  ports: [ { port: 80, targetPort: 80 } ]
---
apiVersion: v1
kind: Pod
metadata: { name: web, namespace: vault, labels: { app: web } }
spec:
  containers: [ { name: nginx, image: nginx:1.27, ports: [ { containerPort: 80 } ] } ]
---
apiVersion: v1
kind: Service
metadata: { name: web, namespace: vault }
spec:
  selector: { app: web }
  ports: [ { port: 80, targetPort: 80 } ]
YAML
  echo "  Q3  vault/worker · vault/db(+Service) · vault/web(+Service) 배치"

  # ── Q4: 붙을 PV 가 없어 Pending 인 PVC
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: records }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: archive-claim, namespace: records }
spec:
  storageClassName: archive-manual
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 500Mi } }
YAML
  echo "  Q4  records/archive-claim (Pending) 배치"

  # ── Q5: etcdctl 확인
  echo -n "  Q5  "; etcd_tool_check || true

  # ── Q6: 상태가 섞인 파드 다섯 개
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: fleet }
---
apiVersion: v1
kind: Pod
metadata: { name: web-a, namespace: fleet, labels: { tier: web } }
spec: { containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 3600"] } ] }
---
apiVersion: v1
kind: Pod
metadata: { name: web-b, namespace: fleet, labels: { tier: web } }
spec: { containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 3600"] } ] }
---
apiVersion: v1
kind: Pod
metadata: { name: web-c, namespace: fleet, labels: { tier: web } }
spec: { containers: [ { name: c, image: busybox:0.0-does-not-exist, command: ["sh", "-c", "sleep 3600"] } ] }
---
apiVersion: v1
kind: Pod
metadata: { name: api-a, namespace: fleet, labels: { tier: api } }
spec: { containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 3600"] } ] }
---
apiVersion: v1
kind: Pod
metadata: { name: batch-a, namespace: fleet, labels: { tier: batch } }
spec: { containers: [ { name: c, image: busybox:0.0-does-not-exist, command: ["sh", "-c", "sleep 3600"] } ] }
YAML
  echo "  Q6  fleet 네임스페이스에 파드 5개 배치 · $OUT_DIR 디렉터리 준비"
  return 0
}

# ══════════════════════════════════════════════════════════════
# Q1 — 유형① 워크로드: HPA + scaleDown 안정화
# ══════════════════════════════════════════════════════════════
q1_title() { echo "[Type 1 · Workload] HPA with a scale-down window [15 pts]"; }
q1_text() { cat <<'EOF'
The Deployment api-server in the scaling namespace must scale on CPU.

  (a) Give the container a CPU request of 100m so that the HPA can compute
      utilization. Do not delete the Deployment.

  (b) Create a HorizontalPodAutoscaler (autoscaling/v2) named api-server
        target                Deployment api-server
        min / max replicas    2 / 6
        CPU utilization       60 %
        scale-down            stabilizationWindowSeconds 45

Verify:
  kubectl -n scaling get hpa api-server
  kubectl -n scaling get hpa api-server -o yaml | grep -A3 behavior
EOF
}
q1_title_ko() { echo "[유형① 워크로드] 스케일 다운 안정화가 있는 HPA [15점]"; }
q1_text_ko() { cat <<'EOF'
scaling 네임스페이스의 Deployment api-server 가 CPU 기준으로 늘고 줄어야 한다.

  (a) HPA 가 사용률을 계산할 수 있도록 컨테이너에 CPU request 100m 을 준다.
      Deployment 를 지우지 않는다.

  (b) HorizontalPodAutoscaler (autoscaling/v2) api-server 를 만든다
        대상                  Deployment api-server
        최소 / 최대           2 / 6
        CPU 사용률            60 %
        스케일 다운           stabilizationWindowSeconds 45

[확인]
  kubectl -n scaling get hpa api-server
  kubectl -n scaling get hpa api-server -o yaml | grep -A3 behavior
EOF
}
q1_hint() { cat <<'EOF'
kubectl -n scaling set resources deployment api-server --requests=cpu=100m

kubectl -n scaling autoscale deployment api-server --cpu-percent=60 --min=2 --max=6
# behavior 는 명령 옵션이 없다 → edit 로 spec 아래에 추가
kubectl -n scaling edit hpa api-server
#   spec:
#     behavior:
#       scaleDown:
#         stabilizationWindowSeconds: 45
EOF
}
q1_grade() {
  local hpa="kubectl -n scaling get hpa api-server -o jsonpath"
  check_output "Deployment 컨테이너에 cpu request 100m" \
    "kubectl -n scaling get deployment api-server -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}'" '^(100m|0\.1)$' 3
  check "HPA api-server 존재" "kubectl -n scaling get hpa api-server" 2
  check_output "대상이 Deployment api-server" "$hpa='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}'" '^Deployment/api-server$' 2
  check_output "최소 2 · 최대 6" "$hpa='{.spec.minReplicas}/{.spec.maxReplicas}'" '^2/6$' 3
  check_output "CPU 사용률 60%" \
    "$hpa='{.spec.metrics[?(@.resource.name==\"cpu\")].resource.target.averageUtilization}'" '^60$' 2
  check_output "scaleDown stabilizationWindowSeconds 45" \
    "$hpa='{.spec.behavior.scaleDown.stabilizationWindowSeconds}'" '^45$' 3
}

# ══════════════════════════════════════════════════════════════
# Q2 — 유형② 트래픽: NodePort (port / targetPort / nodePort 구분)
# ══════════════════════════════════════════════════════════════
q2_title() { echo "[Type 2 · Traffic] Expose a Deployment with a fixed NodePort [15 pts]"; }
q2_text() { cat <<'EOF'
The Deployment catalog in the storefront namespace listens on container port 8080.

Create a Service named catalog-svc
  type          NodePort
  port          80        (the port the Service receives)
  targetPort    8080      (the container port)
  nodePort      30180

The Pod storefront/client must get "catalog-ok" from http://catalog-svc .

Verify:
  kubectl -n storefront get svc catalog-svc
  kubectl -n storefront get endpoints catalog-svc
  kubectl -n storefront exec client -- wget -qO- -T 3 http://catalog-svc
EOF
}
q2_title_ko() { echo "[유형② 트래픽] nodePort 를 지정한 Service [15점]"; }
q2_text_ko() { cat <<'EOF'
storefront 네임스페이스의 Deployment catalog 는 컨테이너 포트 8080 에서 응답한다.

Service catalog-svc 를 만든다
  타입          NodePort
  port          80        (Service 가 받는 포트)
  targetPort    8080      (컨테이너 포트)
  nodePort      30180

storefront/client 파드에서 http://catalog-svc 로 "catalog-ok" 가 와야 한다.

[확인]
  kubectl -n storefront get svc catalog-svc
  kubectl -n storefront get endpoints catalog-svc
  kubectl -n storefront exec client -- wget -qO- -T 3 http://catalog-svc
EOF
}
q2_hint() { cat <<'EOF'
# expose 에는 nodePort 옵션이 없다 → 골격을 뽑아서 한 줄 추가
kubectl -n storefront expose deployment catalog --name=catalog-svc \
  --type=NodePort --port=80 --target-port=8080 --dry-run=client -o yaml > svc.yaml
#   spec.ports[0].nodePort: 30180
kubectl apply -f svc.yaml
EOF
}
q2_grade() {
  local svc="kubectl -n storefront get svc catalog-svc -o jsonpath"
  check "Service catalog-svc 존재" "kubectl -n storefront get svc catalog-svc" 2
  check_output "타입 NodePort" "$svc='{.spec.type}'" '^NodePort$' 2
  check_output "port 80" "$svc='{.spec.ports[0].port}'" '^80$' 2
  check_output "targetPort 8080" "$svc='{.spec.ports[0].targetPort}'" '^8080$' 3
  check_output "nodePort 30180" "$svc='{.spec.ports[0].nodePort}'" '^30180$' 2
  wait_ready "-l app=catalog" storefront || true
  check_output "Endpoints 가 비어 있지 않다 (셀렉터가 맞다)" \
    "kubectl -n storefront get endpoints catalog-svc -o jsonpath='{.subsets[*].addresses[*].ip}'" '[0-9]' 2
  wait_ready client storefront || true
  check_output "client → catalog-svc 응답 catalog-ok" \
    "kubectl -n storefront exec client -- wget -qO- -T 3 http://catalog-svc" 'catalog-ok' 2
}

# ══════════════════════════════════════════════════════════════
# Q3 — 유형② 트래픽: NetworkPolicy Egress + DNS
# ══════════════════════════════════════════════════════════════
q3_title() { echo "[Type 2 · Traffic] Egress policy that keeps DNS working [20 pts]"; }
q3_text() { cat <<'EOF'
In the vault namespace the Pod worker (label app=worker) may only talk to db.

Create a NetworkPolicy named worker-egress
  - applies to Pods labelled app=worker
  - restricts EGRESS only (ingress is not affected)
  - allows TCP 80 to Pods labelled app=db
  - allows DNS (UDP 53 and TCP 53) so that worker can resolve Service names

Expected result:
  worker -> http://db.vault    works   (by name)
  worker -> http://web.vault   blocked

Verify:
  kubectl -n vault exec worker -- nslookup db.vault.svc.cluster.local
  kubectl -n vault exec worker -- wget -qO- -T 3 http://db.vault
  kubectl -n vault exec worker -- wget -qO- -T 3 http://web.vault
EOF
}
q3_title_ko() { echo "[유형② 트래픽] DNS 를 살린 Egress 정책 [20점]"; }
q3_text_ko() { cat <<'EOF'
vault 네임스페이스의 worker 파드(레이블 app=worker)는 db 하고만 통신해야 한다.

NetworkPolicy worker-egress 를 만든다
  - 대상: app=worker 파드
  - EGRESS 만 제한한다 (Ingress 는 건드리지 않는다)
  - app=db 파드로 가는 TCP 80 허용
  - DNS(UDP 53 · TCP 53) 허용 — worker 가 Service 이름을 풀 수 있어야 한다

기대 결과:
  worker → http://db.vault    통과   (이름으로)
  worker → http://web.vault   차단

[확인]
  kubectl -n vault exec worker -- nslookup db.vault.svc.cluster.local
  kubectl -n vault exec worker -- wget -qO- -T 3 http://db.vault
  kubectl -n vault exec worker -- wget -qO- -T 3 http://web.vault
EOF
}
q3_hint() { cat <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: worker-egress, namespace: vault }
spec:
  podSelector: { matchLabels: { app: worker } }
  policyTypes: [Egress]
  egress:
    - to: [ { podSelector: { matchLabels: { app: db } } } ]
      ports: [ { protocol: TCP, port: 80 } ]
    - ports:                      # to 가 없으면 '어디로든' — DNS 서버가 kube-system 에 있어도 된다
        - { protocol: UDP, port: 53 }
        - { protocol: TCP, port: 53 }
EOF
}
q3_grade() {
  local np="kubectl -n vault get networkpolicy worker-egress -o jsonpath"
  check "worker-egress 존재" "kubectl -n vault get networkpolicy worker-egress" 2
  check_output "대상이 app=worker" "$np='{.spec.podSelector.matchLabels.app}'" '^worker$' 2
  check_output "policyTypes 가 Egress 만" "$np='{.spec.policyTypes}'" '^\["Egress"\]$' 2
  check_output "egress 규칙에 80 과 53 이 있다" \
    "$np='{.spec.egress[*].ports[*].port}' | tr ' ' '\n' | sort -u | tr '\n' ' '" '(^| )53 .*80 |(^| )80 .*53 ' 2

  wait_ready worker vault || true
  wait_ready db vault || true
  wait_ready web vault || true
  local dns=1 a b
  kubectl -n vault exec worker -- nslookup db.vault.svc.cluster.local &>/dev/null && dns=0
  check_result "worker 에서 DNS 조회가 된다" "$dns" "DNS(53) 를 열지 않았다 — 이름으로 접속하지 못한다" 4
  a=$(kubectl -n vault exec worker -- wget -qO- -T 3 http://db.vault 2>/dev/null)
  b=$(kubectl -n vault exec worker -- wget -qO- -T 3 http://web.vault 2>/dev/null)
  local served=1; echo "$a" | grep -qi nginx && served=0
  check_result "worker → db.vault 응답 (허용)" "$served" "응답 없음 — DNS 또는 app=db 허용 규칙 확인" 4
  # 허용 경로가 살아 있을 때만 '막힘' 을 믿는다
  check_result "worker → web.vault 차단" \
    "$([[ $served == 0 ]] && ! echo "$b" | grep -qi nginx && echo 0 || echo 1)" "web 이 닿는다 — 정책이 worker 를 고르는지·to 가 너무 넓지 않은지 확인" 4
}

# ══════════════════════════════════════════════════════════════
# Q4 — 유형③ 스토리지: Pending PVC 에 맞는 PV + Pod
# ══════════════════════════════════════════════════════════════
q4_title() { echo "[Type 3 · Storage] Bind a pending PVC and mount it [20 pts]"; }
q4_text() { cat <<'EOF'
The PVC archive-claim in the records namespace is Pending.
Do NOT change or recreate the PVC.

  (a) Create a PersistentVolume named pv-archive that the PVC will bind to
        capacity    1Gi
        hostPath    /mnt/archive   (type: DirectoryOrCreate)
      Read the PVC to find out what else must match.

  (b) Create a Pod named archive-reader in records
        image       busybox:1.36
        command     sh -c 'sleep 3600'
        mount       the PVC archive-claim at /data

The PVC must be Bound to pv-archive and the Pod must be Running.

Verify:
  kubectl get pv pv-archive
  kubectl -n records get pvc archive-claim
  kubectl -n records exec archive-reader -- touch /data/ok
EOF
}
q4_title_ko() { echo "[유형③ 스토리지] Pending PVC 에 맞는 PV 와 Pod [20점]"; }
q4_text_ko() { cat <<'EOF'
records 네임스페이스의 PVC archive-claim 이 Pending 이다.
PVC 는 고치거나 다시 만들지 않는다.

  (a) 이 PVC 가 붙을 PersistentVolume pv-archive 를 만든다
        용량        1Gi
        hostPath    /mnt/archive   (type: DirectoryOrCreate)
      그 밖에 맞춰야 할 값은 PVC 를 읽어서 찾는다.

  (b) records 에 Pod archive-reader 를 만든다
        이미지      busybox:1.36
        명령        sh -c 'sleep 3600'
        마운트      PVC archive-claim 을 /data 에

PVC 가 pv-archive 에 Bound 이고 Pod 가 Running 이어야 한다.

[확인]
  kubectl get pv pv-archive
  kubectl -n records get pvc archive-claim
  kubectl -n records exec archive-reader -- touch /data/ok
EOF
}
q4_hint() { cat <<'EOF'
kubectl -n records get pvc archive-claim -o yaml   # storageClassName · accessModes · 요청 용량

# 붙는 조건 세 가지: storageClassName 같음 · accessModes 맞음 · PV 용량 >= PVC 요청
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-archive }
spec:
  capacity: { storage: 1Gi }
  accessModes: [ReadWriteOnce]
  storageClassName: archive-manual
  hostPath: { path: /mnt/archive, type: DirectoryOrCreate }

# Pod 는 kubectl run ... --dry-run=client -o yaml 로 골격을 뽑고 volumes 를 추가
EOF
}
q4_grade() {
  local pv="kubectl get pv pv-archive -o jsonpath"
  local pvc="kubectl -n records get pvc archive-claim -o jsonpath"
  check "PV pv-archive 존재" "kubectl get pv pv-archive" 2
  check_output "용량 1Gi" "$pv='{.spec.capacity.storage}'" '^1Gi$' 1
  check_output "hostPath /mnt/archive" "$pv='{.spec.hostPath.path}'" '^/mnt/archive/?$' 1
  check_output "storageClassName 이 PVC 와 같다 (archive-manual)" "$pv='{.spec.storageClassName}'" '^archive-manual$' 2
  check_output "PVC 를 바꾸지 않았다 (archive-manual · 500Mi)" "$pvc='{.spec.storageClassName}/{.spec.resources.requests.storage}'" '^archive-manual/500Mi$' 1
  check_output "PVC 가 Bound" "$pvc='{.status.phase}'" '^Bound$' 3
  check_output "PVC 가 pv-archive 에 붙었다" "$pvc='{.spec.volumeName}'" '^pv-archive$' 2
  check_output "Pod 가 PVC archive-claim 을 쓴다" \
    "kubectl -n records get pod archive-reader -o jsonpath='{.spec.volumes[*].persistentVolumeClaim.claimName}'" '(^| )archive-claim( |$)' 2
  check_output "/data 에 마운트" \
    "kubectl -n records get pod archive-reader -o jsonpath='{.spec.containers[0].volumeMounts[*].mountPath}'" '(^| )/data( |$)' 2
  wait_ready archive-reader records || true
  check_output "Pod 가 Running" "kubectl -n records get pod archive-reader -o jsonpath='{.status.phase}'" '^Running$' 2
  check "/data 에 쓸 수 있다" "kubectl -n records exec archive-reader -- sh -c 'touch /data/.grade && rm /data/.grade'" 2
}

# ══════════════════════════════════════════════════════════════
# Q5 — 유형④ 클러스터 운영: etcd 스냅샷
# ══════════════════════════════════════════════════════════════
q5_title() { echo "[Type 4 · Cluster ops] Take an etcd snapshot [15 pts]"; }
q5_text() { cat <<'EOF'
On the control plane node, save a snapshot of the running etcd to

  /tmp/finaltest/etcd.db

  endpoint   https://127.0.0.1:2379
  CA cert    /etc/kubernetes/pki/etcd/ca.crt
  cert       /etc/kubernetes/pki/etcd/server.crt
  key        /etc/kubernetes/pki/etcd/server.key

Do not restore it. Leaving the cluster untouched is part of the task.

Verify:
  sudo ETCDCTL_API=3 etcdctl snapshot status /tmp/finaltest/etcd.db -w table
EOF
}
q5_title_ko() { echo "[유형④ 클러스터 운영] etcd 스냅샷 저장 [15점]"; }
q5_text_ko() { cat <<'EOF'
컨트롤 플레인 노드에서 실행 중인 etcd 의 스냅샷을 아래 경로에 저장한다.

  /tmp/finaltest/etcd.db

  endpoint   https://127.0.0.1:2379
  CA 인증서  /etc/kubernetes/pki/etcd/ca.crt
  인증서     /etc/kubernetes/pki/etcd/server.crt
  키         /etc/kubernetes/pki/etcd/server.key

복원은 하지 않는다. 클러스터를 건드리지 않는 것도 문제의 일부다.

[확인]
  sudo ETCDCTL_API=3 etcdctl snapshot status /tmp/finaltest/etcd.db -w table
EOF
}
q5_hint() { cat <<'EOF'
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/finaltest/etcd.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# sudo 를 빼면 인증서를 못 읽는다. 플래그는 --cacert (--ca-cert 아님)
EOF
}
q5_grade() {
  local size
  size=$(stat -c%s "$ETCD_SNAP" 2>/dev/null || stat -f%z "$ETCD_SNAP" 2>/dev/null \
         || sudo -n stat -c%s "$ETCD_SNAP" 2>/dev/null || echo 0)
  size="${size//[^0-9]/}"; size="${size:-0}"
  check_result "$ETCD_SNAP 파일이 있다" "$([[ $size -gt 0 ]] && echo 0 || echo 1)" "파일이 없거나 비어 있다" 3
  check_result "1MB 이상 (진짜 스냅샷인가 · 현재 ${size} bytes)" \
    "$([[ $size -ge 1000000 ]] && echo 0 || echo 1)" "touch 로 만든 빈 파일은 FAIL" 6
  # 상태 확인은 도구가 있을 때만 엄격하게 본다 (파드 안의 etcdctl 로 푼 경우를 막지 않으려고)
  local st=1 note="snapshot status 로 읽히지 않는다 — 깨진 파일"
  if command -v etcdutl &>/dev/null || command -v etcdctl &>/dev/null; then
    { etcdutl snapshot status "$ETCD_SNAP" || sudo -n etcdutl snapshot status "$ETCD_SNAP" \
      || ETCDCTL_API=3 etcdctl snapshot status "$ETCD_SNAP" || sudo -n env ETCDCTL_API=3 etcdctl snapshot status "$ETCD_SNAP"; } \
      2>/dev/null | grep -q '[0-9]' && st=0
  else
    [[ $size -ge 1000000 ]] && st=0
    note="호스트에 etcdctl 이 없어 크기로만 판정"
  fi
  check_result "snapshot status 로 읽힌다" "$st" "$note" 6
}

# ══════════════════════════════════════════════════════════════
# Q6 — 유형⑤ 조회: 조건에 맞는 파드 이름을 파일로
# ══════════════════════════════════════════════════════════════
q6_title() { echo "[Type 5 · Query] Save filtered Pod lists to files [15 pts]"; }
q6_text() { cat <<'EOF'
Use the Pods in the fleet namespace.

  (a) Write the names of all Pods with the label tier=web
      to /tmp/finaltest/web-pods.txt

  (b) Write the names of all Pods whose phase is NOT Running
      to /tmp/finaltest/not-running.txt

Format for both files: one Pod name per line, sorted by name,
no header, no "pod/" prefix, nothing else.

Verify:
  cat /tmp/finaltest/web-pods.txt
  cat /tmp/finaltest/not-running.txt
EOF
}
q6_title_ko() { echo "[유형⑤ 조회] 조건에 맞는 파드 목록을 파일로 [15점]"; }
q6_text_ko() { cat <<'EOF'
fleet 네임스페이스의 파드를 대상으로 한다.

  (a) 레이블 tier=web 인 파드의 이름을
      /tmp/finaltest/web-pods.txt 에 저장한다

  (b) phase 가 Running 이 아닌 파드의 이름을
      /tmp/finaltest/not-running.txt 에 저장한다

두 파일 모두: 한 줄에 파드 이름 하나, 이름순,
헤더 없이, "pod/" 접두사 없이, 다른 내용 없이.

[확인]
  cat /tmp/finaltest/web-pods.txt
  cat /tmp/finaltest/not-running.txt
EOF
}
q6_hint() { cat <<'EOF'
kubectl -n fleet get pods -l tier=web --no-headers -o custom-columns=:metadata.name \
  > /tmp/finaltest/web-pods.txt

# phase 는 field-selector 로 거른다 (!= 도 된다)
kubectl -n fleet get pods --field-selector=status.phase!=Running \
  --no-headers -o custom-columns=:metadata.name > /tmp/finaltest/not-running.txt

cat /tmp/finaltest/*.txt      # 반드시 열어 보고 넘어간다
EOF
}
_q6_norm() { grep -v '^[[:space:]]*$' "$1" 2>/dev/null | sed 's/[[:space:]]*$//'; }
q6_grade() {
  local want_web want_bad got_web got_bad
  want_web=$(kubectl -n fleet get pods -l tier=web --no-headers -o custom-columns=:metadata.name 2>/dev/null | sort)
  want_bad=$(kubectl -n fleet get pods --field-selector=status.phase!=Running --no-headers -o custom-columns=:metadata.name 2>/dev/null | sort)
  got_web=$(_q6_norm "$WEB_FILE"); got_bad=$(_q6_norm "$BAD_FILE")
  check "$WEB_FILE 이 있다" "test -s $WEB_FILE" 2
  check_result "(a) tier=web 파드 이름이 정확하다" \
    "$([[ -n "$want_web" && "$got_web" == "$want_web" ]] && echo 0 || echo 1)" \
    "기대: $(echo $want_web) / 실제: $(echo $got_web)" 6
  check "$BAD_FILE 이 있다" "test -s $BAD_FILE" 1
  check_result "(b) Running 이 아닌 파드 이름이 정확하다" \
    "$([[ -n "$want_bad" && "$got_bad" == "$want_bad" ]] && echo 0 || echo 1)" \
    "기대: $(echo $want_bad) / 실제: $(echo $got_bad)" 6
}

exam_main "$@"
