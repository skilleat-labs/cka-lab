#!/usr/bin/env bash
# CKA 1강 실습 — 아키텍처 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 1강 실습 — 아키텍처 (컨트롤플레인 · 노드 · 선언적 관리)"
EXAM_NQ=4

exam_cleanup() {
  kdel deployment arch-demo -n default
  rm -f /tmp/control-plane.txt /tmp/etcd-endpoint.txt /tmp/node-runtime.txt /tmp/selfheal.txt
  echo "  arch-demo 및 /tmp 답안 파일 삭제"
}
exam_setup() { echo "  (미리 만들어둘 것 없음)"; }

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Control plane components"; }
q1_text() { cat <<'EOF'
The control plane runs as static Pods in the kube-system namespace.

List the names of the control plane Pods running on the control plane node
and save them to /tmp/control-plane.txt, one name per line.

The file must contain the Pods for etcd, kube-apiserver,
kube-controller-manager and kube-scheduler.

Verify:
  cat /tmp/control-plane.txt
EOF
}
q1_title_ko() { echo "컨트롤플레인 구성 요소"; }
q1_text_ko() { cat <<'EOF'
컨트롤플레인은 kube-system 네임스페이스에 스태틱 파드로 떠 있다.

컨트롤플레인 노드에서 돌고 있는 컨트롤플레인 파드의 이름을
/tmp/control-plane.txt 에 한 줄에 하나씩 저장한다.

etcd · kube-apiserver · kube-controller-manager · kube-scheduler
네 가지가 모두 들어 있어야 한다.

[확인]
  cat /tmp/control-plane.txt
EOF
}
q1_grade() {
  check "/tmp/control-plane.txt 가 있다" "test -s /tmp/control-plane.txt"
  check_output "etcd 가 들어 있다"                   "cat /tmp/control-plane.txt" 'etcd'
  check_output "kube-apiserver 가 들어 있다"          "cat /tmp/control-plane.txt" 'kube-apiserver'
  check_output "kube-controller-manager 가 들어 있다" "cat /tmp/control-plane.txt" 'kube-controller-manager'
  check_output "kube-scheduler 가 들어 있다"          "cat /tmp/control-plane.txt" 'kube-scheduler'
}
q1_hint() { cat <<'EOF'
kubectl get pods -n kube-system -o name | grep -E 'etcd|apiserver|controller-manager|scheduler'

# 이름만 남기려면
kubectl get pods -n kube-system --no-headers -o custom-columns=:metadata.name \
  | grep -E 'etcd|apiserver|controller-manager|scheduler' > /tmp/control-plane.txt
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Where the API server keeps its state"; }
q2_text() { cat <<'EOF'
The API server is the only component that talks to etcd.

Find the value of the --etcd-servers flag that kube-apiserver was started with,
and save just that value to /tmp/etcd-endpoint.txt

Example of what the file should look like:
  https://127.0.0.1:2379

Verify:
  cat /tmp/etcd-endpoint.txt
EOF
}
q2_title_ko() { echo "API 서버는 상태를 어디에 두는가"; }
q2_text_ko() { cat <<'EOF'
etcd 와 직접 이야기하는 것은 API 서버뿐이다.

kube-apiserver 가 어떤 --etcd-servers 값으로 떠 있는지 찾아서
그 값만 /tmp/etcd-endpoint.txt 에 저장한다.

파일 내용 예시:
  https://127.0.0.1:2379

[확인]
  cat /tmp/etcd-endpoint.txt
EOF
}
q2_grade() {
  check "/tmp/etcd-endpoint.txt 가 있다" "test -s /tmp/etcd-endpoint.txt"
  check_output "etcd 주소 형태다 (https://호스트:2379)" "cat /tmp/etcd-endpoint.txt" 'https://.*:2379'
  local want actual
  want=$(kubectl -n kube-system get pod -l component=kube-apiserver \
          -o jsonpath='{.items[0].spec.containers[0].command}' 2>/dev/null \
        | tr ',' '\n' | grep -o 'https://[^"]*:2379' | head -1)
  actual=$(tr -d ' \n' < /tmp/etcd-endpoint.txt 2>/dev/null)
  check_result "실제 kube-apiserver 의 값과 같다" \
    "$([[ -n "$want" && "$actual" == *"${want}"* ]] && echo 0 || echo 1)" \
    "실제 값: ${want:-찾지 못함} / 적어낸 값: ${actual:-비어 있음}"
}
q2_hint() { cat <<'EOF'
# 스태틱 파드의 매니페스트에 그대로 적혀 있다
sudo grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml

# kubectl 로도 볼 수 있다
kubectl -n kube-system describe pod -l component=kube-apiserver | grep etcd-servers
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "What each node runs"; }
q3_text() { cat <<'EOF'
Every node runs a kubelet and a container runtime.

For each node in the cluster, write one line to /tmp/node-runtime.txt
in this format (space separated):

  <node-name> <kubelet-version> <container-runtime>

Example:
  control-plane v1.32.13 containerd://1.7.27

Verify:
  cat /tmp/node-runtime.txt
EOF
}
q3_title_ko() { echo "노드마다 무엇이 돌고 있나"; }
q3_text_ko() { cat <<'EOF'
모든 노드에는 kubelet 과 컨테이너 런타임이 돌고 있다.

클러스터의 각 노드에 대해 아래 형식으로 한 줄씩
/tmp/node-runtime.txt 에 저장한다 (공백으로 구분).

  <노드이름> <kubelet버전> <컨테이너런타임>

예시:
  control-plane v1.32.13 containerd://1.7.27

[확인]
  cat /tmp/node-runtime.txt
EOF
}
q3_grade() {
  check "/tmp/node-runtime.txt 가 있다" "test -s /tmp/node-runtime.txt"
  local nodes lines
  nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  lines=$(grep -c . /tmp/node-runtime.txt 2>/dev/null || echo 0)
  lines="${lines//[^0-9]/}"; lines="${lines:-0}"
  check_result "노드 수만큼 줄이 있다" \
    "$([[ "$nodes" -gt 0 && "$lines" == "$nodes" ]] && echo 0 || echo 1)" \
    "노드 ${nodes}개 / 파일 ${lines}줄"
  check_output "kubelet 버전이 들어 있다"  "cat /tmp/node-runtime.txt" 'v1\.[0-9]+'
  check_output "컨테이너 런타임이 들어 있다" "cat /tmp/node-runtime.txt" '://'
}
q3_hint() { cat <<'EOF'
kubectl get nodes -o wide            # 눈으로 먼저 확인

kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,VER:.status.nodeInfo.kubeletVersion,RT:.status.nodeInfo.containerRuntimeVersion' \
  --no-headers > /tmp/node-runtime.txt
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Declarative model — the cluster fixes itself"; }
q4_text() { cat <<'EOF'
Kubernetes keeps the actual state matching the desired state.

  1) create a Deployment named arch-demo in the default namespace
     image      nginx:1.24
     replicas   3

  2) delete ONE of its Pods

  3) after the cluster recreates it, confirm there are still 3 Pods
     and write the word  recreated  into /tmp/selfheal.txt

Verify:
  kubectl get pods -l app=arch-demo
  cat /tmp/selfheal.txt
EOF
}
q4_title_ko() { echo "선언적 모델 — 클러스터가 스스로 되돌린다"; }
q4_text_ko() { cat <<'EOF'
쿠버네티스는 실제 상태를 원하는 상태에 계속 맞춘다.

  1) default 네임스페이스에 arch-demo Deployment 를 만든다
     이미지      nginx:1.24
     레플리카    3

  2) 그 파드 중 하나를 삭제한다

  3) 클러스터가 다시 만들어 파드가 3개로 돌아오면
     /tmp/selfheal.txt 에  recreated  라고 적는다

[확인]
  kubectl get pods -l app=arch-demo
  cat /tmp/selfheal.txt
EOF
}
q4_grade() {
  check "Deployment arch-demo 존재" "kubectl get deployment arch-demo -n default"
  check_output "레플리카 3" "kubectl get deployment arch-demo -n default -o jsonpath='{.spec.replicas}'" '^3$'
  check_output "이미지 nginx:1.24" \
    "kubectl get deployment arch-demo -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" '^nginx:1\.24$'
  wait_ready "-l app=arch-demo" default
  check_output "파드 3개가 Ready" \
    "kubectl get deployment arch-demo -n default -o jsonpath='{.status.readyReplicas}'" '^3$'
  check_output "/tmp/selfheal.txt 에 recreated" "cat /tmp/selfheal.txt 2>/dev/null" 'recreated'
}
q4_hint() { cat <<'EOF'
kubectl create deployment arch-demo --image=nginx:1.24 --replicas=3

kubectl get pods -l app=arch-demo
kubectl delete pod <그중 하나>          # 지우자마자 새 파드가 생긴다
kubectl get pods -l app=arch-demo -w    # 3개로 돌아오는 것을 본다

echo recreated > /tmp/selfheal.txt
EOF
}

exam_main "$@"
