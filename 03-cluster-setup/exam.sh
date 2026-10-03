#!/usr/bin/env bash
# CKA 3강 실습 — 클러스터 구축 · 노드 조인 · CNI · CRI (순차 진행형)
#   Q1 워커 조인 · Q2 crictl 로그 · Q3 CNI 매니페스트 내려받아 cidr 고치기 · Q4 CRI(cri-dockerd) 패키지 + sysctl
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 3강 실습 — 클러스터 구축 · 노드 조인 · CNI · CRI"
EXAM_NQ=4

# ── Q3: Calico operator 의 custom-resources.yaml (기본 cidr 192.168.0.0/16) ──
CALICO_VER="v3.29.3"
CALICO_CR_URL="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VER}/manifests/custom-resources.yaml"
CNI_DIR=/tmp/calico                       # 학생이 내려받고 고칠 곳
CNI_FILE="$CNI_DIR/custom-resources.yaml"
CNI_CMD="$CNI_DIR/apply.sh"

# ── Q4: cri-dockerd 를 설치할 워커. 19-node-ops 와 같은 방식으로 찾는다 ──
#   컨트롤플레인이 아닌 첫 노드. CRI_NODE=<이름> bash exam.sh start 로 직접 지정해도 된다.
CRI_NODE="${CRI_NODE:-$(kubectl get nodes --no-headers \
  -l '!node-role.kubernetes.io/control-plane' \
  -o custom-columns=:metadata.name 2>/dev/null | head -1 | tr -d ' ')}"
CRI_NODE="${CRI_NODE:-worker-1}"
CRI_VER="0.3.26"                          # ubuntu-noble(24.04) .deb 가 있는 0.3.x 버전
CRI_SYSCTL=/etc/sysctl.d/99-cri.conf      # 지문에서 지정하는 파일 — 정리할 때 이것만 지운다
CRI_KEYS="net.bridge.bridge-nf-call-iptables=1 net.ipv6.conf.all.forwarding=1 net.ipv4.ip_forward=1 net.netfilter.nf_conntrack_max=131072"

# 노드에 스크립트를 보내 bash 로 실행한다 (표준입력으로 넘기므로 따옴표 걱정이 없다).
#   이름으로 ssh → 안 되면 InternalIP 로 ssh. 둘 다 접속 실패면 255.
#   이 노드 자체에서 exam.sh 를 돌리는 경우에는 그냥 로컬에서 실행한다.
node_run() {
  local script="$1" host rc ip
  if [[ "$CRI_NODE" == "$(hostname -s 2>/dev/null)" ]]; then
    bash -s <<<"$script"; return $?
  fi
  ip=$(kubectl get node "$CRI_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
  for host in "$CRI_NODE" $ip; do
    ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" 'bash -s' <<<"$script" 2>/dev/null
    rc=$?
    (( rc != 255 )) && return $rc
  done
  return 255
}

# 이 클러스터의 파드 네트워크 CIDR — kubeadm-config 의 podSubnet, 없으면 controller-manager 의 --cluster-cidr
cluster_pod_cidr() {
  local c
  c=$(kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' 2>/dev/null \
      | awk '/^[[:space:]]*podSubnet:/{print $2; exit}')
  if [[ -z "$c" ]]; then
    c=$(kubectl -n kube-system get pods -l component=kube-controller-manager \
          -o jsonpath='{.items[0].spec.containers[0].command}' 2>/dev/null \
        | grep -oE 'cluster-cidr=[0-9a-fA-F.:/,]+' | head -1 | cut -d= -f2)
  fi
  c="${c%%,*}"; c="${c//[\"\' ]/}"
  echo "$c"
}

exam_cleanup() {
  rm -f /tmp/cni.txt /tmp/cni-install.sh          # 예전 Q3 답안 파일
  rm -f /tmp/coredns.log 2>/dev/null || true
  rm -rf "$CNI_DIR" 2>/dev/null || sudo -n rm -rf "$CNI_DIR" 2>/dev/null || true

  # Q4 — 패키지 제거 · 지문에서 지정한 sysctl 파일만 삭제 · 바꾼 값 되돌리기
  #   ip_forward 와 bridge-nf-call-iptables 는 클러스터가 쓰는 값이라 1 로 둔다.
  local out rc
  out=$(node_run "$(cat <<EOS
need=0
if dpkg-query -W cri-dockerd >/dev/null 2>&1; then
  sudo -n dpkg --purge cri-dockerd >/dev/null 2>&1 || need=1
fi
sudo -n systemctl reset-failed cri-docker.service cri-docker.socket >/dev/null 2>&1
sudo -n systemctl daemon-reload >/dev/null 2>&1
if [ -e $CRI_SYSCTL ]; then sudo -n rm -f $CRI_SYSCTL >/dev/null 2>&1 || need=1; fi
if [ -f ~/.cka13-sysctl-before ]; then
  v6=\$(grep '^ipv6fwd=' ~/.cka13-sysctl-before | cut -d= -f2 | tr -cd '0-9')
  ct=\$(grep '^ctmax=' ~/.cka13-sysctl-before | cut -d= -f2 | tr -cd '0-9')
  [ -n "\$v6" ] && { sudo -n sysctl -qw net.ipv6.conf.all.forwarding="\$v6" >/dev/null 2>&1 || need=1; }
  [ -n "\$ct" ] && { sudo -n sysctl -qw net.netfilter.nf_conntrack_max="\$ct" >/dev/null 2>&1 || need=1; }
  [ "\$need" = 0 ] && rm -f ~/.cka13-sysctl-before
fi
sudo -n sysctl -qw net.ipv4.ip_forward=1 net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1
rm -f ~/cri-dockerd_*.deb ~/cri-dockerd_*.deb.part
echo "need=\$need"
EOS
)")
  rc=$?
  echo "  /tmp/coredns.log · $CNI_DIR 삭제"
  if (( rc == 255 )); then
    echo "  ($CRI_NODE 에 ssh 하지 못해 Q4 정리를 건너뜁니다 — 노드에서 직접:"
    echo "   sudo dpkg --purge cri-dockerd; sudo rm -f $CRI_SYSCTL; sudo sysctl --system)"
  elif [[ "$out" == *need=1* ]]; then
    echo "  ($CRI_NODE 에서 sudo 에 비밀번호가 필요해 일부를 정리하지 못했습니다 — 노드에서 직접:"
    echo "   sudo dpkg --purge cri-dockerd; sudo rm -f $CRI_SYSCTL; sudo sysctl --system)"
  else
    echo "  $CRI_NODE: cri-dockerd 제거 · $CRI_SYSCTL 삭제 · sysctl 값 복구"
  fi
  echo "  (노드는 자동으로 제거하지 않는다 — 다시 조인 연습을 하려면"
  echo "   control-plane 에서 kubectl delete node worker-2,"
  echo "   worker-2 에서 sudo kubeadm reset -f 를 직접 실행한다)"
}

exam_setup() {
  # ── Q3: 작업 폴더. 인터넷이 안 되면 원본 사본을 offline/ 에 둔다
  mkdir -p "$CNI_DIR"
  if curl -fsSL --max-time 10 -o /dev/null "$CALICO_CR_URL" 2>/dev/null; then
    echo "  Q3  $CNI_DIR 준비 (매니페스트는 직접 내려받는다)"
  else
    mkdir -p "$CNI_DIR/offline"
    cat > "$CNI_DIR/offline/custom-resources.yaml" <<'YAML'
# This section includes base Calico installation configuration.
# For more information, see: https://docs.tigera.io/calico/latest/reference/installation/api#operator.tigera.io/v1.Installation
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  # Configures Calico networking.
  calicoNetwork:
    ipPools:
    - name: default-ipv4-ippool
      blockSize: 26
      cidr: 192.168.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()

---

# This section configures the Calico API server.
# For more information, see: https://docs.tigera.io/calico/latest/reference/installation/api#operator.tigera.io/v1.APIServer
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
YAML
    echo -e "  Q3  ${ORANGE}raw.githubusercontent.com 에 접속하지 못했습니다${RESET} — 원본 사본을 $CNI_DIR/offline/ 에 두었습니다"
  fi

  # ── Q4: 워커 홈 디렉터리에 cri-dockerd .deb 내려받기 + 바꾸기 전 sysctl 값 기록
  if ! kubectl get node "$CRI_NODE" &>/dev/null; then
    echo -e "  Q4  ${RED}노드 '$CRI_NODE' 를 찾을 수 없습니다.${RESET}"
    echo -e "      다시 실행: ${CYAN}CRI_NODE=<워커 이름> bash exam.sh start${RESET}"
    return 0
  fi
  local out rc
  out=$(node_run "$(cat <<EOS
V=$CRI_VER
arch=\$(dpkg --print-architecture 2>/dev/null); arch=\${arch:-amd64}
code=\$(. /etc/os-release 2>/dev/null; echo "\${VERSION_CODENAME:-noble}")
[ -f ~/.cka13-sysctl-before ] || {
  echo "ipv6fwd=\$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)"
  echo "ctmax=\$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null)"
} > ~/.cka13-sysctl-before
dpkg-query -W -f='\${Status}' cri-dockerd 2>/dev/null | grep -q 'ok installed' && echo "preinstalled=1"
f=\$(ls ~/cri-dockerd_*.deb 2>/dev/null | head -1)
if [ -n "\$f" ]; then echo "deb=\$f"; exit 0; fi
for c in "\$code" jammy; do
  f="cri-dockerd_\${V}.3-0.ubuntu-\${c}_\${arch}.deb"
  if curl -fsSL --max-time 180 -o ~/"\$f.part" "https://github.com/Mirantis/cri-dockerd/releases/download/v\${V}/\$f"; then
    mv ~/"\$f.part" ~/"\$f"; echo "deb=\$HOME/\$f"; exit 0
  fi
  rm -f ~/"\$f.part"
done
echo "url=https://github.com/Mirantis/cri-dockerd/releases/download/v\${V}/cri-dockerd_\${V}.3-0.ubuntu-\${code}_\${arch}.deb"
exit 3
EOS
)")
  rc=$?
  if (( rc == 255 )); then
    echo -e "  Q4  ${RED}$CRI_NODE 에 ssh 하지 못했습니다${RESET} (control-plane → $CRI_NODE 비밀번호 없는 ssh 필요)"
    echo "      $CRI_NODE 에 들어가 홈 디렉터리에서 직접 내려받으세요:"
    echo "      curl -LO https://github.com/Mirantis/cri-dockerd/releases/download/v$CRI_VER/cri-dockerd_$CRI_VER.3-0.ubuntu-noble_amd64.deb"
    echo "      (arm64 VM 이면 파일 이름 끝을 _arm64.deb 로)"
  elif (( rc != 0 )); then
    echo -e "  Q4  ${RED}$CRI_NODE 에서 cri-dockerd .deb 를 내려받지 못했습니다${RESET} (GitHub 접속 확인)"
    echo "      $CRI_NODE 에서 직접:  cd ~ && curl -LO $(grep '^url=' <<<"$out" | cut -d= -f2-)"
  else
    echo "  Q4  $CRI_NODE:$(grep '^deb=' <<<"$out" | cut -d= -f2-) 준비"
  fi
  if [[ "$out" == *preinstalled=1* ]]; then
    echo -e "  Q4  ${ORANGE}$CRI_NODE 에 cri-dockerd 가 이미 설치돼 있습니다${RESET} — 직접 sudo dpkg --purge cri-dockerd 후 다시 start 하세요"
  fi
  return 0
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Join the worker node to the cluster"; }
q1_text() { cat <<'EOF'
Join the node worker-2 (192.168.56.12) to the cluster.

  - on the control plane, print a fresh join command with
    kubeadm token create --print-join-command
  - run that command on worker-2 with sudo
  - the node must reach Ready state and run the same minor version as the
    other nodes

Verify:
  kubectl get nodes -o wide
EOF
}
q1_title_ko() { echo "워커 노드를 클러스터에 조인"; }
q1_text_ko() { cat <<'EOF'
worker-2(192.168.56.12) 노드를 클러스터에 조인시키시오.

  - control-plane 에서 kubeadm token create --print-join-command 로
    조인 명령을 새로 뽑는다
  - 그 명령을 worker-2 에서 sudo 로 실행한다
  - 노드가 Ready 가 되고, 다른 노드와 같은 마이너 버전이어야 한다

[확인]
  kubectl get nodes -o wide
EOF
}
q1_grade() {
  check "worker-2 노드가 클러스터에 있다" "kubectl get node worker-2"
  check_output "worker-2 가 Ready" \
    "kubectl get node worker-2 --no-headers" '\sReady\s'
  check_output "kubelet 버전이 v1.x 로 보고된다" \
    "kubectl get node worker-2 --no-headers -o wide" 'v1\.'
  check_output "control-plane 과 같은 마이너 버전" \
    "kubectl get nodes --no-headers -o custom-columns=V:.status.nodeInfo.kubeletVersion | sed 's/\.[0-9]*$//' | sort -u | wc -l" '^\s*1$'
}
q1_hint() { cat <<'EOF'
# control-plane 에서
kubeadm token create --print-join-command

# worker-2 에서 (위 출력을 그대로, sudo 를 붙여서)
sudo kubeadm join 192.168.56.10:6443 --token ... --discovery-token-ca-cert-hash sha256:...

# 이미 조인했다가 다시 하려면 worker-2 에서
sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Collect container logs with crictl"; }
q2_text() { cat <<'EOF'
On the control plane node, use crictl (not kubectl) to save the log of a
running coredns container to /tmp/coredns.log.

  - find the container id with crictl ps
  - write the log of that container into /tmp/coredns.log
  - the file must not be empty

Verify:
  ls -l /tmp/coredns.log
  head /tmp/coredns.log
EOF
}
q2_title_ko() { echo "crictl 로 컨테이너 로그 수집"; }
q2_text_ko() { cat <<'EOF'
control-plane 노드에서 kubectl 이 아니라 crictl 을 사용해
실행 중인 coredns 컨테이너의 로그를 /tmp/coredns.log 에 저장하시오.

  - crictl ps 로 컨테이너 ID 를 찾는다
  - 그 컨테이너의 로그를 /tmp/coredns.log 에 쓴다
  - 파일이 비어 있으면 안 된다

[확인]
  ls -l /tmp/coredns.log
  head /tmp/coredns.log
EOF
}
q2_grade() {
  check "/tmp/coredns.log 파일 존재" "test -f /tmp/coredns.log"
  check "/tmp/coredns.log 가 비어 있지 않다" "test -s /tmp/coredns.log"
  check_output "CoreDNS 로그 내용으로 보인다" \
    "cat /tmp/coredns.log 2>/dev/null | head -50" 'CoreDNS|coredns|plugin|linux/amd64'
}
q2_hint() { cat <<'EOF'
sudo crictl ps | grep coredns          # 컨테이너 ID 확인 (맨 앞 열)
sudo crictl logs <컨테이너ID> > /tmp/coredns.log 2>&1

# 한 줄로
sudo crictl logs "$(sudo crictl ps -q --name coredns | head -1)" > /tmp/coredns.log 2>&1
EOF
}

# ══════════════════════════════════════════════════════════════
# Q3 — 문서의 매니페스트를 그대로 쓸 수 없을 때: 내려받아 cidr 를 클러스터 값으로 고친다
#   실제 시험 유형: 문서의 kubectl create -f <custom-resources URL> 이 맞지 않아
#   파일로 받아서 cidr 를 노드/kubeadm-config 에서 찾은 값으로 바꾼 뒤 적용.
#   이 클러스터에는 이미 Cilium 이 있으므로 적용은 하지 않고 파일만 채점한다.
q3_title() { echo "Fix a CNI manifest to match the cluster's pod CIDR"; }
q3_text() { cat <<EOF
The Calico (Tigera operator) install guide tells you to run

  kubectl create -f $CALICO_CR_URL

That manifest cannot be used as-is on this cluster: its IP pool uses the
default cidr 192.168.0.0/16, which is not the pod network CIDR this cluster
was created with.

  1) download the manifest to  $CNI_FILE
  2) in the Installation resource, set the IP pool cidr to this cluster's
     pod network CIDR. Find the value in the cluster (kubeadm configuration
     or node spec) — do not guess. Keep the rest of the file as it is.
  3) write the single kubectl command that would apply YOUR edited file
     into  $CNI_CMD

Do NOT apply it — this cluster already runs a CNI and the Tigera operator
is not installed. (If the download fails, a copy of the original file is
in $CNI_DIR/offline/.)

Verify:
  grep -n cidr $CNI_FILE
  cat $CNI_CMD
EOF
}
q3_title_ko() { echo "CNI 매니페스트 cidr 를 클러스터 값으로 고치기"; }
q3_text_ko() { cat <<EOF
Calico(Tigera operator) 설치 문서는 다음 명령을 실행하라고 안내한다.

  kubectl create -f $CALICO_CR_URL

이 매니페스트는 이 클러스터에 그대로 쓸 수 없다. IP 풀의 cidr 가 기본값
192.168.0.0/16 이라 이 클러스터를 만들 때 정한 파드 네트워크 CIDR 와 다르다.

  1) 매니페스트를  $CNI_FILE  로 내려받는다
  2) Installation 리소스의 IP 풀 cidr 를 이 클러스터의 파드 네트워크 CIDR 로
     바꾼다. 값은 클러스터에서 찾는다(kubeadm 설정 또는 노드 spec) — 추측하지
     않는다. 나머지 내용은 그대로 둔다.
  3) 고친 파일을 적용하는 kubectl 명령 한 줄을  $CNI_CMD  에 적는다

적용하지는 않는다 — 이 클러스터에는 이미 CNI 가 있고 Tigera operator 도
설치되어 있지 않다. (내려받기가 안 되면 원본 사본이 $CNI_DIR/offline/ 에 있다.)

[확인]
  grep -n cidr $CNI_FILE
  cat $CNI_CMD
EOF
}

# 고친 파일을 읽어 key=value 줄로 요약한다 — parse=ok|bad|noparser|missing · kind=… · api.<kind>=… · cidr=…
#   python3 + PyYAML 이 있으면 진짜 YAML 로 읽고, 없으면 grep 으로 최소한만 본다.
cr_inspect() {
  local f="$1"
  [[ -s "$f" ]] || { echo "parse=missing"; return; }
  if command -v python3 &>/dev/null && python3 -c 'import yaml' &>/dev/null; then
    python3 - "$f" <<'PY' 2>/dev/null || echo "parse=bad"
import sys, yaml
try:
    docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d is not None]
except Exception:
    print("parse=bad"); sys.exit(0)
print("parse=ok")
for d in docs:
    if not isinstance(d, dict):
        continue
    print("kind=%s" % d.get("kind"))
    print("api.%s=%s" % (d.get("kind"), d.get("apiVersion")))
    if d.get("kind") == "Installation":
        pools = (((d.get("spec") or {}).get("calicoNetwork") or {}).get("ipPools")) or []
        for p in pools:
            if isinstance(p, dict):
                print("cidr=%s" % p.get("cidr"))
PY
  else
    # 파서가 없을 때: 들여쓰기에 탭이 있으면 YAML 이 아니다. 나머지는 줄 단위로만 본다
    if grep -q $'^[[:space:]]*\t' "$f"; then echo "parse=bad"; else echo "parse=noparser"; fi
    grep -E '^kind:' "$f" | awk '{print "kind="$2}'
    grep -qE '^apiVersion:[[:space:]]*operator\.tigera\.io/v1[[:space:]]*$' "$f" \
      && echo "api.Installation=operator.tigera.io/v1"
    grep -E '^[[:space:]-]*cidr:' "$f" | awk -F'cidr:' '{gsub(/[ "'\''\r]/,"",$2); print "cidr="$2}'
  fi
}

q3_grade() {
  local want info parse cidrs n bad
  want=$(cluster_pod_cidr)
  info=$(cr_inspect "$CNI_FILE")
  parse=$(grep '^parse=' <<<"$info" | head -1 | cut -d= -f2)
  cidrs=$(grep '^cidr=' <<<"$info" | cut -d= -f2- | tr '\n' ' ')
  n=$(grep -c '^cidr=' <<<"$info"); n="${n//[^0-9]/}"; n="${n:-0}"
  bad=$(grep '^cidr=' <<<"$info" | cut -d= -f2- | grep -vxF "${want:-__none__}" | head -1)

  check "$CNI_FILE 이 있다" "test -s $CNI_FILE"
  check_result "YAML 로 읽힌다" \
    "$([[ "$parse" == ok || "$parse" == noparser ]] && echo 0 || echo 1)" \
    "$([[ "$parse" == missing ]] && echo "파일 없음" || echo "YAML 파싱 실패 — 들여쓰기(탭)·콜론 확인")"
  check_result "Installation 리소스(operator.tigera.io/v1)가 남아 있다" \
    "$(grep -qx 'kind=Installation' <<<"$info" && grep -qx 'api.Installation=operator.tigera.io/v1' <<<"$info" && echo 0 || echo 1)" \
    "kind: Installation / apiVersion: operator.tigera.io/v1 문서를 지우거나 바꾸지 않는다"
  check_result "IP 풀 cidr 가 클러스터의 파드 CIDR 와 같다" \
    "$([[ -n "$want" && "$n" -ge 1 && -z "$bad" ]] && echo 0 || echo 1)" \
    "클러스터: ${want:-찾지 못함} / 파일: ${cidrs:-cidr 없음}"
  check "$CNI_CMD 이 있다" "test -s $CNI_CMD"
  check_output "고친 로컬 파일을 kubectl 로 적용하는 명령이다" \
    "grep -v '^[[:space:]]*#' $CNI_CMD 2>/dev/null" \
    'kubectl[[:space:]]+(create|apply)[[:space:]].*-f[[:space:]=]*(/tmp/calico/|\./)?custom-resources\.yaml'
}
q3_hint() { cat <<'EOF'
# 1) 이 클러스터의 파드 CIDR — kubeadm init 때 준 --pod-network-cidr
kubectl -n kube-system get cm kubeadm-config -o yaml | grep podSubnet
#    노드에 나눠 준 조각으로도 짐작할 수 있다 (노드마다 /24, 전체는 그보다 넓다)
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'

# 2) 내려받아서 고친다
mkdir -p /tmp/calico && cd /tmp/calico
curl -LO https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/custom-resources.yaml
#   (wget 도 된다. 인터넷이 안 되면: cp /tmp/calico/offline/custom-resources.yaml .)
vi custom-resources.yaml          # cidr: 192.168.0.0/16 → podSubnet 값
grep -n cidr custom-resources.yaml

# 3) 적용 명령은 파일로만 (실행하지 않는다)
echo 'kubectl create -f /tmp/calico/custom-resources.yaml' > /tmp/calico/apply.sh

# 실제로는 operator(tigera-operator.yaml) 를 먼저 create 해야 Installation 종류가 생긴다.
# operator 없이 이 파일을 적용하면: no matches for kind "Installation" in version "operator.tigera.io/v1"
EOF
}

# ══════════════════════════════════════════════════════════════
# Q4 — CRI 패키지 설치: dpkg -i · systemctl enable --now · sysctl 영구 설정
#   이 클러스터의 노드에는 Docker 엔진이 없어서 cri-docker 서비스가 active 로 유지되지 못한다.
#   그래서 active 는 채점하지 않고 '설치됨 · enabled · sysctl 값/파일' 만 본다.
#   kubelet 은 계속 containerd 를 쓰므로 노드는 Ready 여야 한다.
q4_title() { echo "Install a CRI package and persist kernel parameters"; }
q4_text() { cat <<EOF
Prepare node $CRI_NODE so it could use cri-dockerd (Docker Engine's CRI shim).
The package has already been downloaded to the home directory on that node:

  ssh $CRI_NODE
  ls ~/cri-dockerd_*.deb

  1) install the package with dpkg
  2) enable and start the systemd service cri-docker.service
  3) set the following kernel parameters, persist them in the file
     $CRI_SYSCTL so they survive a reboot, and apply them now:

       net.bridge.bridge-nf-call-iptables = 1
       net.ipv6.conf.all.forwarding       = 1
       net.ipv4.ip_forward                = 1
       net.netfilter.nf_conntrack_max     = 131072

Note: this lab node has no Docker Engine, so cri-docker.service cannot stay
active (starting it fails or keeps restarting) — that is expected here and is
not graded. It must be installed and enabled. Do not change the runtime the
kubelet uses: $CRI_NODE must stay Ready.

Verify (on $CRI_NODE):
  dpkg -s cri-dockerd | grep Status
  systemctl is-enabled cri-docker.service
  sysctl net.ipv4.ip_forward net.netfilter.nf_conntrack_max
EOF
}
q4_title_ko() { echo "CRI 패키지 설치와 커널 파라미터 영구 설정"; }
q4_text_ko() { cat <<EOF
$CRI_NODE 노드가 cri-dockerd(Docker 엔진용 CRI 어댑터)를 쓸 수 있도록 준비하시오.
패키지 파일은 그 노드의 홈 디렉터리에 이미 내려받아 두었다.

  ssh $CRI_NODE
  ls ~/cri-dockerd_*.deb

  1) dpkg 로 패키지를 설치한다
  2) systemd 서비스 cri-docker.service 를 enable 하고 시작한다
  3) 아래 커널 파라미터를 재부팅 뒤에도 유지되도록 $CRI_SYSCTL 파일에
     적고, 지금 바로 적용한다

       net.bridge.bridge-nf-call-iptables = 1
       net.ipv6.conf.all.forwarding       = 1
       net.ipv4.ip_forward                = 1
       net.netfilter.nf_conntrack_max     = 131072

참고: 이 실습 노드에는 Docker 엔진이 없어서 cri-docker.service 가 active 로
유지되지 못한다(시작이 실패하거나 재시작을 반복). 여기서는 정상이며 채점하지
않는다. 설치되어 있고 enabled 여야 한다. kubelet 이 쓰는 런타임은 바꾸지 않는다
— $CRI_NODE 는 계속 Ready 여야 한다.

[확인] ($CRI_NODE 에서)
  dpkg -s cri-dockerd | grep Status
  systemctl is-enabled cri-docker.service
  sysctl net.ipv4.ip_forward net.netfilter.nf_conntrack_max
EOF
}

q4_grade() {
  # 노드에 한 번만 ssh 해서 key=value 로 모아 온다 (줄 순서가 아니라 이름으로 읽는다)
  local out rc
  out=$(node_run "$(cat <<EOS
echo "pkg=\$(dpkg-query -W -f='\${Status}' cri-dockerd 2>/dev/null)"
echo "svc=\$(systemctl is-enabled cri-docker.service 2>/dev/null)"
for kv in $CRI_KEYS; do
  k=\${kv%%=*}
  echo "live.\$k=\$(sysctl -n \$k 2>/dev/null)"
  echo "file.\$k=\$(grep -E "^[[:space:]]*\$k[[:space:]]*=" $CRI_SYSCTL 2>/dev/null | tail -1 | cut -d= -f2 | tr -d ' \t\r')"
done
echo "file=\$([ -f $CRI_SYSCTL ] && echo yes || echo no)"
EOS
)")
  rc=$?
  local ssh_note=""
  (( rc == 255 )) && ssh_note="채점기가 $CRI_NODE 에 ssh 하지 못했다 — control-plane 에서 ssh $CRI_NODE 가 비밀번호 없이 되는지 확인 (CRI_NODE=<노드> 로 지정 가능)"

  local pkg svc file live_bad="" file_bad="" kv want got
  pkg=$(grep -E '^pkg=' <<<"$out" | head -1 | cut -d= -f2-)
  svc=$(grep -E '^svc=' <<<"$out" | head -1 | cut -d= -f2-)
  file=$(grep -E '^file=' <<<"$out" | head -1 | cut -d= -f2-)
  for kv in $CRI_KEYS; do
    want="${kv#*=}"; kv="${kv%%=*}"
    got=$(grep -F "live.$kv=" <<<"$out" | head -1 | cut -d= -f2-); got="${got//[^0-9]/}"
    [[ "$got" == "$want" ]] || live_bad+="$kv=${got:-?} "
    got=$(grep -F "file.$kv=" <<<"$out" | head -1 | cut -d= -f2-); got="${got//[^0-9]/}"
    [[ "$got" == "$want" ]] || file_bad+="$kv=${got:-없음} "
  done

  check_result "cri-dockerd 패키지가 설치됐다 (dpkg: install ok installed)" \
    "$([[ "$pkg" == "install ok installed" ]] && echo 0 || echo 1)" \
    "${ssh_note:-dpkg 상태: ${pkg:-설치 안 됨} — 의존성 오류로 unpacked 에 멈췄다면 sudo apt-get install -f}"
  check_result "cri-docker.service 가 enabled" \
    "$([[ "$svc" == "enabled" ]] && echo 0 || echo 1)" \
    "${ssh_note:-is-enabled: ${svc:-유닛 없음}}"
  check_result "커널 파라미터 4개가 지금 적용돼 있다" \
    "$([[ $rc -ne 255 && -z "$live_bad" ]] && echo 0 || echo 1)" \
    "${ssh_note:-다른 값: ${live_bad}— sudo sysctl --system 또는 sudo sysctl -p $CRI_SYSCTL}"
  check_result "$CRI_SYSCTL 에 4개가 모두 적혀 있다 (영구)" \
    "$([[ "$file" == yes && -z "$file_bad" ]] && echo 0 || echo 1)" \
    "${ssh_note:-$([[ "$file" == yes ]] && echo "빠지거나 다른 값: $file_bad" || echo "$CRI_SYSCTL 파일이 없다")}"
  check_output "$CRI_NODE 는 여전히 Ready (kubelet 런타임은 그대로)" \
    "kubectl get node $CRI_NODE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" '^True$'
}
q4_hint() { cat <<'EOF'
ssh <노드>                                  # 지문의 노드
ls ~/cri-dockerd_*.deb

# 1) 설치 — dpkg 는 의존성을 받아 오지 않는다. 의존성 오류가 나면 apt 로 채운다
sudo dpkg -i ~/cri-dockerd_*.deb
#   (오류 시) sudo apt-get install -f -y
dpkg -s cri-dockerd | grep Status          # Status: install ok installed

# 2) 서비스 — 이름은 cri-docker (패키지 이름 cri-dockerd 와 다르다)
systemctl list-unit-files 'cri-docker*'
sudo systemctl enable --now cri-docker.service
#   Docker 엔진이 없는 노드라 start 는 실패한다 — 이 실습에서는 정상
systemctl is-enabled cri-docker.service    # enabled

# 3) sysctl — 파일에 쓰고 바로 적용
cat <<'CONF' | sudo tee /etc/sysctl.d/99-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.ip_forward = 1
net.netfilter.nf_conntrack_max = 131072
CONF
sudo sysctl --system                       # 또는 sudo sysctl -p /etc/sysctl.d/99-cri.conf
sysctl net.bridge.bridge-nf-call-iptables net.ipv6.conf.all.forwarding \
       net.ipv4.ip_forward net.netfilter.nf_conntrack_max

exit                                       # control-plane 으로 돌아와서 채점
EOF
}

exam_main "$@"
