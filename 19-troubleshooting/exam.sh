#!/usr/bin/env bash
# CKA 11강 실습 — 트러블슈팅 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 11강 실습 — 트러블슈팅 (CrashLoop · ImagePull · Endpoints · 노드)"
EXAM_NQ=4

exam_cleanup() {
  kdel pod broken-pod fixed-pod pull-fail -n default
  kdel deployment target-app -n default
  kdel service target-svc -n default
  echo "  broken-pod / fixed-pod / pull-fail / target-app / target-svc 삭제"
}
exam_setup() {
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: broken-pod
  namespace: default
spec:
  containers:
  - name: app
    image: nginx:1.24
    command: ["invalid-command"]
YAML
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: pull-fail
  namespace: default
spec:
  containers:
  - name: app
    image: nginx:nonexistent-tag-xyz-9999
YAML
  kubectl create deployment target-app --image=nginx:1.24 --replicas=2 -n default &>/dev/null || true
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Service
metadata:
  name: target-svc
  namespace: default
spec:
  selector:
    app: WRONG-LABEL
  ports:
  - port: 80
    targetPort: 80
YAML
  echo "  고장난 리소스 3종을 만들었다: broken-pod(CrashLoop) · pull-fail(ImagePull) · target-svc(빈 Endpoints)"
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Diagnose a CrashLoopBackOff Pod"; }
q1_text() { cat <<'EOF'
The Pod broken-pod in the default namespace is in CrashLoopBackOff.

  1) find the cause (the events and the previous container log tell you)
  2) create a working Pod named fixed-pod with image nginx:1.24 that runs
     correctly

Leave broken-pod in place — it is the evidence.

Useful commands:
  kubectl describe pod broken-pod
  kubectl logs broken-pod --previous

Verify:
  kubectl get pod fixed-pod        -> Running
EOF
}
q1_title_ko() { echo "CrashLoopBackOff 진단"; }
q1_text_ko() { cat <<'EOF'
default 네임스페이스의 broken-pod 가 CrashLoopBackOff 상태다.

  1) 원인을 찾는다 (Events 와 이전 컨테이너 로그에 나온다)
  2) 정상 동작하는 fixed-pod 를 nginx:1.24 이미지로 만든다

broken-pod 는 증거이므로 그대로 둔다.

[진단]
  kubectl describe pod broken-pod
  kubectl logs broken-pod --previous

[확인]
  kubectl get pod fixed-pod        → Running
EOF
}
q1_grade() {
  check "fixed-pod 존재" "kubectl get pod fixed-pod -n default"
  wait_ready "fixed-pod" default
  check_output "fixed-pod Running" "kubectl get pod fixed-pod -n default -o jsonpath='{.status.phase}'" '^Running$'
  check_output "이미지 nginx:1.24" \
    "kubectl get pod fixed-pod -n default -o jsonpath='{.spec.containers[0].image}'" '^nginx:1\.24$'
  check_output "재시작 없이 안정적" \
    "kubectl get pod fixed-pod -n default -o jsonpath='{.status.containerStatuses[0].restartCount}'" '^[0-2]$'
  check "증거인 broken-pod 는 남겨 뒀다" "kubectl get pod broken-pod -n default"
}
q1_hint() { cat <<'EOF'
kubectl describe pod broken-pod | tail -20     # Events
kubectl logs broken-pod --previous             # 죽기 직전 로그
# command: ["invalid-command"] 처럼 실행할 수 없는 명령이 들어 있다

kubectl run fixed-pod --image=nginx:1.24 --restart=Never
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Fix an ImagePullBackOff Pod"; }
q2_text() { cat <<'EOF'
The Pod pull-fail in the default namespace is in ImagePullBackOff.

Fix it so that a Pod named pull-fail runs image nginx:1.24 and reaches
Running state.

Note: the image of a running Pod cannot be edited in place for every field —
deleting and recreating it is the usual answer.

Verify:
  kubectl get pod pull-fail        -> Running
EOF
}
q2_title_ko() { echo "ImagePullBackOff 수정"; }
q2_text_ko() { cat <<'EOF'
default 네임스페이스의 pull-fail 파드가 ImagePullBackOff 상태다.

pull-fail 파드가 nginx:1.24 이미지로 Running 이 되도록 고치시오.

파드의 필드는 대부분 실행 중 수정할 수 없다 — 삭제 후 재생성이 보통의
정답이다.

[확인]
  kubectl get pod pull-fail        → Running
EOF
}
q2_grade() {
  check "파드 pull-fail 존재" "kubectl get pod pull-fail -n default"
  wait_ready "pull-fail" default
  check_output "Running" "kubectl get pod pull-fail -n default -o jsonpath='{.status.phase}'" '^Running$'
  check_output "이미지가 nginx:1.24" \
    "kubectl get pod pull-fail -n default -o jsonpath='{.spec.containers[0].image}'" '^nginx:1\.24$'
  check_output "컨테이너가 Ready" \
    "kubectl get pod pull-fail -n default -o jsonpath='{.status.containerStatuses[0].ready}'" '^true$'
}
q2_hint() { cat <<'EOF'
kubectl describe pod pull-fail | tail -15      # Events 에 pull 실패 이유

kubectl delete pod pull-fail
kubectl run pull-fail --image=nginx:1.24 --restart=Never

# 이미지만 바꾸는 방법도 있다
kubectl set image pod/pull-fail app=nginx:1.24
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Service with empty Endpoints"; }
q3_text() { cat <<'EOF'
The Service target-svc has no Endpoints, although the Deployment
target-app is running with two Pods.

Diagnose the cause and fix the Service so that both Pod IPs appear in its
Endpoints. Do not change the Pod labels — fix the Service.

Useful commands:
  kubectl get endpoints target-svc
  kubectl get svc target-svc -o yaml
  kubectl get pods -l app=target-app --show-labels

Verify:
  kubectl get endpoints target-svc    -> two Pod IPs
EOF
}
q3_title_ko() { echo "Endpoints 가 비어 있는 Service"; }
q3_text_ko() { cat <<'EOF'
target-svc Service 의 Endpoints 가 비어 있다. target-app Deployment 는
파드 2개로 정상 실행 중이다.

원인을 진단하고, Endpoints 에 파드 IP 2개가 등록되도록 Service 를
고치시오. 파드 레이블을 바꾸지 말고 Service 를 고친다.

[진단]
  kubectl get endpoints target-svc
  kubectl get svc target-svc -o yaml
  kubectl get pods -l app=target-app --show-labels

[확인]
  kubectl get endpoints target-svc    → 파드 IP 2개
EOF
}
q3_grade() {
  check "Service target-svc 존재" "kubectl get service target-svc -n default"
  check_output "selector 가 app=target-app" \
    "kubectl get service target-svc -n default -o jsonpath='{.spec.selector.app}'" '^target-app$'
  check_output "Endpoints 에 파드 IP 2개" \
    "kubectl get endpoints target-svc -n default -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w" '^\s*2$'
  check_output "Deployment 파드 레이블은 그대로" \
    "kubectl get deployment target-app -n default -o jsonpath='{.spec.template.metadata.labels.app}'" '^target-app$'
  check_output "임시 파드에서 target-svc 로 실제 응답" \
    "kubectl run netchk-q3 -n default --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- --timeout=5 http://target-svc 2>/dev/null" 'nginx'
}
q3_hint() { cat <<'EOF'
kubectl get svc target-svc -o yaml | grep -A3 selector      # app: WRONG-LABEL
kubectl get pods -l app=target-app --show-labels            # 실제 레이블

kubectl patch svc target-svc -p '{"spec":{"selector":{"app":"target-app"}}}'
kubectl get endpoints target-svc
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Check node health"; }
q4_text() { cat <<'EOF'
Check the state of the cluster nodes and record what you found.

  1) at least two nodes must be Ready
  2) write the output of the node list, including the Conditions summary,
     into /tmp/node-report.txt

If a node is NotReady, recover it first (ssh into it and inspect kubelet),
then write the report.

Verify:
  kubectl get nodes
  cat /tmp/node-report.txt
EOF
}
q4_title_ko() { echo "노드 상태 점검"; }
q4_text_ko() { cat <<'EOF'
클러스터 노드 상태를 점검하고 결과를 기록하시오.

  1) Ready 노드가 최소 2개여야 한다
  2) 노드 목록과 Conditions 요약을 /tmp/node-report.txt 에 저장한다

NotReady 노드가 있으면 먼저 복구한 뒤(ssh 로 들어가 kubelet 확인)
리포트를 작성한다.

[확인]
  kubectl get nodes
  cat /tmp/node-report.txt
EOF
}
q4_grade() {
  local ready; ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')
  check_result "Ready 노드가 2개 이상 (현재 ${ready:-0}개)" \
    "$([[ "${ready:-0}" -ge 2 ]] && echo 0 || echo 1)" "NotReady 노드를 먼저 복구하세요"
  check "/tmp/node-report.txt 존재" "test -f /tmp/node-report.txt"
  check "/tmp/node-report.txt 가 비어 있지 않다" "test -s /tmp/node-report.txt"
  check_output "리포트에 노드 이름이 들어 있다" \
    "cat /tmp/node-report.txt 2>/dev/null" "$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo control)"
  check_output "리포트에 상태(Ready) 정보가 있다" \
    "cat /tmp/node-report.txt 2>/dev/null" 'Ready'
}
q4_hint() { cat <<'EOF'
kubectl get nodes -o wide
kubectl describe node <노드> | grep -A8 Conditions

{ kubectl get nodes -o wide; echo; kubectl describe nodes | grep -E '^Name:|Ready|MemoryPressure|DiskPressure'; } \
  > /tmp/node-report.txt
EOF
}

exam_main "$@"
