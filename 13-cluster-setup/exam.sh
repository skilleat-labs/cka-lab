#!/usr/bin/env bash
# CKA 13강 실습 — 클러스터 구축과 노드 조인 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 13강 실습 — 클러스터 구축 · 노드 조인"
EXAM_NQ=3

exam_cleanup() {
  rm -f /tmp/cni.txt /tmp/cni-install.sh
  echo "  (노드는 자동으로 제거하지 않는다 — 다시 조인 연습을 하려면"
  echo "   control-plane 에서 kubectl delete node worker-2,"
  echo "   worker-2 에서 sudo kubeadm reset -f 를 직접 실행한다)"
  rm -f /tmp/coredns.log 2>/dev/null || true
}
exam_setup() { echo "  (미리 만들어둘 것 없음)"; }

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
q3_title() { echo "Identify the CNI and write the install command"; }
q3_text() { cat <<'EOF'
After kubeadm init the nodes stay NotReady until a CNI plugin is installed.

  1) find which CNI plugin this cluster uses and write its name
     to /tmp/cni.txt  (one word, lowercase — e.g. calico / cilium / flannel)

  2) write to /tmp/cni-install.sh the command that installs a CNI
     on a fresh cluster. It must be a single kubectl or helm command
     and must reference a manifest URL or a chart.

Do NOT run the install command — the cluster already has a CNI.

Verify:
  cat /tmp/cni.txt
  cat /tmp/cni-install.sh
EOF
}
q3_title_ko() { echo "CNI 확인하고 설치 명령 적기"; }
q3_text_ko() { cat <<'EOF'
kubeadm init 만 하면 노드는 NotReady 다. CNI 를 깔아야 Ready 가 된다.

  1) 이 클러스터가 어떤 CNI 를 쓰는지 알아내어 이름을 /tmp/cni.txt 에
     적는다 (소문자 한 단어 — 예: calico / cilium / flannel)

  2) 새 클러스터에 CNI 를 설치하는 명령을 /tmp/cni-install.sh 에 적는다
     kubectl 또는 helm 한 줄이어야 하고, 매니페스트 URL 이나 차트를
     가리켜야 한다.

설치 명령을 실행하지는 않는다 — 이 클러스터에는 이미 CNI 가 있다.

[확인]
  cat /tmp/cni.txt
  cat /tmp/cni-install.sh
EOF
}
q3_grade() {
  check "/tmp/cni.txt 가 있다" "test -s /tmp/cni.txt"
  # 실제로 돌고 있는 CNI 를 찾아 대조한다
  local actual
  actual=$(kubectl -n kube-system get pods -o name 2>/dev/null \
    | grep -oiE 'cilium|calico|flannel|weave|canal' | head -1 | tr 'A-Z' 'a-z')
  local wrote; wrote=$(tr 'A-Z' 'a-z' < /tmp/cni.txt 2>/dev/null | tr -d ' \n')
  check_result "이 클러스터의 CNI 이름이 맞다" \
    "$([[ -n "$actual" && "$wrote" == *"$actual"* ]] && echo 0 || echo 1)" \
    "실제: ${actual:-찾지 못함} / 적어낸 값: ${wrote:-비어 있음}"
  check "/tmp/cni-install.sh 가 있다" "test -s /tmp/cni-install.sh"
  check_output "kubectl apply 또는 helm install 이다" \
    "cat /tmp/cni-install.sh 2>/dev/null" 'kubectl apply|helm (install|upgrade)|cilium install'
  check_output "매니페스트 URL 이나 차트를 가리킨다" \
    "cat /tmp/cni-install.sh 2>/dev/null" 'https?://|[a-z-]+/[a-z-]+'
}
q3_hint() { cat <<'EOF'
# 어떤 CNI 가 도는지는 kube-system 파드를 보면 안다
kubectl -n kube-system get pods
#   cilium-xxxxx · cilium-operator-...   → cilium
#   calico-node-xxxxx                    → calico

# 노드의 CNI 설정 파일로도 확인된다
ls /etc/cni/net.d/

echo cilium > /tmp/cni.txt

# 설치 명령 예시 (실행하지 않는다 — 파일로만)
cat > /tmp/cni-install.sh <<'SH'
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
SH

# 시험에서는 "노드가 NotReady 다" 로 나오는 경우가 많다.
# describe node 의 Conditions 에 network plugin is not ready 가 보이면 CNI 가 없는 것이다.
EOF
}

exam_main "$@"
