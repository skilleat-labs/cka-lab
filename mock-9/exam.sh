#!/usr/bin/env bash
# CKA Mock Exam 9 — 시험 전 마지막 점검 · 자주 나오는 6유형 (100점 · 6문항 · 35분)
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
#
# 목적: 시험 직전에 자신감을 올리는 세트. 출제 유형 문서(CKA_출제유형_문제와풀이_2025-2026)의 풀이를
#       공부했으면 그대로 풀리는 형태로, 이름과 값만 바꿔 냈다. 문서에 없는 함정은 넣지 않았다.
#   Q1 Helm template + CRD 없이 install (7/9) · Q2 HPA (4/9) · Q3 Ingress → Gateway API (7/9)
#   Q4 CRD 목록 · 필드 설명을 파일로 (4/9) · Q5 kubelet 이 멈춘 워커 (5/9) · Q6 NetworkPolicy 고르기 (5/9)
# 인터넷이 필요하다 — Q1 차트·CRD, Q3 Gateway API 컨트롤러(NGINX Gateway Fabric), Q4 cert-manager CRD.
# Q5 는 그 문제에 들어갈 때 워커 노드 하나의 kubelet 을 실제로 멈춘다. clean · 마감 · 다시 start 할 때 되살린다.
# (mock-8 과 같은 방식이다. 다만 mock-8 과 달리 kubelet 설정은 건드리지 않는다 — 멈추고 disable 만 한다)
set -uo pipefail
EXAM_UNIT="점"
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA Mock Exam 9 — 시험 전 마지막 점검 · 자주 나오는 6유형 (100점 · 6문항)"
EXAM_NQ=6
EXAM_LIMIT_MIN="${EXAM_LIMIT_MIN:-35}"   # 제한시간(분) — 0 이면 무제한

NAMESPACES="gitops-tools streaming cafe front-office back-office guest-zone"

# ── Q1: Argo CD 차트 (16-helm · mock-8 과 같은 차트·버전) ──
#   차트 7.7.0 = Argo CD v2.13.0. CRD 를 crds/ 가 아니라 templates/ 에 두고 crds.install 값으로 켜고 끈다.
ARGO_CHART_VER=7.7.0
Q1_REL=argocd
Q1_NS=gitops-tools
Q1_OUT=/tmp/mock9-argocd.yaml
ARGO_CRD_BASE="https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.0/manifests/crds"
ARGO_CRDS=(applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io)
ARGO_MARK="$WORK_DIR/.argocd-crds-by-setup"     # 있으면 setup 이 CRD 를 만든 것 → cleanup 이 지운다
ARGO_REC="$WORK_DIR/.argo-repo-before"          # 시작할 때 argo 저장소가 있었는지

# ── Q3: Gateway API + NGINX Gateway Fabric (08-ingress · mock-7 · mock-8 과 같은 버전·방식) ──
NGF_VERSION="v2.7.0"
GW_CRD_KUSTOMIZE="https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=${NGF_VERSION}"
NGF_CRDS="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/crds.yaml"
NGF_DEPLOY="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/nodeport/deploy.yaml"
MODE_FILE="$WORK_DIR/.gateway-mode"
gw_mode() { cat "$MODE_FILE" 2>/dev/null || echo none; }
Q3_NS=cafe
Q3_HOST=cafe.example.local

# ── Q4: cert-manager CRD 만 (cert-manager 본체는 설치하지 않는다. 16-helm 과 같은 버전) ──
CM_VERSION=v1.16.2
CM_CRDS_URL="https://github.com/cert-manager/cert-manager/releases/download/${CM_VERSION}/cert-manager.crds.yaml"
CM_CRDS=(certificaterequests.cert-manager.io certificates.cert-manager.io challenges.acme.cert-manager.io
         clusterissuers.cert-manager.io issuers.cert-manager.io orders.acme.cert-manager.io)
CM_MARK="$WORK_DIR/.cert-manager-crds-by-setup"
Q4_LIST=/tmp/mock9-crds.txt
Q4_EXPLAIN=/tmp/mock9-privatekey.txt

# ── Q6: 준비된 정책 파일 세 개 중 하나 고르기 ──
Q6_DIR=/tmp/mock9-netpol
Q6_SUM="$WORK_DIR/.q6-files.cksum"

# ══════════════════════════════════════════════════════════════
# Q5 — 워커 노드의 kubelet 을 멈추고 되살리는 도구 (mock-8 과 같다)
#   노드에서 root 로 명령을 돌려야 한다. ① ssh(BatchMode) + sudo -n 이 되면 그것을 쓰고,
#   ② 안 되면 그 노드에 특권 파드(hostPID + nsenter)를 띄워서 돌린다.
#   ②는 kubelet 이 살아 있을 때만 된다 — kubelet 이 죽어 있고 ssh 도 안 되면 손으로 고치는 수밖에 없어 명령을 안내한다.
# ══════════════════════════════════════════════════════════════
Q5_NODE_FILE="$WORK_DIR/.q5-node"        # 멈출 노드 이름 (setup 이 고른다. 비어 있으면 Q5 를 내지 않는다)
Q5_IP_FILE="$WORK_DIR/.q5-ip"
Q5_BROKEN="$WORK_DIR/.q5-broken"         # 있으면 kubelet 을 멈춰 둔 상태 (내용: ssh | pod)
q5_node() { cat "$Q5_NODE_FILE" 2>/dev/null || true; }
q5_ip()   { cat "$Q5_IP_FILE" 2>/dev/null || true; }

node_ip() { kubectl get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null; }
node_is_ready() {
  [[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == "True" ]]
}
wait_node_ready() {   # wait_node_ready <노드> <최대 초>
  local i
  for ((i=0; i<$2; i+=3)); do node_is_ready "$1" && return 0; sleep 3; done
  node_is_ready "$1"
}

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
node_ssh() {   # node_ssh <노드> <원격 명령>   (stdin 을 그대로 넘긴다)
  local ip; ip=$(node_ip "$1"); [[ -z "$ip" ]] && ip=$(q5_ip)
  [[ -z "$ip" ]] && return 255
  ssh "${SSH_OPTS[@]}" ${EXAM_SSH_USER:+-l "$EXAM_SSH_USER"} "$ip" "$2"
}
node_ssh_ok() {   # 비밀번호 없이 ssh 로 들어가 sudo 까지 되는가
  [[ -n "${EXAM_NO_SSH:-}" ]] && return 1       # 시험용: 특권 파드 경로를 강제로 탄다
  command -v ssh &>/dev/null || return 1
  node_ssh "$1" 'sudo -n true' </dev/null &>/dev/null
}
node_run_pod() {  # node_run_pod <노드> [최대 초=90]  < 스크립트   → 스크립트의 출력
  local node="$1" to="${2:-90}" name="mock9-node-helper-${RANDOM}${RANDOM}" b64 ph="" i
  b64=$(base64 | tr -d '\n')
  kubectl apply -f - &>/dev/null <<EOF || return 1
apiVersion: v1
kind: Pod
metadata: { name: ${name}, namespace: kube-system, labels: { app: mock9-node-helper } }
spec:
  nodeName: ${node}
  hostPID: true
  restartPolicy: Never
  terminationGracePeriodSeconds: 0
  tolerations: [ { operator: Exists } ]
  containers:
    - name: sh
      image: busybox:1.36
      securityContext: { privileged: true }
      command: ["sh", "-c", "echo ${b64} | base64 -d | nsenter -t 1 -m -u -i -n -p sh"]
EOF
  for ((i=0; i<to; i+=2)); do
    ph=$(kubectl -n kube-system get pod "$name" -o jsonpath='{.status.phase}' 2>/dev/null)
    [[ "$ph" == "Succeeded" || "$ph" == "Failed" ]] && break
    sleep 2
  done
  kubectl -n kube-system logs "$name" 2>/dev/null
  kubectl -n kube-system delete pod "$name" --force --grace-period=0 &>/dev/null
  [[ "$ph" == "Succeeded" ]]
}
# node_run <노드> [파드 대기 초]  < 스크립트 — 노드에서 root 로 실행하고 출력을 돌려준다. 어느 길로 갔는지는 NODE_VIA_FILE 에 남긴다
NODE_VIA_FILE="$WORK_DIR/.node-via"
node_run() {
  local node="$1" to="${2:-90}" script; script=$(cat)
  if node_ssh_ok "$node"; then
    echo ssh > "$NODE_VIA_FILE"
    node_ssh "$node" 'sudo -n sh -s' <<< "$script" 2>/dev/null
    return $?
  fi
  node_is_ready "$node" || { echo none > "$NODE_VIA_FILE"; return 1; }    # kubelet 이 죽어 있으면 파드를 띄울 수 없다
  echo pod > "$NODE_VIA_FILE"
  node_run_pod "$node" "$to" <<< "$script"
}

# 노드에서 돌리는 스크립트 — POSIX sh (우분투의 /bin/sh 는 dash 다)
#   고장: kubelet 을 disable + stop. 설정 파일은 건드리지 않는다 (enable --now 한 줄이면 고쳐진다).
#        stop 은 12초 뒤에 건다 — 특권 파드로 돌릴 때 파드가 끝났다는 것을 kubelet 이 보고할 시간을 준다.
Q5_BREAK_SH='
systemctl stop mock9-kubelet-stop.timer >/dev/null 2>&1
systemctl reset-failed mock9-kubelet-stop.service >/dev/null 2>&1
systemctl is-active kubelet >/dev/null 2>&1 || { echo "ERR kubelet 이 이미 멈춰 있다"; exit 3; }
if command -v systemd-run >/dev/null 2>&1; then
  systemd-run --unit=mock9-kubelet-stop --on-active=12 systemctl disable --now kubelet >/dev/null 2>&1 || { echo "ERR systemd-run 실패"; exit 4; }
else
  nohup sh -c "sleep 12; systemctl disable --now kubelet" >/dev/null 2>&1 &
fi
echo BROKEN
'
Q5_RESTORE_SH='
systemctl stop mock9-kubelet-stop.timer >/dev/null 2>&1
systemctl reset-failed kubelet >/dev/null 2>&1
systemctl enable --now kubelet >/dev/null 2>&1
sleep 2
echo "state=$(systemctl is-active kubelet 2>/dev/null)"
'
#   pending: kubelet 정지 예약(12초 타이머)이 아직 안 끝났으면 1 이상 — 그동안은 멀쩡해 보여도 고친 것이 아니다
Q5_STATE_SH='echo "active=$(systemctl is-active kubelet 2>/dev/null) enabled=$(systemctl is-enabled kubelet 2>/dev/null) pending=$(systemctl is-active mock9-kubelet-stop.timer mock9-kubelet-stop.service 2>/dev/null | grep -c "^activ")"'

# 멈출 노드를 고른다 — taint 없는 Ready 워커 중 이름순 마지막. 그 노드 말고도 파드를 받을 노드가 하나는 있어야 한다
#   (없으면 그 노드를 멈추는 순간 다른 문제의 파드가 갈 곳이 없다)
pick_q5_node() {
  local jp='{range .items[*]}{.metadata.name}|{.status.conditions[?(@.type=="Ready")].status}|{.spec.taints[*].effect}{"\n"}{end}'
  local tgt other
  tgt=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath="$jp" 2>/dev/null \
        | awk -F'|' '$2=="True" && $3==""{print $1}' | sort | tail -1)
  [[ -z "$tgt" ]] && return 1
  other=$(kubectl get nodes -o jsonpath="$jp" 2>/dev/null \
          | awk -F'|' -v t="$tgt" '$2=="True" && $3=="" && $1!=t{print $1}' | head -1)
  [[ -z "$other" ]] && return 1
  echo "$tgt"
}

# 다른 문제의 파드는 Q5 에서 멈출 노드를 피해서 띄운다 — Q5 를 못 고친 채 넘어가도 Q3 · Q6 채점이 흔들리지 않게.
#   YAML 한 줄(flow)로 만들어 어느 들여쓰기에도 넣을 수 있다. 멈출 노드가 없으면 빈 affinity
AFF='{}'
set_avoid_affinity() {
  local n h; n=$(q5_node)
  [[ -z "$n" ]] && { AFF='{}'; return 0; }
  h=$(kubectl get node "$n" -o jsonpath='{.metadata.labels.kubernetes\.io/hostname}' 2>/dev/null); h="${h:-$n}"
  AFF="{ nodeAffinity: { requiredDuringSchedulingIgnoredDuringExecution: { nodeSelectorTerms: [ { matchExpressions: [ { key: kubernetes.io/hostname, operator: NotIn, values: [ \"$h\" ] } ] } ] } } }"
}

# kubelet 을 되살린다 — 멈춘 적이 있을 때만 건드린다. 여러 번 불려도 된다
q5_restore() {
  [[ -f "$Q5_BROKEN" ]] || return 0
  local n out; n=$(q5_node)
  [[ -z "$n" ]] && { rm -f "$Q5_BROKEN"; return 0; }
  kubectl get node "$n" &>/dev/null || return 0
  out=$(node_run "$n" <<< "$Q5_RESTORE_SH")
  if [[ "$out" == *"state=active"* ]]; then
    rm -f "$Q5_BROKEN"
    echo "  $n kubelet 복구 (enable --now)"
    wait_node_ready "$n" 60 || echo "  $n 이 아직 Ready 가 아닙니다 — kubectl get nodes 로 확인"
  else
    echo -e "  ${ORANGE}[주의] $n 의 kubelet 을 자동으로 되살리지 못했습니다 (ssh 불가 · 노드 NotReady).${RESET}"
    echo "    $n 에 들어가서 아래 한 줄을 실행하세요:"
    echo -e "      ${CYAN}sudo systemctl enable --now kubelet${RESET}"
  fi
}
exam_on_finish() { q5_restore; }

exam_cleanup() {
  local ns own
  q5_restore
  kubectl -n kube-system delete pod -l app=mock9-node-helper --force --grace-period=0 --ignore-not-found &>/dev/null || true
  # Q1 — 릴리스 → 네임스페이스 순서
  if command -v helm &>/dev/null; then
    helm uninstall "$Q1_REL" -n "$Q1_NS" &>/dev/null || true
    if [[ "$(cat "$ARGO_REC" 2>/dev/null)" == "absent" ]]; then
      helm repo remove argo &>/dev/null && echo "  helm 저장소 argo 제거 (시험 중에 추가된 것)"
    fi
  fi
  rm -f "$ARGO_REC"
  rmf "$Q1_OUT" "$Q4_LIST" "$Q4_EXPLAIN" "$Q6_DIR"
  # CRD 는 setup 이 만든 경우, 또는 학생이 crds.install 을 켠 채 설치해 이 릴리스 소유가 된 경우에만 지운다
  own=$(kubectl get crd applications.argoproj.io \
        -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}/{.metadata.annotations.meta\.helm\.sh/release-namespace}' 2>/dev/null)
  if [[ -f "$ARGO_MARK" || "$own" == "$Q1_REL/$Q1_NS" ]]; then
    kubectl delete crd "${ARGO_CRDS[@]}" --ignore-not-found --timeout=60s &>/dev/null &
    rm -f "$ARGO_MARK"
  fi
  if [[ -f "$CM_MARK" ]]; then
    kubectl delete crd "${CM_CRDS[@]}" --ignore-not-found --timeout=60s &>/dev/null &
    rm -f "$CM_MARK"
  fi
  for ns in $NAMESPACES; do
    kubectl get namespace "$ns" &>/dev/null && kubectl delete namespace "$ns" --wait=false &>/dev/null
  done
  rm -f "$MODE_FILE" "$Q6_SUM" "$Q5_NODE_FILE" "$Q5_IP_FILE" "$NODE_VIA_FILE"
  echo "  gitops-tools · streaming · cafe · front-office · back-office · guest-zone 네임스페이스, Helm 릴리스 $Q1_REL"
  echo "  $Q1_OUT · $Q4_LIST · $Q4_EXPLAIN · $Q6_DIR 삭제"
  echo "  (setup 이 만든 Argo CD · cert-manager CRD 만 삭제. Gateway API 컨트롤러는 남겨둠 — 완전 제거: kubectl delete ns nginx-gateway)"
}

setup_gateway_api() {
  # 08-ingress · mock-7 · mock-8 과 같은 절차 — 이미 설치돼 있으면 건너뛴다
  local mode="none"
  if kubectl get gatewayclass nginx &>/dev/null \
     && [[ -n "$(kubectl -n nginx-gateway get deploy -o name 2>/dev/null)" ]] \
     && kubectl -n nginx-gateway wait --for=condition=Available deploy --all --timeout=60s &>/dev/null; then
    echo "  Q3  Gateway API 이미 설치됨 — 건너뜀"; mode="full"
  else
    echo "  Q3  Gateway API CRD 설치 중..."
    if kubectl kustomize "$GW_CRD_KUSTOMIZE" 2>/dev/null | kubectl apply -f - &>/dev/null; then
      mode="crds"
      kubectl apply --server-side -f "$NGF_CRDS" &>/dev/null || true
      kubectl create namespace nginx-gateway &>/dev/null || true
      echo "  Q3  NGINX Gateway Fabric 배포 중 (최대 3분)..."
      if kubectl apply -f "$NGF_DEPLOY" &>/dev/null && \
         kubectl wait --for=condition=Available deployment --all -n nginx-gateway --timeout=180s &>/dev/null; then
        mode="full"; echo "  Q3  NGINX Gateway Fabric 준비 완료 (GatewayClass: nginx)"
      else
        echo "  Q3  컨트롤러가 아직 Ready 되지 않음 — kubectl get pods -n nginx-gateway 로 확인"
      fi
    else
      echo "  Q3  Gateway API CRD 설치 실패 (인터넷 연결 확인)"
    fi
  fi

  # 데이터 플레인을 DaemonSet 으로 (모든 노드의 NodePort 로 접속되도록)
  if [[ "$mode" == "full" ]]; then
    local patch='{"spec":{"kubernetes":{"deployment":null,"daemonSet":{"patches":[{"type":"StrategicMerge","value":{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}]}}}}}]}}}}'
    local pn pns; pn=$(kubectl get gatewayclass nginx -o jsonpath='{.spec.parametersRef.name}' 2>/dev/null); pns=$(kubectl get gatewayclass nginx -o jsonpath='{.spec.parametersRef.namespace}' 2>/dev/null)
    if [[ -n "$pn" && -n "$pns" ]]; then
      kubectl patch nginxproxy "$pn" -n "$pns" --type=merge -p "$patch" &>/dev/null && echo "  Q3  게이트웨이 데이터 플레인 → DaemonSet"
    else
      kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: gateway.nginx.org/v1alpha2
kind: NginxProxy
metadata: { name: exam-proxy-config, namespace: nginx-gateway }
spec:
  kubernetes:
    daemonSet:
      patches:
      - type: StrategicMerge
        value:
          spec:
            template:
              spec:
                tolerations:
                - { key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule }
EOF
      kubectl patch gatewayclass nginx --type=merge -p '{"spec":{"parametersRef":{"group":"gateway.nginx.org","kind":"NginxProxy","name":"exam-proxy-config","namespace":"nginx-gateway"}}}' &>/dev/null && echo "  Q3  게이트웨이 데이터 플레인 → DaemonSet"
    fi
  fi
  echo "$mode" > "$MODE_FILE"
  case "$mode" in
    full) echo "  Q3  → 전부 채점 가능" ;;
    crds) echo -e "  ${ORANGE}Q3  → CRD 만 설치됨. 리소스 작성은 채점되지만 상태·트래픽 3점은 0점 처리${RESET}" ;;
    none) echo -e "  ${RED}Q3  → Gateway API 미설치. 인터넷 연결 후 bash exam.sh start 를 다시${RESET}" ;;
  esac
}

exam_setup() {
  # ── Q5: 멈출 노드를 먼저 고른다 — 다른 문제의 파드가 그 노드를 피해야 하므로
  local n via=""
  rm -f "$Q5_NODE_FILE" "$Q5_IP_FILE"
  if n=$(pick_q5_node); then
    echo "$n" > "$Q5_NODE_FILE"; node_ip "$n" > "$Q5_IP_FILE"
    if node_ssh_ok "$n"; then via="ssh"; else via="특권 파드 (ssh 가 비밀번호 없이 안 된다)"; fi
    echo "  Q5  멈출 노드: $n — 문제에 들어갈 때 kubelet 을 멈춥니다 · 준비 방법: $via"
  else
    echo -e "  ${ORANGE}Q5  이 클러스터에서는 낼 수 없습니다 — taint 없는 Ready 워커 1대 + 파드를 받을 다른 노드 1대가 필요합니다 (통과 처리)${RESET}"
  fi
  set_avoid_affinity

  # ── Q1: argo 저장소 유무 기록 + Argo CD CRD 를 미리 설치 (차트는 CRD 없이 설치하라는 문제)
  if command -v helm &>/dev/null; then
    if helm repo list 2>/dev/null | awk '{print $1}' | grep -qx argo; then echo present > "$ARGO_REC"; else echo absent > "$ARGO_REC"; fi
    echo "  Q1  helm $(helm version --short 2>/dev/null) 확인"
  else
    echo -e "  ${RED}Q1  helm 이 없습니다 — Q1 을 풀 수 없습니다.${RESET} 설치: https://helm.sh/docs/intro/install/"
  fi
  #   ApplicationSet CRD 는 커서 client-side apply 의 annotation 한도(256KiB)를 넘는다 → --server-side
  if kubectl get crd applications.argoproj.io &>/dev/null; then
    echo "  Q1  Argo CD CRD 가 이미 있습니다 — 그대로 씁니다"
  else
    touch "$ARGO_MARK"      # 일부만 만들어져도 cleanup 이 지우도록 먼저 표시
    kubectl apply --server-side \
      -f "$ARGO_CRD_BASE/application-crd.yaml" \
      -f "$ARGO_CRD_BASE/applicationset-crd.yaml" \
      -f "$ARGO_CRD_BASE/appproject-crd.yaml" &>/dev/null \
      && echo "  Q1  Argo CD CRD 3개 설치 (applications · applicationsets · appprojects .argoproj.io)" \
      || echo -e "  ${RED}Q1  Argo CD CRD 설치 실패 (인터넷 연결 확인)${RESET}"
  fi

  # ── Q2: HPA 를 붙일 Deployment (CPU requests 있음)
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: streaming }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: video-api, namespace: streaming, labels: { app: video-api } }
spec:
  replicas: 1
  selector: { matchLabels: { app: video-api } }
  template:
    metadata: { labels: { app: video-api } }
    spec:
      terminationGracePeriodSeconds: 1
      containers:
        - name: api
          image: nginx:1.27
          ports: [ { containerPort: 80 } ]
          resources: { requests: { cpu: 50m, memory: 32Mi } }
YAML
  echo "  Q2  streaming/video-api 배치 (cpu requests 50m)"

  # ── Q3: Gateway API 컨트롤러 + 옮겨야 할 Ingress (host · TLS · 경로)
  setup_gateway_api
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: ${Q3_NS} }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: menu, namespace: ${Q3_NS}, labels: { app: menu } }
spec:
  replicas: 1
  selector: { matchLabels: { app: menu } }
  template:
    metadata: { labels: { app: menu } }
    spec:
      affinity: ${AFF}
      terminationGracePeriodSeconds: 1
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [ { containerPort: 80 } ]
          command: ["sh", "-c", "echo menu-ok > /usr/share/nginx/html/index.html && exec nginx -g 'daemon off;'"]
---
apiVersion: v1
kind: Service
metadata: { name: menu-svc, namespace: ${Q3_NS} }
spec:
  selector: { app: menu }
  ports: [ { name: http, port: 80, targetPort: 80 } ]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: menu-ingress, namespace: ${Q3_NS} }
spec:
  ingressClassName: nginx
  tls:
    - hosts: [ ${Q3_HOST} ]
      secretName: cafe-tls
  rules:
    - host: ${Q3_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: menu-svc, port: { number: 80 } }
YAML
  local d; d=$(mktemp -d)
  if openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
       -keyout "$d/tls.key" -out "$d/tls.crt" \
       -subj "/CN=${Q3_HOST}" -addext "subjectAltName=DNS:${Q3_HOST}" &>/dev/null; then
    kubectl create secret tls cafe-tls -n "$Q3_NS" --cert="$d/tls.crt" --key="$d/tls.key" &>/dev/null
  else
    echo -e "  ${RED}Q3  openssl 로 인증서를 만들지 못했습니다 — Secret cafe-tls 없음${RESET}"
  fi
  rm -rf "$d"
  echo "  Q3  cafe 에 menu(+menu-svc:80) · Secret cafe-tls · Ingress menu-ingress 배치"

  # ── Q4: cert-manager CRD 만 설치 (컨트롤러 없음 → 파드는 생기지 않는다)
  if kubectl get crd certificates.cert-manager.io &>/dev/null; then
    echo "  Q4  cert-manager CRD 가 이미 있습니다 — 그대로 씁니다"
  else
    touch "$CM_MARK"
    kubectl apply -f "$CM_CRDS_URL" &>/dev/null \
      && echo "  Q4  cert-manager ${CM_VERSION} CRD 6개 설치 (CRD 만 — cert-manager 본체는 없음)" \
      || echo -e "  ${RED}Q4  cert-manager CRD 설치 실패 (인터넷 연결 확인)${RESET}"
  fi
  # kubectl explain 은 CRD 가 Established 된 뒤에야 스키마를 보여 준다
  kubectl wait --for=condition=Established crd/certificates.cert-manager.io --timeout=30s &>/dev/null || true

  # ── Q6: 보호할 orders-api 와 접속을 시도할 파드 두 개 + 정책 파일 세 개
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: front-office }
---
apiVersion: v1
kind: Namespace
metadata: { name: back-office }
---
apiVersion: v1
kind: Namespace
metadata: { name: guest-zone }
---
apiVersion: v1
kind: Pod
metadata: { name: orders-api, namespace: back-office, labels: { app: orders-api } }
spec:
  affinity: ${AFF}
  terminationGracePeriodSeconds: 1
  containers: [ { name: nginx, image: "nginx:1.27", ports: [ { containerPort: 80 } ] } ]
---
apiVersion: v1
kind: Service
metadata: { name: orders-api, namespace: back-office }
spec:
  selector: { app: orders-api }
  ports: [ { port: 80, targetPort: 80 } ]
---
apiVersion: v1
kind: Pod
metadata: { name: web, namespace: front-office, labels: { app: web } }
spec:
  affinity: ${AFF}
  terminationGracePeriodSeconds: 1
  containers: [ { name: c, image: "busybox:1.36", command: ["sh", "-c", "sleep 36000"] } ]
---
apiVersion: v1
kind: Pod
metadata: { name: visitor, namespace: guest-zone, labels: { app: visitor } }
spec:
  affinity: ${AFF}
  terminationGracePeriodSeconds: 1
  containers: [ { name: c, image: "busybox:1.36", command: ["sh", "-c", "sleep 36000"] } ]
YAML
  rmf "$Q6_DIR"; mkdir -p "$Q6_DIR"
  # policy-a — 너무 넓다: 출발지는 맞지만 ports 가 없어 모든 포트를 연다
  cat > "$Q6_DIR/policy-a.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: orders-api-policy-a
  namespace: back-office
spec:
  podSelector:
    matchLabels:
      app: orders-api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: front-office
YAML
  # policy-b — 정답: front-office 네임스페이스에서 오는 TCP 80 만
  cat > "$Q6_DIR/policy-b.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: orders-api-policy-b
  namespace: back-office
spec:
  podSelector:
    matchLabels:
      app: orders-api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: front-office
      ports:
        - protocol: TCP
          port: 80
YAML
  # policy-c — 너무 넓다: namespaceSelector: {} = 모든 네임스페이스
  cat > "$Q6_DIR/policy-c.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: orders-api-policy-c
  namespace: back-office
spec:
  podSelector:
    matchLabels:
      app: orders-api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 80
YAML
  ( cd "$Q6_DIR" && cksum policy-a.yaml policy-b.yaml policy-c.yaml ) > "$Q6_SUM" 2>/dev/null
  echo "  Q6  back-office/orders-api(+Service) · front-office/web · guest-zone/visitor 배치, $Q6_DIR 에 policy-a~c.yaml"
  return 0
}

# ══════════════════════════════════════════════════════════════
# Q1 — Helm: 설치하지 않고 뽑기 + CRD 없이 설치
# ══════════════════════════════════════════════════════════════
q1_title() { echo "Helm: render a chart, then install it without its CRDs [15 pts]"; }
q1_text() { cat <<'EOF'
  (a) Add the Helm repository
        name  argo
        URL   https://argoproj.github.io/argo-helm

      Render the chart argo/argo-cd to a file WITHOUT installing it
        chart version   7.7.0
        release name    argocd
        namespace       gitops-tools
        output file     /tmp/mock9-argocd.yaml

      The file must NOT contain any CustomResourceDefinition.

  (b) Install the same chart and version into the gitops-tools namespace
      as the release argocd (create the namespace).
      The CRDs are ALREADY installed in the cluster, so the chart must
      NOT install them.

You do not have to wait for the Argo CD Pods to become Ready.

Verify:
  grep -c 'kind: CustomResourceDefinition' /tmp/mock9-argocd.yaml     -> 0
  helm list -n gitops-tools                                           -> deployed
EOF
}
q1_title_ko() { echo "Helm — 설치하지 않고 뽑기, CRD 없이 설치하기 [15점]"; }
q1_text_ko() { cat <<'EOF'
  (a) Helm 저장소를 추가한다
        이름  argo
        주소  https://argoproj.github.io/argo-helm

      argo/argo-cd 차트를 설치하지 말고 파일로 렌더링한다
        차트 버전     7.7.0
        릴리스 이름   argocd
        네임스페이스  gitops-tools
        저장 경로     /tmp/mock9-argocd.yaml

      파일에 CustomResourceDefinition 이 하나도 없어야 한다.

  (b) 같은 차트 · 같은 버전을 gitops-tools 네임스페이스에
      릴리스 argocd 로 설치한다 (네임스페이스는 만들어서).
      CRD 는 이미 클러스터에 있으므로 차트가 설치하면 안 된다.

Argo CD 파드가 Ready 가 될 때까지 기다릴 필요는 없다.

[확인]
  grep -c 'kind: CustomResourceDefinition' /tmp/mock9-argocd.yaml     → 0
  helm list -n gitops-tools                                           → deployed
EOF
}
q1_hint() { cat <<'EOF'
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update

# CRD 를 끄는 값 이름을 차트에서 찾는다 — --skip-crds 는 차트의 crds/ 폴더만 빼는데,
# 이 차트는 CRD 를 templates/ 에 두고 crds.install 값으로 켜고 끈다
helm show values argo/argo-cd --version 7.7.0 | grep -A3 '^crds:'

# (a) template = 클러스터를 건드리지 않고 YAML 만 출력
helm template argocd argo/argo-cd --version 7.7.0 -n gitops-tools \
  --set crds.install=false > /tmp/mock9-argocd.yaml
grep -c 'kind: CustomResourceDefinition' /tmp/mock9-argocd.yaml     # 0

# (b) install — 같은 옵션. 네임스페이스는 --create-namespace
helm install argocd argo/argo-cd --version 7.7.0 -n gitops-tools --create-namespace \
  --set crds.install=false
EOF
}
q1_grade() {
  # ── (a) 렌더링한 파일
  check "$Q1_OUT 이 있다" "test -s $Q1_OUT" 1
  check_output "(a) 차트 버전 7.7.0 으로 렌더링했다" "grep -m1 'helm.sh/chart: argo-cd-' $Q1_OUT" 'argo-cd-7\.7\.0$' 2
  check_output "(a) 네임스페이스 gitops-tools 로 렌더링했다" "grep -m1 '^  namespace:' $Q1_OUT" 'namespace: gitops-tools$' 1
  check_output "(a) 릴리스 이름 argocd 로 렌더링했다" "grep -m1 'app.kubernetes.io/instance:' $Q1_OUT" 'instance: argocd$' 1
  local n has=1; n=$(grep -c 'kind: CustomResourceDefinition' "$Q1_OUT" 2>/dev/null); n="${n//[^0-9]/}"; n="${n:-0}"
  [[ -s "$Q1_OUT" ]] && has=0
  check_result "(a) 파일에 CustomResourceDefinition 이 0개$([[ $has == 0 ]] && echo " (현재 ${n}개)")" \
    "$([[ $has == 0 && "$n" == "0" ]] && echo 0 || echo 1)" \
    "$([[ $has == 0 ]] && echo '--skip-crds 로 안 빠지면 차트 values 의 crds 설정을 본다' || echo '파일이 없다')" 3

  # ── (b) 설치한 릴리스
  check_output "(b) gitops-tools 에 릴리스 argocd 가 deployed" \
    "helm status $Q1_REL -n $Q1_NS 2>/dev/null" 'STATUS: deployed' 2
  check_output "(b) 차트 버전 argo-cd-7.7.0" \
    "helm list -n $Q1_NS 2>/dev/null | grep -E '^${Q1_REL}[[:space:]]'" 'argo-cd-7\.7\.0' 1
  check_output "(b) crds.install=false 로 설치했다" \
    "helm get values $Q1_REL -n $Q1_NS -o json 2>/dev/null" '"crds":\{[^}]*"install":false' 2
  # 미리 깔아 둔 CRD 가 그대로이고 Helm 릴리스 소유가 아닌지
  local crd owner
  crd=$(kubectl get crd applications.argoproj.io -o name 2>/dev/null)
  owner=$(kubectl get crd applications.argoproj.io -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null)
  local rel=1; helm status "$Q1_REL" -n "$Q1_NS" &>/dev/null && rel=0
  check_result "(b) CRD 는 Helm 릴리스가 관리하지 않는다" \
    "$([[ $rel == 0 && -n "$crd" && -z "$owner" ]] && echo 0 || echo 1)" \
    "$([[ $rel != 0 ]] && echo '릴리스 argocd 가 없다' || { [[ -z "$crd" ]] && echo 'applications.argoproj.io CRD 가 없다 — bash exam.sh start 로 다시 준비' || echo "CRD 가 릴리스 ${owner} 소유다"; })" 1
  check_output "(b) Argo CD server Deployment 가 만들어졌다" \
    "kubectl -n $Q1_NS get deployment -l app.kubernetes.io/name=argocd-server,app.kubernetes.io/instance=$Q1_REL -o name" 'argocd-server' 1
}

# ══════════════════════════════════════════════════════════════
# Q2 — HPA
# ══════════════════════════════════════════════════════════════
q2_title() { echo "HPA for an existing Deployment [15 pts]"; }
q2_text() { cat <<'EOF'
The Deployment video-api runs in the streaming namespace.
Create a HorizontalPodAutoscaler for it.

  name             video-api-scaler
  target           Deployment video-api
  replicas         minimum 1, maximum 5
  metric           average CPU utilization 70%
  scale-down       stabilization window of 60 seconds

Verify:
  kubectl -n streaming get hpa video-api-scaler
  kubectl -n streaming get hpa video-api-scaler -o yaml | grep -A3 behavior
EOF
}
q2_title_ko() { echo "기존 Deployment 에 HPA 붙이기 [15점]"; }
q2_text_ko() { cat <<'EOF'
streaming 네임스페이스에 Deployment video-api 가 돌고 있다.
여기에 HorizontalPodAutoscaler 를 만든다.

  이름            video-api-scaler
  대상            Deployment video-api
  레플리카        최소 1, 최대 5
  기준            CPU 평균 사용률 70%
  스케일 다운     안정화 시간 60초

[확인]
  kubectl -n streaming get hpa video-api-scaler
  kubectl -n streaming get hpa video-api-scaler -o yaml | grep -A3 behavior
EOF
}
q2_hint() { cat <<'EOF'
# 뼈대는 명령으로 — HPA 이름이 Deployment 이름과 다르므로 --name
#   (kubectl 1.34 부터는 --cpu-percent=70 대신 --cpu=70% 를 쓰라는 경고가 나온다. 둘 다 된다)
kubectl -n streaming autoscale deployment video-api --name=video-api-scaler \
  --cpu-percent=70 --min=1 --max=5 --dry-run=client -o yaml > hpa.yaml

# behavior 는 명령 옵션이 없다 → spec 아래에 추가 (apiVersion 이 autoscaling/v2 인지 확인)
#   파일 끝에 붙이면 안 된다 — 맨 아래는 status: 라서 "unknown field status.behavior" 로 거부된다
#   spec:
#     behavior:
#       scaleDown:
#         stabilizationWindowSeconds: 60
kubectl apply -f hpa.yaml

# metrics-server 가 없으면 TARGETS 가 <unknown> 으로 나오지만 채점에는 문제없다
EOF
}
q2_grade() {
  local hpa="kubectl -n streaming get hpa video-api-scaler -o jsonpath"
  check "HPA video-api-scaler 존재" "kubectl -n streaming get hpa video-api-scaler" 3
  check_output "대상이 Deployment video-api" \
    "$hpa='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}'" '^Deployment/video-api$' 3
  check_output "minReplicas 1" "$hpa='{.spec.minReplicas}'" '^1$' 2
  check_output "maxReplicas 5" "$hpa='{.spec.maxReplicas}'" '^5$' 2
  check_output "CPU 평균 사용률 70%" \
    "$hpa='{.spec.metrics[?(@.resource.name==\"cpu\")].resource.target.averageUtilization}'" '^70$' 2
  check_output "scaleDown 안정화 시간 60초" \
    "$hpa='{.spec.behavior.scaleDown.stabilizationWindowSeconds}'" '^60$' 3
}

# ══════════════════════════════════════════════════════════════
# Q3 — Ingress → Gateway API
# ══════════════════════════════════════════════════════════════
q3_title() { echo "Migrate an Ingress to the Gateway API [20 pts]"; }
q3_text() { cat <<'EOF'
In the cafe namespace the Ingress menu-ingress exposes an application over
HTTPS. Migrate it to the Gateway API. A Gateway API controller is installed
and provides the GatewayClass nginx.

Look at the existing Ingress first:
  kubectl -n cafe get ingress menu-ingress -o yaml

  (1) Create a Gateway named cafe-gateway in cafe
        gatewayClassName   nginx
        listener           name https, port 443, protocol HTTPS
        hostname           the same host as the Ingress
        tls                terminate with the TLS Secret the Ingress uses

  (2) Create an HTTPRoute named cafe-route in cafe
        parentRefs         cafe-gateway
        hostnames          the same host as the Ingress
        rule               the same path (PathPrefix), backend Service
                           and port as the Ingress

  (3) Delete the Ingress menu-ingress.
      Keep the Service and the Secret.

Verify:
  kubectl -n cafe get gateway,httproute
  kubectl -n cafe get ingress
EOF
}
q3_title_ko() { echo "Ingress 를 Gateway API 로 옮기기 [20점]"; }
q3_text_ko() { cat <<'EOF'
cafe 네임스페이스의 Ingress menu-ingress 가 애플리케이션을 HTTPS 로
노출하고 있다. 이것을 Gateway API 로 옮긴다. Gateway API 컨트롤러가
설치돼 있고 GatewayClass nginx 를 제공한다.

먼저 기존 Ingress 를 확인한다:
  kubectl -n cafe get ingress menu-ingress -o yaml

  (1) cafe 에 Gateway cafe-gateway 를 만든다
        gatewayClassName   nginx
        리스너             이름 https, 포트 443, 프로토콜 HTTPS
        hostname           Ingress 와 같은 호스트
        tls                Ingress 가 쓰는 TLS Secret 으로 종료(Terminate)

  (2) cafe 에 HTTPRoute cafe-route 를 만든다
        parentRefs         cafe-gateway
        hostnames          Ingress 와 같은 호스트
        규칙               Ingress 와 같은 경로(PathPrefix) · 백엔드 Service · 포트

  (3) Ingress menu-ingress 를 삭제한다.
      Service 와 Secret 은 남겨 둔다.

[확인]
  kubectl -n cafe get gateway,httproute
  kubectl -n cafe get ingress
EOF
}
q3_hint() { cat <<'EOF'
kubectl -n cafe get ingress menu-ingress -o yaml   # host · secretName · path · backend 를 옮겨 적는다

apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: cafe-gateway, namespace: cafe }
spec:
  gatewayClassName: nginx                    # ← ingressClassName
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    hostname: <Ingress 의 host>              # ← tls[].hosts
    tls:
      mode: Terminate
      certificateRefs:
      - { kind: Secret, name: <Ingress 의 secretName> }
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: cafe-route, namespace: cafe }
spec:
  parentRefs: [ { name: cafe-gateway } ]
  hostnames: [ <Ingress 의 host> ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: <Ingress 의 path> } } ]
    backendRefs: [ { name: <Service>, port: <포트> } ]

kubectl -n cafe describe gateway cafe-gateway     # Programmed True 인지
kubectl -n cafe delete ingress menu-ingress
EOF
}
q3_grade() {
  local mode ns="$Q3_NS"; mode=$(gw_mode)
  if [[ "$mode" == "none" ]]; then
    check_result "Gateway API 가 설치되어 있다" 1 "미설치 — 인터넷 연결 후 bash exam.sh start 재실행" 20
    return
  fi
  local GW="kubectl -n $ns get gateway cafe-gateway -o jsonpath"
  local RT="kubectl -n $ns get httproute cafe-route -o jsonpath"
  local L='.spec.listeners[?(@.port==443)]'

  # ── Gateway 스펙 (리스너는 포트 443 으로 찾는다 — 이름이 달라도 나머지를 채점할 수 있게)
  check "Gateway cafe-gateway 존재" "kubectl -n $ns get gateway cafe-gateway" 1
  check_output "gatewayClassName nginx" "$GW='{.spec.gatewayClassName}'" '^nginx$' 1
  check_output "리스너 https · 443 · HTTPS" "$GW='{$L.name}/{$L.protocol}'" '^https/HTTPS$' 2
  check_output "리스너 hostname $Q3_HOST" "$GW='{$L.hostname}'" '^cafe\.example\.local$' 2
  check_output "리스너 TLS 인증서가 Secret cafe-tls" "$GW='{$L.tls.certificateRefs[*].name}'" '(^| )cafe-tls( |$)' 2
  # 비어 있으면(생략) 기본값 Terminate — 단, 443 리스너가 없을 때 빈 출력으로 통과하지 않게 따로 판정
  local tm lp
  lp=$(kubectl -n "$ns" get gateway cafe-gateway -o jsonpath="{$L.port}" 2>/dev/null)
  tm=$(kubectl -n "$ns" get gateway cafe-gateway -o jsonpath="{$L.tls.mode}" 2>/dev/null)
  check_result "TLS 모드 Terminate (생략하면 기본값)" \
    "$([[ "$lp" == "443" && ( -z "$tm" || "$tm" == Terminate ) ]] && echo 0 || echo 1)" \
    "$([[ "$lp" == "443" ]] && echo "tls.mode: $tm" || echo '포트 443 리스너가 없음')" 1

  # ── HTTPRoute 스펙
  check "HTTPRoute cafe-route 존재" "kubectl -n $ns get httproute cafe-route" 1
  check_output "parentRefs 가 cafe-gateway" "$RT='{.spec.parentRefs[*].name}'" '(^| )cafe-gateway( |$)' 1
  check_output "hostnames 에 $Q3_HOST" "$RT='{.spec.hostnames[*]}'" '(^| )cafe\.example\.local( |$)' 1
  check_output "경로 매치 PathPrefix /" \
    "$RT='{range .spec.rules[*].matches[*]}{.path.type}={.path.value}{\" \"}{end}'" '(^| )PathPrefix=/( |$)' 1
  check_output "backendRef menu-svc:80" \
    "$RT='{range .spec.rules[*].backendRefs[*]}{.name}:{.port}{\" \"}{end}'" '(^| )menu-svc:80( |$)' 2

  # ── 정리 — Ingress 는 지우고, Service · Secret 은 남긴다. Gateway 를 만들기 전에 지우기만 해서는 점수가 없다
  local ing gw_ok=1; ing=$(kubectl -n "$ns" get ingress menu-ingress 2>&1)
  kubectl -n "$ns" get gateway cafe-gateway &>/dev/null && gw_ok=0
  check_result "Ingress menu-ingress 삭제됨" \
    "$([[ $gw_ok == 0 && "$ing" == *NotFound* ]] && echo 0 || echo 1)" \
    "$([[ $gw_ok != 0 ]] && echo 'Gateway 를 먼저 만든다' || echo "아직 남아 있다 — kubectl -n $ns delete ingress menu-ingress")" 1
  local keep=1; kubectl -n "$ns" get service menu-svc &>/dev/null && kubectl -n "$ns" get secret cafe-tls &>/dev/null && keep=0
  check_result "Service menu-svc 와 Secret cafe-tls 는 남아 있다" \
    "$([[ $gw_ok == 0 && $keep == 0 ]] && echo 0 || echo 1)" \
    "$([[ $gw_ok != 0 ]] && echo 'Gateway 를 먼저 만든다' || echo 'Service 또는 Secret 이 지워졌다 — bash exam.sh start 로 다시 준비')" 1

  if [[ "$mode" != "full" ]]; then
    check_result "Gateway Programmed · HTTPS 트래픽 (컨트롤러가 없어 확인 불가)" 1 "컨트롤러 설치 후 bash exam.sh start 를 다시" 3
    return
  fi

  # ── 컨트롤러가 받아들였는가 + 실제 HTTPS 트래픽 (Gateway 가 만든 Service 의 443 NodePort 로)
  #   Gateway 를 만든 직후에는 데이터 플레인 파드가 아직 뜨는 중이다 (15~20초).
  #   파드가 하나라도 Ready 가 될 때까지 30초까지 기다리고, 그 뒤 4초 간격으로 세 번까지 요청한다
  local port ip ips hit="" resp try w
  port=$(kubectl -n "$ns" get svc -l gateway.networking.k8s.io/gateway-name=cafe-gateway \
           -o jsonpath='{.items[0].spec.ports[?(@.port==443)].nodePort}' 2>/dev/null)
  port="${port//[^0-9]/}"
  if [[ -n "$port" ]]; then
    for ((w=0; w<30; w+=3)); do
      [[ "$(kubectl -n "$ns" get pods -l gateway.networking.k8s.io/gateway-name=cafe-gateway \
            -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == *True* ]] && break
      sleep 3
    done
  fi
  check_output "Gateway Programmed" "$GW='{.status.conditions[?(@.type==\"Programmed\")].status}'" 'True' 1
  if [[ -n "$port" ]] && command -v curl &>/dev/null; then
    ips=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null)
    for try in 1 2 3; do
      for ip in $ips; do
        resp=$(curl -sk --max-time 4 --resolve "${Q3_HOST}:${port}:${ip}" "https://${Q3_HOST}:${port}/" 2>/dev/null || true)
        [[ "$resp" == *menu-ok* ]] && { hit="$ip"; break 2; }
      done
      (( try < 3 )) && sleep 4
    done
  fi
  check_result "https://$Q3_HOST/ 가 Gateway 를 거쳐 백엔드에 닿는다${hit:+ — $hit:$port}" \
    "$([[ -n "$hit" ]] && echo 0 || echo 1)" \
    "${port:+NodePort $port 응답 없음 — }리스너 hostname · certificateRefs · HTTPRoute hostnames/경로/백엔드 확인" 2
}

# ══════════════════════════════════════════════════════════════
# Q4 — CRD 목록 · 필드 설명을 파일로
# ══════════════════════════════════════════════════════════════
q4_title() { echo "Save a CRD list and a CRD field description to files [15 pts]"; }
q4_text() { cat <<'EOF'
The cert-manager CRDs are installed in the cluster (only the CRDs, not
cert-manager itself).

  (a) Save the list of ALL cert-manager CRDs to
        /tmp/mock9-crds.txt
      using kubectl's default output format (do not use -o).
      The file must not contain any other CRDs.

  (b) Save the documentation of the field spec.privateKey of the
      cert-manager Certificate resource to
        /tmp/mock9-privatekey.txt
      using kubectl.

Verify:
  cat /tmp/mock9-crds.txt
  head /tmp/mock9-privatekey.txt
EOF
}
q4_title_ko() { echo "CRD 목록과 필드 설명을 파일로 저장 [15점]"; }
q4_text_ko() { cat <<'EOF'
클러스터에 cert-manager 의 CRD 가 설치돼 있다 (CRD 만 — cert-manager 본체는 없다).

  (a) cert-manager 의 CRD 목록 전부를
        /tmp/mock9-crds.txt
      에 kubectl 의 기본 출력 형식으로 저장한다 (-o 를 쓰지 않는다).
      다른 CRD 가 섞이면 안 된다.

  (b) cert-manager 의 Certificate 리소스에서 spec.privateKey 필드의 설명을
        /tmp/mock9-privatekey.txt
      에 kubectl 로 뽑아 저장한다.

[확인]
  cat /tmp/mock9-crds.txt
  head /tmp/mock9-privatekey.txt
EOF
}
q4_hint() { cat <<'EOF'
# (a) '기본 출력 형식' = -o 없이 나오는 표. grep 으로 cert-manager 만 거른다
kubectl get crd | grep cert-manager > /tmp/mock9-crds.txt
cat /tmp/mock9-crds.txt

# (b) kubectl explain 은 CRD 의 스키마도 설명해 준다
kubectl api-resources --api-group=cert-manager.io        # 리소스 이름 확인
kubectl explain certificate.spec.privateKey > /tmp/mock9-privatekey.txt
head /tmp/mock9-privatekey.txt
EOF
}
q4_grade() {
  # (a) CRD 목록 — 이름이 다 있고, 기본 형식(NAME  CREATED AT)이고, 다른 CRD 가 없어야 한다
  check "$Q4_LIST 이 있다" "test -s $Q4_LIST" 1
  local want got ts other has=1
  [[ -s "$Q4_LIST" ]] && has=0
  want=$(kubectl get crd -o name 2>/dev/null | grep -c 'cert-manager\.io$'); want="${want//[^0-9]/}"; want="${want:-0}"
  got=$(grep -oE '^[a-z0-9.-]+\.cert-manager\.io' "$Q4_LIST" 2>/dev/null | sort -u | wc -l); got="${got//[^0-9]/}"; got="${got:-0}"
  ts=$(grep -cE '^[a-z0-9.-]+\.cert-manager\.io[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$Q4_LIST" 2>/dev/null); ts="${ts//[^0-9]/}"; ts="${ts:-0}"
  other=$(grep -vE '^NAME[[:space:]]|^[[:space:]]*$|cert-manager\.io' "$Q4_LIST" 2>/dev/null | wc -l); other="${other//[^0-9]/}"; other="${other:-0}"
  check_result "(a) cert-manager CRD 가 모두 들어 있다 (${got}/${want})" \
    "$([[ $has == 0 && "$want" -gt 0 && "$got" == "$want" ]] && echo 0 || echo 1)" \
    "$([[ "$want" == "0" ]] && echo '클러스터에 cert-manager CRD 가 없다 — bash exam.sh start 로 다시 준비' || echo 'kubectl get crd | grep cert-manager')" 4
  check_result "(a) 기본 출력 형식이다 (NAME · CREATED AT)" \
    "$([[ $has == 0 && "$want" -gt 0 && "$ts" == "$want" ]] && echo 0 || echo 1)" "-o name / -o yaml 이 아니라 그냥 kubectl get crd 의 줄이어야 한다" 2
  check_result "(a) 다른 CRD 가 섞이지 않았다" \
    "$([[ $has == 0 && "$got" -gt 0 && "$other" == "0" ]] && echo 0 || echo 1)" \
    "$([[ $has == 0 && "$got" -gt 0 ]] && echo "cert-manager 가 아닌 줄 ${other}개 — grep 으로 거른다" || echo 'cert-manager CRD 줄이 없다')" 2

  # (b) kubectl explain 결과
  check "$Q4_EXPLAIN 이 있다" "test -s $Q4_EXPLAIN" 1
  check_output "(b) Certificate 리소스의 설명이다" "cat $Q4_EXPLAIN 2>/dev/null" '^KIND:[[:space:]]+Certificate$' 2
  check_output "(b) spec.privateKey 필드의 설명이다" "cat $Q4_EXPLAIN 2>/dev/null" '^(FIELD|RESOURCE):[[:space:]]+privateKey' 2
  check_output "(b) privateKey 의 하위 필드가 보인다 (rotationPolicy 등)" "cat $Q4_EXPLAIN 2>/dev/null" 'rotationPolicy' 1
}

# ══════════════════════════════════════════════════════════════
# Q5 — kubelet 이 멈춘 워커 노드
# ══════════════════════════════════════════════════════════════
# 문제에 처음 들어갈 때 한 번 — 시작부터 멈추면 Q1~Q4 동안 노드가 하나 빠진 채로 풀게 된다
q5_enter() {
  local n out via; n=$(q5_node)
  [[ -z "$n" ]] && return 0
  [[ -f "$Q5_BROKEN" ]] && return 0
  kubectl get node "$n" &>/dev/null || return 0
  out=$(node_run "$n" <<< "$Q5_BREAK_SH")
  via=$(cat "$NODE_VIA_FILE" 2>/dev/null)
  if [[ "$out" == *BROKEN* ]]; then
    echo "$via" > "$Q5_BROKEN"
    echo "  $n 의 kubelet 을 멈췄습니다 ($via) — 1분 안에 NotReady 가 됩니다"
  else
    # 실패를 엔진에 알린다 → 들어간 것으로 치지 않고 다음 show 때 다시 시도한다
    echo "Q5: $n 의 kubelet 을 멈추지 못했습니다 (${via:-방법 없음}) ${out:+— $out}" >> "$_GUARD_ERR"
  fi
}
q5_title() { echo "Repair a worker node that is NotReady [15 pts]"; }
q5_text() {
  local n ip; n=$(q5_node); ip=$(q5_ip)
  if [[ -z "$n" ]]; then cat <<'EOF'
This question needs a worker node that can be stopped while another node
keeps running the workloads. This cluster does not have one, so the question
is skipped and counted as passed.

Run:  bash exam.sh check
EOF
    return
  fi
  cat <<EOF
The node ${n} is NotReady (or will be, within a minute).

Find the cause and fix it. The fix must survive a reboot of the node.

Connect to the node:
  ssh ${n}          (or: ssh ${ip})
  sudo -i

Verify (back on the control plane):
  kubectl get nodes          -> ${n} is Ready
EOF
}
q5_title_ko() { echo "NotReady 워커 노드 복구 — kubelet [15점]"; }
q5_text_ko() {
  local n ip; n=$(q5_node); ip=$(q5_ip)
  if [[ -z "$n" ]]; then cat <<'EOF'
이 문제는 다른 노드가 워크로드를 맡는 동안 멈출 수 있는 워커 노드가 필요하다.
이 클러스터에는 그런 노드가 없어서 문제를 내지 않고 통과로 처리한다.

실행:  bash exam.sh check
EOF
    return
  fi
  cat <<EOF
노드 ${n} 이 NotReady 다 (지금 아니라면 1분 안에 NotReady 가 된다).

원인을 찾아 고친다. 노드를 재부팅한 뒤에도 유지돼야 한다.

노드 접속:
  ssh ${n}          (또는: ssh ${ip})
  sudo -i

[확인] (컨트롤플레인으로 돌아와서)
  kubectl get nodes          → ${n} 이 Ready
EOF
}
q5_hint() { cat <<'EOF'
systemctl status kubelet --no-pager      # Loaded 줄의 enabled/disabled · Active 상태
#   inactive (dead) · disabled        → 멈춰 있고, 재부팅해도 안 뜬다

systemctl enable --now kubelet           # 지금 시작 + 재부팅 후 자동 시작
#   start 만 하면 재부팅 뒤 다시 멈춘다

exit; exit                               # 컨트롤플레인으로 돌아와서
kubectl get nodes
EOF
}
q5_grade() {
  local n; n=$(q5_node)
  if [[ -z "$n" ]]; then
    check_result "멈출 수 있는 워커 노드가 없는 클러스터 — 통과 처리" 0 "" 15; return
  fi
  if [[ ! -f "$Q5_BROKEN" ]]; then
    # kubelet 을 멈춘 적이 없으면 건강한 노드를 보고 통과시키면 안 된다
    check_result "$n NotReady 복구" 1 "kubelet 이 아직 멈추지 않았다 — bash exam.sh show 로 문제 환경을 다시 준비" 15; return
  fi
  # kubelet 상태는 노드 안에서 본다 (ssh, 안 되면 특권 파드 — 파드는 kubelet 이 살아 있어야 뜬다)
  #   Ready 만 보면 안 된다: kubelet 이 멈춘 뒤에도 40~50초는 Ready 로 남고, 문제에 들어온 직후 12초는 아직 멈추기 전이다.
  #   그래서 "kubelet 이 active 이고 정지 예약이 끝난 뒤" 일 때만 Ready 를 인정한다
  local st act en pend rdy=1
  st=$(node_run "$n" 24 <<< "$Q5_STATE_SH")
  act=$(grep -oE 'active=[a-z-]+' <<< "$st" | cut -d= -f2); en=$(grep -oE 'enabled=[a-z-]+' <<< "$st" | cut -d= -f2)
  pend=$(grep -oE 'pending=[0-9]+' <<< "$st" | cut -d= -f2)
  if [[ -n "$pend" && "$pend" != "0" ]]; then
    check_result "$n NotReady 복구" 1 "kubelet 이 아직 멈추기 전이다 — 문제를 푼 뒤 다시 채점" 15; return
  fi
  if [[ "$act" == "active" ]]; then wait_node_ready "$n" 30 && rdy=0; fi
  local why="노드 안을 확인하지 못했다 — kubelet 이 떠야 확인할 수 있다 (고친 뒤 다시 채점)"
  check_result "$n 이 Ready 이고 kubelet 이 실행 중 (is-active: ${act:-확인 불가})" \
    "$([[ $rdy == 0 ]] && echo 0 || echo 1)" \
    "$([[ -z "$act" ]] && echo "$why" || { [[ "$act" == "active" ]] && echo 'kubelet 은 떴는데 노드가 아직 Ready 가 아니다 — 잠시 뒤 다시 채점' || echo 'systemctl status kubelet'; })" 10
  check_result "kubelet 이 enabled — 재부팅 후 자동 시작 (is-enabled: ${en:-확인 불가})" \
    "$([[ "$en" == "enabled" ]] && echo 0 || echo 1)" "$([[ -z "$en" ]] && echo "$why" || echo "start 만 하면 재부팅 뒤 다시 멈춘다 — systemctl enable kubelet")" 5
}

# ══════════════════════════════════════════════════════════════
# Q6 — NetworkPolicy 고르기
# ══════════════════════════════════════════════════════════════
q6_title() { echo "NetworkPolicy: apply the least permissive of three [20 pts]"; }
q6_text() { cat <<'EOF'
In the back-office namespace the Pod orders-api (label app=orders-api) is
exposed by the Service orders-api on port 80.

Requirement:
  Only Pods in the front-office namespace may reach orders-api,
  and only on TCP port 80.

Three candidate manifests are prepared:

  /tmp/mock9-netpol/policy-a.yaml
  /tmp/mock9-netpol/policy-b.yaml
  /tmp/mock9-netpol/policy-c.yaml

Apply exactly ONE of them - the least permissive one that meets the
requirement. Do not edit the files and do not create any other NetworkPolicy.

Test Pods already exist:
  front-office/web     -> must reach orders-api
  guest-zone/visitor   -> must be blocked

Verify:
  kubectl -n front-office exec web     -- wget -qO- -T 3 http://orders-api.back-office
  kubectl -n guest-zone   exec visitor -- wget -qO- -T 3 http://orders-api.back-office
EOF
}
q6_title_ko() { echo "NetworkPolicy — 세 개 중 최소 권한인 것 하나 적용 [20점]"; }
q6_text_ko() { cat <<'EOF'
back-office 네임스페이스의 파드 orders-api(레이블 app=orders-api)는
Service orders-api 의 80 포트로 노출돼 있다.

요구 사항:
  front-office 네임스페이스의 파드만 orders-api 에 접근할 수 있고,
  그것도 TCP 80 포트로만 가능해야 한다.

후보 매니페스트 세 개가 준비돼 있다.

  /tmp/mock9-netpol/policy-a.yaml
  /tmp/mock9-netpol/policy-b.yaml
  /tmp/mock9-netpol/policy-c.yaml

이 중 정확히 하나만 적용한다 — 요구 사항을 만족하는 것 중 최소 권한인 것.
파일을 고치지 말고, 다른 NetworkPolicy 를 따로 만들지도 않는다.

테스트 파드가 이미 있다.
  front-office/web     → orders-api 에 닿아야 한다
  guest-zone/visitor   → 막혀야 한다

[확인]
  kubectl -n front-office exec web     -- wget -qO- -T 3 http://orders-api.back-office
  kubectl -n guest-zone   exec visitor -- wget -qO- -T 3 http://orders-api.back-office
EOF
}
q6_hint() { cat <<'EOF'
# 1) 실제 레이블부터 본다 — 정책은 레이블로 고른다
kubectl get ns front-office back-office --show-labels
kubectl -n back-office get pods --show-labels

# 2) 세 파일을 나란히 본다 — 대상(podSelector) · 출발지(from) · 포트(ports)
cat /tmp/mock9-netpol/policy-*.yaml

# 3) 조건보다 넓은 것을 지운다
#    namespaceSelector: {}   → 모든 네임스페이스
#    ports 가 없다           → 모든 포트

# 4) 하나만 적용. 잘못 적용했으면 kubectl -n back-office delete networkpolicy <이름>
EOF
}
q6_grade() {
  local P=back-office
  check "정답 정책 orders-api-policy-b 가 적용됐다" "kubectl -n $P get networkpolicy orders-api-policy-b" 6
  local names n other=""
  names=$(kubectl -n "$P" get networkpolicy -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  n=$(wc -w <<< "$names"); n="${n//[^0-9]/}"
  # 어느 것이 왜 틀렸는지는 알려 주지 않는다 — 고르는 것이 문제다
  [[ " $names " == *" orders-api-policy-a "* ]] && other+="policy-a "
  [[ " $names " == *" orders-api-policy-c "* ]] && other+="policy-c "
  # 아무것도 적용하지 않은 상태에서 점수가 새지 않게, 정책이 하나라도 있을 때만 통과
  check_result "다른 후보(policy-a · policy-c)는 적용하지 않았다" \
    "$([[ "${n:-0}" -ge 1 && -z "$other" ]] && echo 0 || echo 1)" \
    "$([[ "${n:-0}" -lt 1 ]] && echo '적용된 정책이 없다' || echo "적용돼 있음: ${other}— kubectl delete 로 지운다")" 3
  check_result "back-office 의 NetworkPolicy 가 정답 하나뿐이다" \
    "$([[ "$names" == "orders-api-policy-b" ]] && echo 0 || echo 1)" "현재 ${n:-0}개: ${names:-없음}" 3
  check_result "준비된 파일을 고치지 않았다" \
    "$([[ "${n:-0}" -ge 1 && -s "$Q6_SUM" ]] && ( cd "$Q6_DIR" 2>/dev/null && cksum policy-a.yaml policy-b.yaml policy-c.yaml 2>/dev/null ) | diff -q - "$Q6_SUM" &>/dev/null && echo 0 || echo 1)" \
    "$([[ "${n:-0}" -lt 1 ]] && echo '적용된 정책이 없다' || echo "$Q6_DIR 의 파일이 바뀌었거나 없다 — bash exam.sh start 로 다시 준비")" 2

  # 실제 연결 — 허용 경로가 살아 있고 정책이 걸려 있을 때만 '막힘' 을 믿는다
  wait_ready orders-api "$P" || true
  local probe='wget -qO- -T 3 http://orders-api.back-office.svc.cluster.local 2>/dev/null' a b served=1
  a=$(kubectl -n front-office exec web     -- sh -c "$probe" 2>/dev/null)
  b=$(kubectl -n guest-zone   exec visitor -- sh -c "$probe" 2>/dev/null)
  grep -qi nginx <<< "$a" && served=0
  check_result "front-office/web → orders-api:80 응답 (허용)" \
    "$([[ "${n:-0}" -ge 1 && $served == 0 ]] && echo 0 || echo 1)" \
    "$([[ "${n:-0}" -lt 1 ]] && echo '적용된 정책이 없다' || echo '응답 없음 — 적용한 정책이 front-office 를 실제로 고르는지 확인')" 3
  check_result "guest-zone/visitor → orders-api 차단" \
    "$([[ "${n:-0}" -ge 1 && $served == 0 ]] && ! grep -qi nginx <<< "$b" && echo 0 || echo 1)" \
    "$([[ "${n:-0}" -lt 1 ]] && echo '적용된 정책이 없다' || { [[ $served != 0 ]] && echo '허용 경로부터 확인' || echo 'visitor 가 닿는다 — 요구보다 넓게 여는 정책이다'; })" 3
}

exam_main "$@"
