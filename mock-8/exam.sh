#!/usr/bin/env bash
# CKA Mock Exam 8 — 후기 상위 7유형 40분 점검 (100점 · 7문항)
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
#
# 목적: 2025–2026 합격 후기 9건에서 많이 언급된 유형 중, 한 클러스터에서 40분 안에 풀 수 있는 7개를 모았다.
#   Q1 Helm template + CRD 없이 설치 (7/9) · Q2 HPA (4/9) · Q3 Ingress → Gateway API (7/9)
#   Q4 기본 StorageClass (4/9) · Q5 kubelet 이 멈춘 워커 (5/9) · Q6 NetworkPolicy 고르기 (5/9)
#   Q7 PriorityClass (3/9)
# 뺀 유형: CNI 설치 · 컨트롤플레인 고장 · cri-dockerd · etcd 복원 — 오래 걸리거나 클러스터를 통째로 쓴다.
# 인터넷이 필요하다 — Q1 차트·CRD, Q3 Gateway API 컨트롤러(NGINX Gateway Fabric).
# Q5 는 그 문제에 들어갈 때 워커 노드 하나의 kubelet 을 실제로 멈춘다. clean · 마감 · 다시 start 할 때 되살린다.
set -uo pipefail
EXAM_UNIT="점"
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA Mock Exam 8 — 후기 상위 7유형 40분 점검 (100점 · 7문항)"
EXAM_NQ=7
EXAM_LIMIT_MIN="${EXAM_LIMIT_MIN:-40}"   # 제한시간(분) — 0 이면 무제한

NAMESPACES="cd-system checkout bookstore shopfront stockroom telemetry"

# ── Q1: Argo CD 차트 (16-helm 과 같은 차트·버전, 다른 릴리스 이름·네임스페이스) ──
#   차트 7.7.0 = Argo CD v2.13.0. CRD 를 crds/ 가 아니라 templates/ 에 두고 crds.install 값으로 켜고 끈다.
ARGO_CHART_VER=7.7.0
Q1_REL=cd-main
Q1_NS=cd-system
Q1_OUT=/tmp/mock8-argocd.yaml
ARGO_CRD_BASE="https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.0/manifests/crds"
ARGO_CRDS=(applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io)
ARGO_MARK="$WORK_DIR/.argocd-crds-by-setup"     # 있으면 setup 이 CRD 를 만든 것 → cleanup 이 지운다
ARGO_REC="$WORK_DIR/.argo-repo-before"          # 시작할 때 argo 저장소가 있었는지

# ── Q3: Gateway API + NGINX Gateway Fabric (08-ingress · mock-7 과 같은 버전·방식) ──
NGF_VERSION="v2.7.0"
GW_CRD_KUSTOMIZE="https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=${NGF_VERSION}"
NGF_CRDS="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/crds.yaml"
NGF_DEPLOY="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/nodeport/deploy.yaml"
MODE_FILE="$WORK_DIR/.gateway-mode"
gw_mode() { cat "$MODE_FILE" 2>/dev/null || echo none; }
Q3_NS=bookstore
Q3_HOST=books.example.local

# ── Q4: 시험 전에 클러스터에 원래 있던 기본 StorageClass (cleanup 이 되돌린다. mock-6 과 같은 방식) ──
SC_REC="$WORK_DIR/.sc-default-before"
sc_defaults() {
  kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}={.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null \
    | grep '=true$' | cut -d= -f1
}

# ── Q6: 준비된 정책 파일 세 개 중 하나 고르기 ──
Q6_DIR=/tmp/mock8-netpol
Q6_SUM="$WORK_DIR/.q6-files.cksum"

# "지우고 다시 만들기" 를 잡으려고 start 때 uid 를 적어 둔다
save_uid() {   # save_uid <표식> <kubectl get 인자...>
  local key="$1"; shift
  kubectl get "$@" -o jsonpath='{.metadata.uid}' > "$WORK_DIR/.uid-$key" 2>/dev/null || true
}
same_uid() {
  local key="$1" want now; shift
  want=$(cat "$WORK_DIR/.uid-$key" 2>/dev/null)
  now=$(kubectl get "$@" -o jsonpath='{.metadata.uid}' 2>/dev/null)
  [[ -n "$want" && "$want" == "$now" ]]
}

# ══════════════════════════════════════════════════════════════
# Q5 — 워커 노드의 kubelet 을 멈추고 되살리는 도구
#   노드에서 root 로 명령을 돌려야 한다. ① ssh(BatchMode) + sudo -n 이 되면 그것을 쓰고,
#   ② 안 되면 그 노드에 특권 파드(hostPID + nsenter)를 띄워서 돌린다.
#   ②는 kubelet 이 살아 있을 때만 된다 — kubelet 이 죽어 있고 ssh 도 안 되면 손으로 고치는 수밖에 없어 명령을 안내한다.
# ══════════════════════════════════════════════════════════════
Q5_NODE_FILE="$WORK_DIR/.q5-node"        # 멈출 노드 이름 (setup 이 고른다. 비어 있으면 Q5 를 내지 않는다)
Q5_IP_FILE="$WORK_DIR/.q5-ip"
Q5_BROKEN="$WORK_DIR/.q5-broken"         # 있으면 kubelet 을 멈춰 둔 상태 (내용: ssh | pod)
Q5_DROPIN=/etc/systemd/system/kubelet.service.d/20-override.conf
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
  local node="$1" to="${2:-90}" name="mock8-node-helper-${RANDOM}${RANDOM}" b64 ph="" i
  b64=$(base64 | tr -d '\n')
  kubectl apply -f - &>/dev/null <<EOF || return 1
apiVersion: v1
kind: Pod
metadata: { name: ${name}, namespace: kube-system, labels: { app: mock8-node-helper } }
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
#   고장: ① 지금 쓰는 ExecStart 를 읽어 실행 파일 경로만 없는 경로로 바꾼 드롭인을 얹고 ② kubelet 을 disable + stop.
#        배포판마다 kubelet 위치·인자가 달라서(우분투 /usr/bin/kubelet, minikube /var/lib/minikube/binaries/...) 줄을 읽어서 만든다.
#        stop 은 12초 뒤에 건다 — 특권 파드로 돌릴 때 파드가 끝났다는 것을 kubelet 이 보고할 시간을 준다.
Q5_BREAK_SH='
D=/etc/systemd/system/kubelet.service.d; F=$D/20-override.conf
systemctl stop mock8-kubelet-stop.timer >/dev/null 2>&1
systemctl reset-failed mock8-kubelet-stop.service >/dev/null 2>&1
rm -f "$F"; systemctl daemon-reload
line=$(systemctl cat kubelet 2>/dev/null | grep -E "^ExecStart=." | tail -1)
case "$line" in *\\) echo "ERR ExecStart 가 여러 줄이다"; exit 3;; esac
cmd=${line#ExecStart=}; bin=${cmd%% *}
[ -x "$bin" ] || { echo "ERR kubelet 실행 파일을 못 찾음: $bin"; exit 3; }
rest=${cmd#"$bin"}
w=""
for c in /usr/local/bin/kubelet /usr/local/sbin/kubelet /opt/bin/kubelet; do
  [ "$c" != "$bin" ] && [ ! -e "$c" ] && { w=$c; break; }
done
[ -n "$w" ] || { echo "ERR 비어 있는 경로가 없다"; exit 3; }
mkdir -p "$D"
printf "[Service]\nExecStart=\nExecStart=%s%s\n" "$w" "$rest" > "$F"
systemctl daemon-reload
if command -v systemd-run >/dev/null 2>&1; then
  systemd-run --unit=mock8-kubelet-stop --on-active=12 systemctl disable --now kubelet >/dev/null 2>&1 || { rm -f "$F"; systemctl daemon-reload; echo "ERR systemd-run 실패"; exit 4; }
else
  nohup sh -c "sleep 12; systemctl disable --now kubelet" >/dev/null 2>&1 &
fi
echo BROKEN
'
Q5_RESTORE_SH='
systemctl stop mock8-kubelet-stop.timer >/dev/null 2>&1
rm -f /etc/systemd/system/kubelet.service.d/20-override.conf
systemctl daemon-reload
systemctl reset-failed kubelet >/dev/null 2>&1
systemctl enable --now kubelet >/dev/null 2>&1
sleep 2
echo "state=$(systemctl is-active kubelet 2>/dev/null)"
'
#   pending: kubelet 정지 예약(12초 타이머)이 아직 안 끝났으면 1 이상 — 그동안은 멀쩡해 보여도 고친 것이 아니다
Q5_STATE_SH='echo "active=$(systemctl is-active kubelet 2>/dev/null) enabled=$(systemctl is-enabled kubelet 2>/dev/null) pending=$(systemctl is-active mock8-kubelet-stop.timer mock8-kubelet-stop.service 2>/dev/null | grep -c "^activ")"'

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

# 다른 문제의 파드는 Q5 에서 멈출 노드를 피해서 띄운다 — Q5 를 못 고친 채 넘어가도 Q3 · Q6 · Q7 채점이 흔들리지 않게.
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
    echo "  $n kubelet 복구 (드롭인 제거 · enable --now)"
    wait_node_ready "$n" 60 || echo "  $n 이 아직 Ready 가 아닙니다 — kubectl get nodes 로 확인"
  else
    echo -e "  ${ORANGE}[주의] $n 의 kubelet 을 자동으로 되살리지 못했습니다 (ssh 불가 · 노드 NotReady).${RESET}"
    echo "    $n 에 들어가서 아래 세 줄을 실행하세요:"
    echo -e "      ${CYAN}sudo rm -f $Q5_DROPIN${RESET}"
    echo -e "      ${CYAN}sudo systemctl daemon-reload${RESET}"
    echo -e "      ${CYAN}sudo systemctl enable --now kubelet${RESET}"
  fi
}
exam_on_finish() { q5_restore; }

exam_cleanup() {
  local ns sc restored="" crd own
  q5_restore
  kubectl -n kube-system delete pod -l app=mock8-node-helper --force --grace-period=0 --ignore-not-found &>/dev/null || true
  # Q1 — 릴리스 → 네임스페이스 순서. 차트가 만든 클러스터 범위 리소스는 uninstall 이 지운다
  if command -v helm &>/dev/null; then
    helm uninstall "$Q1_REL" -n "$Q1_NS" &>/dev/null || true
    if [[ "$(cat "$ARGO_REC" 2>/dev/null)" == "absent" ]]; then
      helm repo remove argo &>/dev/null && echo "  helm 저장소 argo 제거 (시험 중에 추가된 것)"
    fi
  fi
  rm -f "$ARGO_REC"
  rmf "$Q1_OUT" "$Q6_DIR"
  # CRD 는 setup 이 만든 경우, 또는 학생이 crds.install 을 켠 채 설치해 이 릴리스 소유가 된 경우에만 지운다
  #   (원래 있던 Argo CD 는 건드리지 않는다. 릴리스 소유로 남으면 다음 시도에서 "Helm 이 관리하지 않는다" 가 틀린다)
  own=$(kubectl get crd applications.argoproj.io \
        -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}/{.metadata.annotations.meta\.helm\.sh/release-namespace}' 2>/dev/null)
  if [[ -f "$ARGO_MARK" || "$own" == "$Q1_REL/$Q1_NS" ]]; then
    kubectl delete crd "${ARGO_CRDS[@]}" --ignore-not-found --timeout=60s &>/dev/null &
    rm -f "$ARGO_MARK"
  fi
  for ns in $NAMESPACES; do
    kubectl get namespace "$ns" &>/dev/null && kubectl delete namespace "$ns" --wait=false &>/dev/null
  done
  kdel priorityclass tier-critical tier-standard tier-batch relay-priority
  kdel storageclass bulk-hdd fast-nvme
  # Q4 — 학생이 해제한 '원래 기본 StorageClass' 를 되돌린다 (시작 때 적어 둔 것만)
  if [[ -f "$SC_REC" ]]; then
    while IFS= read -r sc; do
      [[ -z "$sc" ]] && continue
      kubectl annotate storageclass "$sc" storageclass.kubernetes.io/is-default-class=true --overwrite &>/dev/null \
        && restored+="$sc "
    done < "$SC_REC"
    rm -f "$SC_REC"
  fi
  [[ -n "$restored" ]] && echo "  원래 기본 StorageClass 복구: $restored"
  rm -f "$MODE_FILE" "$Q6_SUM" "$Q5_NODE_FILE" "$Q5_IP_FILE" "$NODE_VIA_FILE" "$WORK_DIR"/.uid-*
  echo "  cd-system · checkout · bookstore · shopfront · stockroom · telemetry 네임스페이스, Helm 릴리스 $Q1_REL"
  echo "  PriorityClass tier-* · relay-priority / StorageClass bulk-hdd · fast-nvme / $Q1_OUT · $Q6_DIR 삭제"
  echo "  (Gateway API 컨트롤러는 남겨둠 — 완전 제거: kubectl delete ns nginx-gateway)"
}

setup_gateway_api() {
  # 08-ingress · mock-7 과 같은 절차 — 이미 설치돼 있으면 건너뛴다
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
metadata: { name: checkout }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: cart-api, namespace: checkout, labels: { app: cart-api } }
spec:
  replicas: 2
  selector: { matchLabels: { app: cart-api } }
  template:
    metadata: { labels: { app: cart-api } }
    spec:
      terminationGracePeriodSeconds: 1
      containers:
        - name: api
          image: nginx:1.27
          ports: [ { containerPort: 80 } ]
          resources: { requests: { cpu: 50m, memory: 32Mi } }
YAML
  save_uid checkout-cart-api -n checkout deployment cart-api
  echo "  Q2  checkout/cart-api 배치 (replicas 2 · cpu requests 50m)"

  # ── Q3: Gateway API 컨트롤러 + 옮겨야 할 Ingress (host · TLS · 경로)
  setup_gateway_api
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: ${Q3_NS} }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: catalog, namespace: ${Q3_NS}, labels: { app: catalog } }
spec:
  replicas: 1
  selector: { matchLabels: { app: catalog } }
  template:
    metadata: { labels: { app: catalog } }
    spec:
      affinity: ${AFF}
      terminationGracePeriodSeconds: 1
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [ { containerPort: 80 } ]
          command: ["sh", "-c", "mkdir -p /usr/share/nginx/html/catalog && echo catalog-ok > /usr/share/nginx/html/catalog/index.html && exec nginx -g 'daemon off;'"]
---
apiVersion: v1
kind: Service
metadata: { name: catalog-svc, namespace: ${Q3_NS} }
spec:
  selector: { app: catalog }
  ports: [ { name: http, port: 8080, targetPort: 80 } ]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: books-ingress, namespace: ${Q3_NS} }
spec:
  ingressClassName: nginx
  tls:
    - hosts: [ ${Q3_HOST} ]
      secretName: books-tls
  rules:
    - host: ${Q3_HOST}
      http:
        paths:
          - path: /catalog
            pathType: Prefix
            backend:
              service: { name: catalog-svc, port: { number: 8080 } }
YAML
  local d; d=$(mktemp -d)
  if openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
       -keyout "$d/tls.key" -out "$d/tls.crt" \
       -subj "/CN=${Q3_HOST}" -addext "subjectAltName=DNS:${Q3_HOST}" &>/dev/null; then
    kubectl create secret tls books-tls -n "$Q3_NS" --cert="$d/tls.crt" --key="$d/tls.key" &>/dev/null
  else
    echo -e "  ${RED}Q3  openssl 로 인증서를 만들지 못했습니다 — Secret books-tls 없음${RESET}"
  fi
  rm -rf "$d"
  echo "  Q3  bookstore 에 catalog(+catalog-svc:8080) · Secret books-tls · Ingress books-ingress 배치"

  # ── Q4: 지금 기본으로 지정된 StorageClass 하나
  sc_defaults | grep -vxE 'bulk-hdd|fast-nvme' > "$SC_REC" 2>/dev/null || true
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: bulk-hdd
  annotations: { storageclass.kubernetes.io/is-default-class: "true" }
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
YAML
  save_uid sc-bulk-hdd storageclass bulk-hdd
  echo "  Q4  StorageClass bulk-hdd (현재 기본)"
  local others; others=$(sc_defaults | grep -vx bulk-hdd | tr '\n' ' ')
  [[ -n "$others" ]] && echo -e "  ${ORANGE}Q4  참고: 이 클러스터에는 다른 기본 StorageClass 도 있습니다 → ${others}(함께 해제해야 '유일한 기본' 이 됩니다)${RESET}"

  # ── Q6: 보호할 stock-api 와 접속을 시도할 파드 두 개 + 정책 파일 세 개
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: shopfront }
---
apiVersion: v1
kind: Namespace
metadata: { name: stockroom }
---
apiVersion: v1
kind: Pod
metadata: { name: stock-api, namespace: stockroom, labels: { app: stock-api } }
spec:
  affinity: ${AFF}
  terminationGracePeriodSeconds: 1
  containers: [ { name: nginx, image: "nginx:1.27", ports: [ { containerPort: 80 } ] } ]
---
apiVersion: v1
kind: Service
metadata: { name: stock-api, namespace: stockroom }
spec:
  selector: { app: stock-api }
  ports: [ { port: 80, targetPort: 80 } ]
---
apiVersion: v1
kind: Pod
metadata: { name: audit, namespace: stockroom, labels: { app: audit } }
spec:
  affinity: ${AFF}
  terminationGracePeriodSeconds: 1
  containers: [ { name: c, image: "busybox:1.36", command: ["sh", "-c", "sleep 36000"] } ]
---
apiVersion: v1
kind: Pod
metadata: { name: web, namespace: shopfront, labels: { app: web } }
spec:
  affinity: ${AFF}
  terminationGracePeriodSeconds: 1
  containers: [ { name: c, image: "busybox:1.36", command: ["sh", "-c", "sleep 36000"] } ]
YAML
  rmf "$Q6_DIR"; mkdir -p "$Q6_DIR"
  # policy-1 — 레이블이 틀렸다: 네임스페이스에 name=shopfront 라는 레이블은 없다 → 아무도 못 들어온다
  cat > "$Q6_DIR/policy-1.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: stock-api-policy-1
  namespace: stockroom
spec:
  podSelector:
    matchLabels:
      app: stock-api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: shopfront
      ports:
        - protocol: TCP
          port: 80
YAML
  # policy-2 — 너무 넓다: from 항목이 둘(OR) → shopfront 네임스페이스 "또는" stockroom 의 모든 파드
  cat > "$Q6_DIR/policy-2.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: stock-api-policy-2
  namespace: stockroom
spec:
  podSelector:
    matchLabels:
      app: stock-api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: shopfront
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 80
YAML
  # policy-3 — 정답: shopfront 네임스페이스에서 오는 TCP 80 만
  cat > "$Q6_DIR/policy-3.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: stock-api-policy-3
  namespace: stockroom
spec:
  podSelector:
    matchLabels:
      app: stock-api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: shopfront
      ports:
        - protocol: TCP
          port: 80
YAML
  ( cd "$Q6_DIR" && cksum policy-1.yaml policy-2.yaml policy-3.yaml ) > "$Q6_SUM" 2>/dev/null
  echo "  Q6  stockroom/stock-api(+Service) · stockroom/audit · shopfront/web 배치, $Q6_DIR 에 policy-1~3.yaml"

  # ── Q7: 기존 PriorityClass 세 개 + 우선순위 없는 Deployment
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: tier-critical }
value: 800000
description: "existing - customer facing"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: tier-standard }
value: 400000
description: "existing - default tier"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: tier-batch }
value: 1000
description: "existing - batch jobs"
---
apiVersion: v1
kind: Namespace
metadata: { name: telemetry }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: metrics-relay, namespace: telemetry, labels: { app: metrics-relay } }
spec:
  replicas: 2
  selector: { matchLabels: { app: metrics-relay } }
  template:
    metadata: { labels: { app: metrics-relay } }
    spec:
      affinity: ${AFF}
      terminationGracePeriodSeconds: 1
      containers:
        - name: relay
          image: busybox:1.36
          command: ["sh", "-c", "sleep 36000"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML
  save_uid telemetry-metrics-relay -n telemetry deployment metrics-relay
  echo "  Q7  PriorityClass tier-critical(800000) · tier-standard(400000) · tier-batch(1000), telemetry/metrics-relay 배치"
  return 0
}

# ══════════════════════════════════════════════════════════════
# Q1 — Helm: 설치하지 않고 뽑기 + CRD 없이 설치
# ══════════════════════════════════════════════════════════════
q1_title() { echo "Helm: render a chart, then install it without its CRDs [15 pts]"; }
q1_text() { cat <<'EOF'
Argo CD is going to be installed with Helm. Its CRDs are managed separately
and are ALREADY installed in the cluster.

  (a) Add the Helm repository
        name  argo
        URL   https://argoproj.github.io/argo-helm

      Render the chart argo/argo-cd to a file WITHOUT installing it
        chart version   7.7.0
        release name    cd-main
        namespace       cd-system
        output file     /tmp/mock8-argocd.yaml

      The file must NOT contain any CustomResourceDefinition.

  (b) Install the same chart and version into the cluster
        release name    cd-main
        namespace       cd-system   (create it)

      The chart must NOT install the CRDs.

You do not have to wait for the Argo CD Pods to become Ready.

Verify:
  grep -c 'kind: CustomResourceDefinition' /tmp/mock8-argocd.yaml     -> 0
  helm list -n cd-system                                              -> deployed
  helm get values cd-main -n cd-system
EOF
}
q1_title_ko() { echo "Helm — 설치하지 않고 뽑기, CRD 없이 설치하기 [15점]"; }
q1_text_ko() { cat <<'EOF'
Argo CD 를 Helm 으로 설치하려 한다. Argo CD 의 CRD 는 따로 관리하며
클러스터에 이미 설치돼 있다.

  (a) Helm 저장소를 추가한다
        이름  argo
        주소  https://argoproj.github.io/argo-helm

      argo/argo-cd 차트를 설치하지 말고 파일로 렌더링한다
        차트 버전     7.7.0
        릴리스 이름   cd-main
        네임스페이스  cd-system
        저장 경로     /tmp/mock8-argocd.yaml

      파일에 CustomResourceDefinition 이 하나도 없어야 한다.

  (b) 같은 차트 · 같은 버전을 클러스터에 설치한다
        릴리스 이름   cd-main
        네임스페이스  cd-system   (만들어서)

      차트가 CRD 를 설치하면 안 된다.

Argo CD 파드가 Ready 가 될 때까지 기다릴 필요는 없다.

[확인]
  grep -c 'kind: CustomResourceDefinition' /tmp/mock8-argocd.yaml     → 0
  helm list -n cd-system                                              → deployed
  helm get values cd-main -n cd-system
EOF
}
q1_hint() { cat <<'EOF'
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update

# CRD 를 끄는 값 이름을 차트에서 찾는다 — --skip-crds 는 차트의 crds/ 폴더만 빼는데,
# 이 차트는 CRD 를 templates/ 에 두고 crds.install 값으로 켜고 끈다
helm show values argo/argo-cd --version 7.7.0 | grep -A3 '^crds:'

# (a) template = 클러스터를 건드리지 않고 YAML 만 출력
helm template cd-main argo/argo-cd --version 7.7.0 -n cd-system \
  --set crds.install=false > /tmp/mock8-argocd.yaml
grep -c 'kind: CustomResourceDefinition' /tmp/mock8-argocd.yaml     # 0

# (b) install — 같은 옵션. 네임스페이스는 --create-namespace
helm install cd-main argo/argo-cd --version 7.7.0 -n cd-system --create-namespace \
  --set crds.install=false
EOF
}
q1_grade() {
  # ── (a) 렌더링한 파일
  check "$Q1_OUT 이 있다" "test -s $Q1_OUT" 1
  check_output "(a) 차트 버전 7.7.0 으로 렌더링했다" "grep -m1 'helm.sh/chart: argo-cd-' $Q1_OUT" 'argo-cd-7\.7\.0$' 2
  check_output "(a) 네임스페이스 cd-system 으로 렌더링했다" "grep -m1 '^  namespace:' $Q1_OUT" 'namespace: cd-system$' 1
  check_output "(a) 릴리스 이름 cd-main 으로 렌더링했다" "grep -m1 'app.kubernetes.io/instance:' $Q1_OUT" 'instance: cd-main$' 1
  local n has=1; n=$(grep -c 'kind: CustomResourceDefinition' "$Q1_OUT" 2>/dev/null); n="${n//[^0-9]/}"; n="${n:-0}"
  [[ -s "$Q1_OUT" ]] && has=0
  check_result "(a) 파일에 CustomResourceDefinition 이 0개$([[ $has == 0 ]] && echo " (현재 ${n}개)")" \
    "$([[ $has == 0 && "$n" == "0" ]] && echo 0 || echo 1)" \
    "$([[ $has == 0 ]] && echo '--skip-crds 로 안 빠지면 차트 values 의 crds 설정을 본다' || echo '파일이 없다')" 3

  # ── (b) 설치한 릴리스
  check_output "(b) cd-system 에 릴리스 cd-main 이 deployed" \
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
    "$([[ $rel != 0 ]] && echo '릴리스 cd-main 이 없다' || { [[ -z "$crd" ]] && echo 'applications.argoproj.io CRD 가 없다 — bash exam.sh start 로 다시 준비' || echo "CRD 가 릴리스 ${owner} 소유다"; })" 1
  check_output "(b) Argo CD server Deployment 가 만들어졌다" \
    "kubectl -n $Q1_NS get deployment -l app.kubernetes.io/name=argocd-server,app.kubernetes.io/instance=$Q1_REL -o name" 'argocd-server' 1
}

# ══════════════════════════════════════════════════════════════
# Q2 — HPA
# ══════════════════════════════════════════════════════════════
q2_title() { echo "HPA for an existing Deployment [10 pts]"; }
q2_text() { cat <<'EOF'
The Deployment cart-api runs in the checkout namespace.
Create a HorizontalPodAutoscaler for it.

  name             cart-api-hpa
  target           Deployment cart-api
  replicas         minimum 2, maximum 6
  metric           average CPU utilization 60%
  scale-down       stabilization window of 45 seconds

Do not modify the Deployment.

Verify:
  kubectl -n checkout get hpa cart-api-hpa
  kubectl -n checkout get hpa cart-api-hpa -o yaml | grep -A3 behavior
EOF
}
q2_title_ko() { echo "기존 Deployment 에 HPA 붙이기 [10점]"; }
q2_text_ko() { cat <<'EOF'
checkout 네임스페이스에 Deployment cart-api 가 돌고 있다.
여기에 HorizontalPodAutoscaler 를 만든다.

  이름            cart-api-hpa
  대상            Deployment cart-api
  레플리카        최소 2, 최대 6
  기준            CPU 평균 사용률 60%
  스케일 다운     안정화 시간 45초

Deployment 는 수정하지 않는다.

[확인]
  kubectl -n checkout get hpa cart-api-hpa
  kubectl -n checkout get hpa cart-api-hpa -o yaml | grep -A3 behavior
EOF
}
q2_hint() { cat <<'EOF'
# 뼈대는 명령으로 — HPA 이름이 Deployment 이름과 다르므로 --name
#   (kubectl 1.34 부터는 --cpu-percent=60 대신 --cpu=60% 를 쓰라는 경고가 나온다. 둘 다 된다)
kubectl -n checkout autoscale deployment cart-api --name=cart-api-hpa \
  --cpu-percent=60 --min=2 --max=6 --dry-run=client -o yaml > hpa.yaml

# behavior 는 명령 옵션이 없다 → spec 아래에 추가 (apiVersion 이 autoscaling/v2 인지 확인)
#   파일 끝에 붙이면 안 된다 — 맨 아래는 status: 라서 "unknown field status.behavior" 로 거부된다
#   spec:
#     behavior:
#       scaleDown:
#         stabilizationWindowSeconds: 45
kubectl apply -f hpa.yaml

# metrics-server 가 없으면 TARGETS 가 <unknown> 으로 나오지만 채점에는 문제없다
EOF
}
q2_grade() {
  local hpa="kubectl -n checkout get hpa cart-api-hpa -o jsonpath"
  check "HPA cart-api-hpa 존재" "kubectl -n checkout get hpa cart-api-hpa" 2
  check_output "대상이 Deployment cart-api" \
    "$hpa='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}'" '^Deployment/cart-api$' 2
  check_output "minReplicas 2" "$hpa='{.spec.minReplicas}'" '^2$' 1
  check_output "maxReplicas 6" "$hpa='{.spec.maxReplicas}'" '^6$' 1
  check_output "CPU 평균 사용률 60%" \
    "$hpa='{.spec.metrics[?(@.resource.name==\"cpu\")].resource.target.averageUtilization}'" '^60$' 2
  check_output "scaleDown 안정화 시간 45초" \
    "$hpa='{.spec.behavior.scaleDown.stabilizationWindowSeconds}'" '^45$' 2
}

# ══════════════════════════════════════════════════════════════
# Q3 — Ingress → Gateway API
# ══════════════════════════════════════════════════════════════
q3_title() { echo "Migrate an Ingress to the Gateway API [20 pts]"; }
q3_text() { cat <<'EOF'
In the bookstore namespace the Ingress books-ingress exposes an application
over HTTPS. Migrate it to the Gateway API. A Gateway API controller is
installed and provides the GatewayClass nginx.

Look at the existing Ingress first:
  kubectl -n bookstore get ingress books-ingress -o yaml

  (1) Create a Gateway named books-gateway in bookstore
        gatewayClassName   nginx
        listener           name https, port 443, protocol HTTPS
        hostname           the same host as the Ingress
        tls                terminate with the TLS Secret the Ingress uses

  (2) Create an HTTPRoute named books-route in bookstore
        parentRefs         books-gateway
        hostnames          the same host as the Ingress
        rule               the same path (PathPrefix), backend Service
                           and port as the Ingress

  (3) Delete the Ingress books-ingress.
      Keep the Service and the Secret.

Verify:
  kubectl -n bookstore get gateway,httproute
  kubectl -n bookstore describe gateway books-gateway
  kubectl -n bookstore get ingress
EOF
}
q3_title_ko() { echo "Ingress 를 Gateway API 로 옮기기 [20점]"; }
q3_text_ko() { cat <<'EOF'
bookstore 네임스페이스의 Ingress books-ingress 가 애플리케이션을 HTTPS 로
노출하고 있다. 이것을 Gateway API 로 옮긴다. Gateway API 컨트롤러가
설치돼 있고 GatewayClass nginx 를 제공한다.

먼저 기존 Ingress 를 확인한다:
  kubectl -n bookstore get ingress books-ingress -o yaml

  (1) bookstore 에 Gateway books-gateway 를 만든다
        gatewayClassName   nginx
        리스너             이름 https, 포트 443, 프로토콜 HTTPS
        hostname           Ingress 와 같은 호스트
        tls                Ingress 가 쓰는 TLS Secret 으로 종료(Terminate)

  (2) bookstore 에 HTTPRoute books-route 를 만든다
        parentRefs         books-gateway
        hostnames          Ingress 와 같은 호스트
        규칙               Ingress 와 같은 경로(PathPrefix) · 백엔드 Service · 포트

  (3) Ingress books-ingress 를 삭제한다.
      Service 와 Secret 은 남겨 둔다.

[확인]
  kubectl -n bookstore get gateway,httproute
  kubectl -n bookstore describe gateway books-gateway
  kubectl -n bookstore get ingress
EOF
}
q3_hint() { cat <<'EOF'
kubectl -n bookstore get ingress books-ingress -o yaml   # host · secretName · path · backend 를 옮겨 적는다

apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: books-gateway, namespace: bookstore }
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
metadata: { name: books-route, namespace: bookstore }
spec:
  parentRefs: [ { name: books-gateway } ]
  hostnames: [ <Ingress 의 host> ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: <Ingress 의 path> } } ]
    backendRefs: [ { name: <Service>, port: <포트> } ]

kubectl -n bookstore describe gateway books-gateway     # Programmed True 인지
kubectl -n bookstore delete ingress books-ingress
EOF
}
q3_grade() {
  local mode ns="$Q3_NS"; mode=$(gw_mode)
  if [[ "$mode" == "none" ]]; then
    check_result "Gateway API 가 설치되어 있다" 1 "미설치 — 인터넷 연결 후 bash exam.sh start 재실행" 20
    return
  fi
  local GW="kubectl -n $ns get gateway books-gateway -o jsonpath"
  local RT="kubectl -n $ns get httproute books-route -o jsonpath"
  local L='.spec.listeners[?(@.port==443)]'

  # ── Gateway 스펙 (리스너는 포트 443 으로 찾는다 — 이름이 달라도 나머지를 채점할 수 있게)
  check "Gateway books-gateway 존재" "kubectl -n $ns get gateway books-gateway" 1
  check_output "gatewayClassName nginx" "$GW='{.spec.gatewayClassName}'" '^nginx$' 1
  check_output "리스너 https · 443 · HTTPS" "$GW='{$L.name}/{$L.protocol}'" '^https/HTTPS$' 2
  check_output "리스너 hostname $Q3_HOST" "$GW='{$L.hostname}'" '^books\.example\.local$' 2
  check_output "리스너 TLS 인증서가 Secret books-tls" "$GW='{$L.tls.certificateRefs[*].name}'" '(^| )books-tls( |$)' 2
  # 비어 있으면(생략) 기본값 Terminate — 단, 443 리스너가 없을 때 빈 출력으로 통과하지 않게 따로 판정
  local tm lp
  lp=$(kubectl -n "$ns" get gateway books-gateway -o jsonpath="{$L.port}" 2>/dev/null)
  tm=$(kubectl -n "$ns" get gateway books-gateway -o jsonpath="{$L.tls.mode}" 2>/dev/null)
  check_result "TLS 모드 Terminate (생략하면 기본값)" \
    "$([[ "$lp" == "443" && ( -z "$tm" || "$tm" == Terminate ) ]] && echo 0 || echo 1)" \
    "$([[ "$lp" == "443" ]] && echo "tls.mode: $tm" || echo '포트 443 리스너가 없음')" 1

  # ── HTTPRoute 스펙
  check "HTTPRoute books-route 존재" "kubectl -n $ns get httproute books-route" 1
  check_output "parentRefs 가 books-gateway" "$RT='{.spec.parentRefs[*].name}'" '(^| )books-gateway( |$)' 1
  check_output "hostnames 에 $Q3_HOST" "$RT='{.spec.hostnames[*]}'" '(^| )books\.example\.local( |$)' 1
  check_output "경로 매치 PathPrefix /catalog" \
    "$RT='{range .spec.rules[*].matches[*]}{.path.type}={.path.value}{\" \"}{end}'" '(^| )PathPrefix=/catalog/?( |$)' 1
  check_output "backendRef catalog-svc:8080" \
    "$RT='{range .spec.rules[*].backendRefs[*]}{.name}:{.port}{\" \"}{end}'" '(^| )catalog-svc:8080( |$)' 2

  # ── 정리 — Ingress 는 지우고, Service · Secret 은 남긴다. Gateway 를 만들기 전에 지우기만 해서는 점수가 없다
  local ing gw_ok=1; ing=$(kubectl -n "$ns" get ingress books-ingress 2>&1)
  kubectl -n "$ns" get gateway books-gateway &>/dev/null && gw_ok=0
  check_result "Ingress books-ingress 삭제됨" \
    "$([[ $gw_ok == 0 && "$ing" == *NotFound* ]] && echo 0 || echo 1)" \
    "$([[ $gw_ok != 0 ]] && echo 'Gateway 를 먼저 만든다' || echo "아직 남아 있다 — kubectl -n $ns delete ingress books-ingress")" 1
  local keep=1; kubectl -n "$ns" get service catalog-svc &>/dev/null && kubectl -n "$ns" get secret books-tls &>/dev/null && keep=0
  check_result "Service catalog-svc 와 Secret books-tls 는 남아 있다" \
    "$([[ $gw_ok == 0 && $keep == 0 ]] && echo 0 || echo 1)" \
    "$([[ $gw_ok != 0 ]] && echo 'Gateway 를 먼저 만든다' || echo 'Service 또는 Secret 이 지워졌다 — bash exam.sh start 로 다시 준비')" 1

  if [[ "$mode" != "full" ]]; then
    check_result "Gateway Programmed · HTTPS 트래픽 (컨트롤러가 없어 확인 불가)" 1 "컨트롤러 설치 후 bash exam.sh start 를 다시" 3
    return
  fi

  # ── 컨트롤러가 받아들였는가 + 실제 HTTPS 트래픽 (Gateway 가 만든 Service 의 443 NodePort 로)
  check_output "Gateway Programmed" "$GW='{.status.conditions[?(@.type==\"Programmed\")].status}'" 'True' 1
  #   Gateway 를 만든 직후에는 데이터 플레인 파드가 아직 뜨는 중이다 (15~20초).
  #   파드가 하나라도 Ready 가 될 때까지 30초까지 기다리고, 그 뒤 4초 간격으로 세 번까지 요청한다
  local port ip ips hit="" resp try w
  port=$(kubectl -n "$ns" get svc -l gateway.networking.k8s.io/gateway-name=books-gateway \
           -o jsonpath='{.items[0].spec.ports[?(@.port==443)].nodePort}' 2>/dev/null)
  port="${port//[^0-9]/}"
  if [[ -n "$port" ]] && command -v curl &>/dev/null; then
    for ((w=0; w<30; w+=3)); do
      [[ "$(kubectl -n "$ns" get pods -l gateway.networking.k8s.io/gateway-name=books-gateway \
            -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == *True* ]] && break
      sleep 3
    done
    ips=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null)
    for try in 1 2 3; do
      for ip in $ips; do
        resp=$(curl -sk --max-time 4 --resolve "${Q3_HOST}:${port}:${ip}" "https://${Q3_HOST}:${port}/catalog/" 2>/dev/null || true)
        [[ "$resp" == *catalog-ok* ]] && { hit="$ip"; break 2; }
      done
      (( try < 3 )) && sleep 4
    done
  fi
  check_result "https://$Q3_HOST/catalog/ 가 Gateway 를 거쳐 백엔드에 닿는다${hit:+ — $hit:$port}" \
    "$([[ -n "$hit" ]] && echo 0 || echo 1)" \
    "${port:+NodePort $port 응답 없음 — }리스너 hostname · certificateRefs · HTTPRoute hostnames/경로/백엔드 확인" 2
}

# ══════════════════════════════════════════════════════════════
# Q4 — 기본 StorageClass
# ══════════════════════════════════════════════════════════════
q4_title() { echo "Create a StorageClass and make it the only default [10 pts]"; }
q4_text() { cat <<'EOF'
The cluster currently uses bulk-hdd as its default StorageClass.

  (a) Create a StorageClass named fast-nvme
        provisioner         rancher.io/local-path
        volumeBindingMode   WaitForFirstConsumer
        reclaimPolicy       Retain

  (b) Make fast-nvme the ONLY default StorageClass of the cluster.

Do not delete or recreate bulk-hdd.

Verify:
  kubectl get storageclass          -> (default) appears next to fast-nvme only
EOF
}
q4_title_ko() { echo "StorageClass 를 만들어 유일한 기본으로 [10점]"; }
q4_text_ko() { cat <<'EOF'
지금 클러스터의 기본 StorageClass 는 bulk-hdd 다.

  (a) fast-nvme StorageClass 를 만든다
        provisioner         rancher.io/local-path
        volumeBindingMode   WaitForFirstConsumer
        reclaimPolicy       Retain

  (b) fast-nvme 을 클러스터의 유일한 기본 StorageClass 로 만든다.

bulk-hdd 는 지우거나 다시 만들지 않는다.

[확인]
  kubectl get storageclass          → (default) 가 fast-nvme 옆에만
EOF
}
q4_hint() { cat <<'EOF'
kubectl get sc                       # NAME 옆의 (default) 가 지금의 기본

# (a) 기본 지정은 애너테이션 한 줄
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-nvme
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain

# (b) 기존 기본을 해제한다 — 둘 다 true 면 '유일한 기본' 이 아니다. 지우지 말고 false 로
kubectl patch storageclass bulk-hdd \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
EOF
}
q4_grade() {
  local sc="kubectl get storageclass fast-nvme -o jsonpath"
  check "fast-nvme 존재" "kubectl get storageclass fast-nvme" 1
  check_output "provisioner rancher.io/local-path" "$sc='{.provisioner}'" '^rancher\.io/local-path$' 1
  check_output "volumeBindingMode WaitForFirstConsumer" "$sc='{.volumeBindingMode}'" '^WaitForFirstConsumer$' 1
  check_output "reclaimPolicy Retain" "$sc='{.reclaimPolicy}'" '^Retain$' 1
  check_output "fast-nvme 이 기본으로 지정됐다" \
    "$sc='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'" '^true$' 2
  # 아무것도 하지 않은 상태에서 점수가 새지 않게, fast-nvme 을 만든 뒤에만 인정한다
  local made=1; kubectl get storageclass fast-nvme &>/dev/null && made=0
  check_result "bulk-hdd 는 지우거나 다시 만들지 않았다" \
    "$([[ $made == 0 ]] && same_uid sc-bulk-hdd storageclass bulk-hdd && echo 0 || echo 1)" \
    "$([[ $made != 0 ]] && echo 'fast-nvme 을 먼저 만든다' || echo 'bulk-hdd 가 없거나 새로 만들어졌다')" 1
  local defaults; defaults=$(sc_defaults | tr '\n' ' ')
  check_result "기본 StorageClass 가 fast-nvme 하나뿐 (현재: ${defaults:-없음})" \
    "$([[ "$defaults" == "fast-nvme " ]] && echo 0 || echo 1)" "다른 클래스의 is-default-class 를 false 로" 3
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
The node ${n} has stopped reporting to the cluster and is (or will be,
within a minute) NotReady.

Find out why the kubelet is not running on ${n} and fix it.

  - the node must be Ready again
  - the kubelet must be running
  - the kubelet must start automatically after a reboot

Do not reinstall any package and do not run kubeadm reset / join.

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
노드 ${n} 이 클러스터에 상태를 보고하지 않아 NotReady 다
(지금 아니라면 1분 안에 NotReady 가 된다).

${n} 에서 kubelet 이 왜 돌지 않는지 찾아 고친다.

  - 노드가 다시 Ready 여야 한다
  - kubelet 이 실행 중이어야 한다
  - 재부팅한 뒤에도 kubelet 이 자동으로 시작돼야 한다

패키지를 다시 설치하거나 kubeadm reset / join 을 하지 않는다.

노드 접속:
  ssh ${n}          (또는: ssh ${ip})
  sudo -i

[확인] (컨트롤플레인으로 돌아와서)
  kubectl get nodes          → ${n} 이 Ready
EOF
}
q5_hint() { cat <<'EOF'
systemctl status kubelet --no-pager      # Loaded 줄의 enabled/disabled · Drop-In 목록 · Active 상태
#   inactive (dead) · disabled        → 멈춰 있고, 재부팅해도 안 뜬다
systemctl enable --now kubelet           # 지금 시작 + 재부팅 후 자동 시작

systemctl status kubelet --no-pager      # 그래도 activating (auto-restart) 라면 설정 오류로 계속 죽는 것
journalctl -u kubelet -n 20 --no-pager   # 로그가 가리키는 것을 본다 (status=203/EXEC = 실행 파일을 못 찾음)
systemctl cat kubelet                    # 유닛 + 드롭인 전체. ExecStart 가 가리키는 경로가 실제로 있는지
which kubelet

# 드롭인을 고쳤으면 daemon-reload 를 먼저 해야 반영된다
systemctl daemon-reload && systemctl restart kubelet
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
    "$([[ -z "$act" ]] && echo "$why" || { [[ "$act" == "active" ]] && echo 'kubelet 은 떴는데 노드가 아직 Ready 가 아니다 — 잠시 뒤 다시 채점' || echo 'systemctl status kubelet · journalctl -u kubelet'; })" 11
  check_result "kubelet 이 enabled — 재부팅 후 자동 시작 (is-enabled: ${en:-확인 불가})" \
    "$([[ "$en" == "enabled" ]] && echo 0 || echo 1)" "$([[ -z "$en" ]] && echo "$why" || echo "start 만 하면 재부팅 뒤 다시 멈춘다 — systemctl enable kubelet")" 4
}

# ══════════════════════════════════════════════════════════════
# Q6 — NetworkPolicy 고르기
# ══════════════════════════════════════════════════════════════
q6_title() { echo "NetworkPolicy: apply the right one of three [15 pts]"; }
q6_text() { cat <<'EOF'
In the stockroom namespace the Pod stock-api (label app=stock-api) is exposed
by the Service stock-api on port 80.

Requirement:
  ONLY Pods in the shopfront namespace may reach stock-api, on TCP port 80.
  Every other Pod - including other Pods in stockroom - must be blocked.

Three candidate manifests are prepared:

  /tmp/mock8-netpol/policy-1.yaml
  /tmp/mock8-netpol/policy-2.yaml
  /tmp/mock8-netpol/policy-3.yaml

Apply exactly ONE of them - the one that meets the requirement and allows
nothing more. Do not edit the files, do not apply more than one, and do not
create any other NetworkPolicy.

Test Pods already exist:
  shopfront/web     -> must reach stock-api
  stockroom/audit   -> must be blocked

Verify:
  kubectl -n shopfront exec web   -- wget -qO- -T 3 http://stock-api.stockroom
  kubectl -n stockroom exec audit -- wget -qO- -T 3 http://stock-api
EOF
}
q6_title_ko() { echo "NetworkPolicy — 세 개 중 맞는 것 하나 적용 [15점]"; }
q6_text_ko() { cat <<'EOF'
stockroom 네임스페이스의 파드 stock-api(레이블 app=stock-api)는
Service stock-api 의 80 포트로 노출돼 있다.

요구 사항:
  shopfront 네임스페이스의 파드만 stock-api 의 TCP 80 에 닿을 수 있다.
  그 밖의 파드는 stockroom 안의 다른 파드까지 포함해 모두 막혀야 한다.

후보 매니페스트 세 개가 준비돼 있다.

  /tmp/mock8-netpol/policy-1.yaml
  /tmp/mock8-netpol/policy-2.yaml
  /tmp/mock8-netpol/policy-3.yaml

이 중 정확히 하나만 적용한다 — 요구 사항을 만족하면서 그 이상은 허용하지 않는 것.
파일을 고치지 말고, 둘 이상 적용하지 말고, 다른 NetworkPolicy 를 따로 만들지도 않는다.

테스트 파드가 이미 있다.
  shopfront/web     → stock-api 에 닿아야 한다
  stockroom/audit   → 막혀야 한다

[확인]
  kubectl -n shopfront exec web   -- wget -qO- -T 3 http://stock-api.stockroom
  kubectl -n stockroom exec audit -- wget -qO- -T 3 http://stock-api
EOF
}
q6_hint() { cat <<'EOF'
# 1) 실제 레이블부터 본다 — 정책은 레이블로 고른다
kubectl get ns shopfront stockroom --show-labels
kubectl -n stockroom get pods --show-labels

# 2) 세 파일의 from 만 비교한다 (대상 · 포트는 같다)
diff /tmp/mock8-netpol/policy-1.yaml /tmp/mock8-netpol/policy-3.yaml
diff /tmp/mock8-netpol/policy-2.yaml /tmp/mock8-netpol/policy-3.yaml

#   namespaceSelector 의 레이블이 네임스페이스에 실제로 붙어 있는가
#   from 아래 대시(-)가 둘이면 OR — "- podSelector: {}" 는 같은 네임스페이스의 모든 파드를 연다

# 3) 하나만 적용하고, 되는 쪽과 막혀야 하는 쪽을 둘 다 확인한다
#    잘못 적용했으면 kubectl -n stockroom delete networkpolicy <이름>
EOF
}
q6_grade() {
  local P=stockroom
  check "정답 정책 stock-api-policy-3 이 적용됐다" "kubectl -n $P get networkpolicy stock-api-policy-3" 4
  local names n other=""
  names=$(kubectl -n "$P" get networkpolicy -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  n=$(wc -w <<< "$names"); n="${n//[^0-9]/}"
  # 어느 것이 왜 틀렸는지는 알려 주지 않는다 — 고르는 것이 문제다
  [[ " $names " == *" stock-api-policy-1 "* ]] && other+="policy-1 "
  [[ " $names " == *" stock-api-policy-2 "* ]] && other+="policy-2 "
  # 아무것도 적용하지 않은 상태에서 점수가 새지 않게, 정책이 하나라도 있을 때만 통과
  check_result "다른 후보(policy-1 · policy-2)는 적용하지 않았다" \
    "$([[ "${n:-0}" -ge 1 && -z "$other" ]] && echo 0 || echo 1)" \
    "$([[ "${n:-0}" -lt 1 ]] && echo '적용된 정책이 없다' || echo "적용돼 있음: ${other}— kubectl delete 로 지운다")" 2
  check_result "stockroom 의 NetworkPolicy 가 정답 하나뿐이다" \
    "$([[ "$names" == "stock-api-policy-3" ]] && echo 0 || echo 1)" "현재 ${n:-0}개: ${names:-없음}" 2
  check_result "준비된 파일을 고치지 않았다" \
    "$([[ "${n:-0}" -ge 1 && -s "$Q6_SUM" ]] && ( cd "$Q6_DIR" 2>/dev/null && cksum policy-1.yaml policy-2.yaml policy-3.yaml 2>/dev/null ) | diff -q - "$Q6_SUM" &>/dev/null && echo 0 || echo 1)" \
    "$([[ "${n:-0}" -lt 1 ]] && echo '적용된 정책이 없다' || echo "$Q6_DIR 의 파일이 바뀌었거나 없다 — bash exam.sh start 로 다시 준비")" 1

  # 실제 연결 — 허용 경로가 살아 있고 정책이 걸려 있을 때만 '막힘' 을 믿는다
  wait_ready stock-api "$P" || true
  local probe='wget -qO- -T 3 http://stock-api.stockroom.svc.cluster.local 2>/dev/null' a b served=1
  a=$(kubectl -n shopfront exec web   -- sh -c "$probe" 2>/dev/null)
  b=$(kubectl -n "$P"      exec audit -- sh -c "$probe" 2>/dev/null)
  grep -qi nginx <<< "$a" && served=0
  check_result "shopfront/web → stock-api:80 응답 (허용)" \
    "$([[ "${n:-0}" -ge 1 && $served == 0 ]] && echo 0 || echo 1)" \
    "$([[ "${n:-0}" -lt 1 ]] && echo '적용된 정책이 없다' || echo '응답 없음 — 적용한 정책이 shopfront 를 실제로 고르는지 확인')" 3
  check_result "stockroom/audit → stock-api 차단" \
    "$([[ "${n:-0}" -ge 1 && $served == 0 ]] && ! grep -qi nginx <<< "$b" && echo 0 || echo 1)" \
    "$([[ "${n:-0}" -lt 1 ]] && echo '적용된 정책이 없다' || { [[ $served != 0 ]] && echo '허용 경로부터 확인' || echo 'audit 이 닿는다 — 요구보다 넓게 여는 정책이다'; })" 3
}

# ══════════════════════════════════════════════════════════════
# Q7 — PriorityClass
# ══════════════════════════════════════════════════════════════
q7_title() { echo "PriorityClass one below the highest [15 pts]"; }
q7_text() { cat <<'EOF'
Several user-defined PriorityClasses already exist in the cluster.

  (a) Create a PriorityClass named relay-priority whose value is exactly
      ONE LESS than the highest value among the existing user-defined
      PriorityClasses (ignore the built-in system-* classes).
      It must not be the global default.

  (b) Update the existing Deployment metrics-relay in the telemetry
      namespace so that its Pods use relay-priority.
      Do not delete and recreate the Deployment.

All metrics-relay Pods must be Running with the new priority.

Verify:
  kubectl get priorityclass
  kubectl -n telemetry get pods -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priority
EOF
}
q7_title_ko() { echo "가장 높은 값보다 1 낮은 PriorityClass [15점]"; }
q7_text_ko() { cat <<'EOF'
클러스터에 사용자가 만든 PriorityClass 가 이미 몇 개 있다.

  (a) relay-priority PriorityClass 를 만든다.
      값은 기존 사용자 정의 PriorityClass 중 가장 높은 값보다 정확히 1 작게.
      (system- 으로 시작하는 기본 클래스는 제외)
      globalDefault 가 되어서는 안 된다.

  (b) telemetry 네임스페이스의 기존 Deployment metrics-relay 가
      relay-priority 를 쓰도록 수정한다.
      Deployment 를 지우고 다시 만들지 않는다.

metrics-relay 파드가 모두 새 우선순위로 Running 이어야 한다.

[확인]
  kubectl get priorityclass
  kubectl -n telemetry get pods -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priority
EOF
}
q7_hint() { cat <<'EOF'
kubectl get priorityclass --sort-by=.value          # system-* 를 빼고 가장 큰 값을 찾는다

kubectl create priorityclass relay-priority --value=<그 값 - 1> --description="metrics relay"

# 파드 속성이므로 spec.template.spec 아래 — patch 하면 롤아웃으로 파드가 새로 뜬다
kubectl -n telemetry patch deployment metrics-relay \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"relay-priority"}}}}'
kubectl -n telemetry rollout status deployment metrics-relay
EOF
}
q7_grade() {
  # 기대값은 채점 시점에 계산한다 — 다른 실습이 남긴 클래스가 있어도 "가장 높은 값 - 1" 이 기준
  local max want
  max=$(kubectl get priorityclass -o jsonpath='{range .items[*]}{.metadata.name} {.value}{"\n"}{end}' 2>/dev/null \
        | grep -v '^system-' | grep -v '^relay-priority ' | awk '{print $2}' | sort -n | tail -1)
  max="${max//[^0-9]/}"; max="${max:-800000}"; want=$((max - 1))

  check "relay-priority 존재" "kubectl get priorityclass relay-priority" 2
  check_output "값이 ${want} (가장 높은 사용자 정의 값 ${max} - 1)" \
    "kubectl get priorityclass relay-priority -o jsonpath='{.value}'" "^${want}$" 4
  check_output "globalDefault 가 아니다" \
    "kubectl get priorityclass relay-priority -o jsonpath='{.metadata.name}={.globalDefault}'" '^relay-priority=(false)?$' 1
  check_output "Deployment 템플릿에 priorityClassName: relay-priority" \
    "kubectl -n telemetry get deployment metrics-relay -o jsonpath='{.spec.template.spec.priorityClassName}'" '^relay-priority$' 3
  # 아무것도 하지 않은 상태에서 점수가 새지 않게, relay-priority 를 만든 뒤에만 인정한다
  local made=1; kubectl get priorityclass relay-priority &>/dev/null && made=0
  check_result "Deployment 를 지우고 다시 만들지 않았다" \
    "$([[ $made == 0 ]] && same_uid telemetry-metrics-relay -n telemetry deployment metrics-relay && echo 0 || echo 1)" \
    "$([[ $made != 0 ]] && echo 'relay-priority 를 먼저 만든다' || echo 'metrics-relay 가 없거나 새로 만들어졌다')" 1
  # patch 직후에는 옛 파드와 새 파드가 섞여 있다 — 템플릿이 맞을 때만 롤아웃이 끝나기를 20초까지 기다린다
  [[ "$(kubectl -n telemetry get deployment metrics-relay -o jsonpath='{.spec.template.spec.priorityClassName}' 2>/dev/null)" == "relay-priority" ]] \
    && kubectl -n telemetry rollout status deployment metrics-relay --timeout=20s &>/dev/null
  local pr
  # 롤아웃 중 종료 대기(deletionTimestamp 있음)인 옛 파드는 빼고 본다
  pr=$(kubectl -n telemetry get pods -l app=metrics-relay --field-selector=status.phase=Running \
       -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}|{.spec.priority}{"\n"}{end}' 2>/dev/null \
       | awk -F'|' '$1==""{print $2}' | sort | uniq -c | awk '{print $1"x"$2}' | tr '\n' ' ')
  check_result "Running 파드 2개가 모두 priority ${want} (현재: ${pr:-없음})" \
    "$([[ "$pr" == "2x${want} " ]] && echo 0 || echo 1)" "옛 파드가 남아 있으면 롤아웃이 끝났는지 확인" 4
}

exam_main "$@"
