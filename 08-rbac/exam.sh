#!/usr/bin/env bash
# CKA 8강 실습 — RBAC (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 8강 실습 — RBAC (ServiceAccount · Role · ClusterRole)"
EXAM_NQ=4

exam_cleanup() {
  kubectl delete clusterrolebinding node-reader-binding --ignore-not-found &>/dev/null || true
  kubectl delete clusterrole node-reader --ignore-not-found &>/dev/null || true
  kubectl delete rolebinding pod-reader-binding -n default --ignore-not-found &>/dev/null || true
  kubectl delete role pod-reader -n default --ignore-not-found &>/dev/null || true
  kubectl delete pod sa-test -n default --ignore-not-found &>/dev/null || true
  kubectl delete serviceaccount my-sa -n default --ignore-not-found &>/dev/null || true
  echo "  my-sa / sa-test / pod-reader / node-reader 및 바인딩 삭제"
}
exam_setup() { echo "  (미리 만들어둘 것 없음)"; }

# ══════════════════════════════════════════════════════════════
q1_title() { echo "ServiceAccount used by a Pod"; }
q1_text() { cat <<'EOF'
In the default namespace:

  1) create a ServiceAccount named my-sa

  2) create a Pod named sa-test that runs under it
     image     busybox
     command   ["sleep", "3600"]
     spec.serviceAccountName   my-sa

The Pod must be Running.

Verify:
  kubectl get serviceaccount my-sa
  kubectl get pod sa-test -o jsonpath='{.spec.serviceAccountName}'
EOF
}
q1_title_ko() { echo "ServiceAccount 를 쓰는 파드"; }
q1_text_ko() { cat <<'EOF'
default 네임스페이스에서:

  1) my-sa ServiceAccount 를 만든다

  2) 그 SA 로 동작하는 sa-test 파드를 만든다
     이미지    busybox
     명령      ["sleep", "3600"]
     spec.serviceAccountName   my-sa

파드는 Running 이어야 한다.

[확인]
  kubectl get serviceaccount my-sa
  kubectl get pod sa-test -o jsonpath='{.spec.serviceAccountName}'
EOF
}
q1_grade() {
  check "ServiceAccount my-sa 존재" "kubectl get serviceaccount my-sa -n default"
  check "파드 sa-test 존재" "kubectl get pod sa-test -n default"
  wait_ready "sa-test" default
  check_output "Running" "kubectl get pod sa-test -n default -o jsonpath='{.status.phase}'" '^Running$'
  check_output "파드가 my-sa 로 동작" \
    "kubectl get pod sa-test -n default -o jsonpath='{.spec.serviceAccountName}'" '^my-sa$'
  check_output "SA 토큰이 파드에 마운트됨" \
    "kubectl exec sa-test -n default -- ls /var/run/secrets/kubernetes.io/serviceaccount 2>/dev/null" 'token'
}
q1_hint() { cat <<'EOF'
kubectl create serviceaccount my-sa -n default

kubectl run sa-test --image=busybox --command $do -- sleep 3600 > pod.yaml
#   spec.serviceAccountName: my-sa   를 추가
kubectl apply -f pod.yaml
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Role and RoleBinding"; }
q2_text() { cat <<'EOF'
In the default namespace:

  1) create a Role named pod-reader
     apiGroups   [""]  (core)
     resources   ["pods"]
     verbs       ["get", "list", "watch"]

  2) create a RoleBinding named pod-reader-binding
     roleRef    Role pod-reader
     subject    ServiceAccount my-sa in namespace default

Verify:
  kubectl auth can-i list pods --as=system:serviceaccount:default:my-sa -n default
EOF
}
q2_title_ko() { echo "Role 과 RoleBinding"; }
q2_text_ko() { cat <<'EOF'
default 네임스페이스에서:

  1) pod-reader Role 을 만든다
     apiGroups   [""]  (core)
     resources   ["pods"]
     verbs       ["get", "list", "watch"]

  2) pod-reader-binding RoleBinding 을 만든다
     roleRef    Role pod-reader
     subject    default 네임스페이스의 ServiceAccount my-sa

[확인]
  kubectl auth can-i list pods --as=system:serviceaccount:default:my-sa -n default
EOF
}
q2_grade() {
  check "Role pod-reader 존재" "kubectl get role pod-reader -n default"
  check_output "리소스 pods" "kubectl get role pod-reader -n default -o jsonpath='{.rules[0].resources}'" 'pods'
  check_output "verb get" "kubectl get role pod-reader -n default -o jsonpath='{.rules[0].verbs}'" 'get'
  check_output "verb list" "kubectl get role pod-reader -n default -o jsonpath='{.rules[0].verbs}'" 'list'
  check_output "verb watch" "kubectl get role pod-reader -n default -o jsonpath='{.rules[0].verbs}'" 'watch'
  check "RoleBinding pod-reader-binding 존재" "kubectl get rolebinding pod-reader-binding -n default"
  check_output "roleRef 가 pod-reader" \
    "kubectl get rolebinding pod-reader-binding -n default -o jsonpath='{.roleRef.name}'" '^pod-reader$'
  check_output "subject 가 ServiceAccount my-sa" \
    "kubectl get rolebinding pod-reader-binding -n default -o jsonpath='{.subjects[0].kind}:{.subjects[0].name}'" '^ServiceAccount:my-sa$'
  check_output "실제 권한: pods list 가능" \
    "kubectl auth can-i list pods --as=system:serviceaccount:default:my-sa -n default" '^yes$'
}
q2_hint() { cat <<'EOF'
kubectl create role pod-reader --verb=get,list,watch --resource=pods -n default
kubectl create rolebinding pod-reader-binding \
  --role=pod-reader --serviceaccount=default:my-sa -n default

kubectl auth can-i list pods --as=system:serviceaccount:default:my-sa -n default
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "ClusterRole and ClusterRoleBinding"; }
q3_text() { cat <<'EOF'
Nodes are cluster scoped, so a Role cannot grant access to them.

  1) create a ClusterRole named node-reader
     apiGroups   [""]
     resources   ["nodes"]
     verbs       ["get", "list", "watch"]

  2) create a ClusterRoleBinding named node-reader-binding
     roleRef    ClusterRole node-reader
     subject    ServiceAccount my-sa in namespace default

Verify:
  kubectl auth can-i list nodes --as=system:serviceaccount:default:my-sa
EOF
}
q3_title_ko() { echo "ClusterRole 과 ClusterRoleBinding"; }
q3_text_ko() { cat <<'EOF'
노드는 클러스터 범위 리소스라 Role 로는 권한을 줄 수 없다.

  1) node-reader ClusterRole 을 만든다
     apiGroups   [""]
     resources   ["nodes"]
     verbs       ["get", "list", "watch"]

  2) node-reader-binding ClusterRoleBinding 을 만든다
     roleRef    ClusterRole node-reader
     subject    default 네임스페이스의 ServiceAccount my-sa

[확인]
  kubectl auth can-i list nodes --as=system:serviceaccount:default:my-sa
EOF
}
q3_grade() {
  check "ClusterRole node-reader 존재" "kubectl get clusterrole node-reader"
  check_output "리소스 nodes" "kubectl get clusterrole node-reader -o jsonpath='{.rules[0].resources}'" 'nodes'
  check_output "verb get/list/watch" \
    "kubectl get clusterrole node-reader -o jsonpath='{.rules[0].verbs}'" 'get.*list.*watch'
  check "ClusterRoleBinding node-reader-binding 존재" "kubectl get clusterrolebinding node-reader-binding"
  check_output "roleRef 가 node-reader" \
    "kubectl get clusterrolebinding node-reader-binding -o jsonpath='{.roleRef.name}'" '^node-reader$'
  check_output "subject 가 default:my-sa" \
    "kubectl get clusterrolebinding node-reader-binding -o jsonpath='{.subjects[0].name}:{.subjects[0].namespace}'" '^my-sa:default$'
  check_output "실제 권한: nodes list 가능" \
    "kubectl auth can-i list nodes --as=system:serviceaccount:default:my-sa" '^yes$'
}
q3_hint() { cat <<'EOF'
kubectl create clusterrole node-reader --verb=get,list,watch --resource=nodes
kubectl create clusterrolebinding node-reader-binding \
  --clusterrole=node-reader --serviceaccount=default:my-sa

kubectl auth can-i list nodes --as=system:serviceaccount:default:my-sa
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Verify the granted permissions"; }
q4_text() { cat <<'EOF'
Confirm with kubectl auth can-i that the ServiceAccount my-sa has exactly
the permissions granted so far, and nothing more:

  get pods in default            -> yes
  list nodes (cluster wide)      -> yes
  delete pods in default         -> no
  list secrets in default        -> no

If any of the four does not match, fix the Role / ClusterRole so that it
does. Do not add extra permissions.

Verify:
  kubectl auth can-i get pods    --as=system:serviceaccount:default:my-sa -n default
  kubectl auth can-i delete pods --as=system:serviceaccount:default:my-sa -n default
EOF
}
q4_title_ko() { echo "부여된 권한 검증"; }
q4_text_ko() { cat <<'EOF'
kubectl auth can-i 로 my-sa ServiceAccount 가 지금까지 준 권한만
정확히 갖고 있는지 확인하시오.

  default 에서 pods get         → yes
  클러스터 전체 nodes list      → yes
  default 에서 pods delete      → no
  default 에서 secrets list     → no

네 가지 중 맞지 않는 게 있으면 Role / ClusterRole 을 고쳐서 맞춘다.
필요 없는 권한을 더 주면 안 된다.

[확인]
  kubectl auth can-i get pods    --as=system:serviceaccount:default:my-sa -n default
  kubectl auth can-i delete pods --as=system:serviceaccount:default:my-sa -n default
EOF
}
q4_grade() {
  check_output "get pods 가능 (yes)" \
    "kubectl auth can-i get pods --as=system:serviceaccount:default:my-sa -n default" '^yes$'
  check_output "list nodes 가능 (yes)" \
    "kubectl auth can-i list nodes --as=system:serviceaccount:default:my-sa" '^yes$'
  check_output "delete pods 불가 (no)" \
    "kubectl auth can-i delete pods --as=system:serviceaccount:default:my-sa -n default" '^no$'
  check_output "list secrets 불가 (no)" \
    "kubectl auth can-i list secrets --as=system:serviceaccount:default:my-sa -n default" '^no$'
  check_output "다른 네임스페이스 pods 는 불가 (Role 은 네임스페이스 범위)" \
    "kubectl auth can-i list pods --as=system:serviceaccount:default:my-sa -n kube-system" '^no$'
}
q4_hint() { cat <<'EOF'
# 권한이 과한 경우: Role/ClusterRole 의 verbs 나 resources 를 줄인다
kubectl get role pod-reader -n default -o yaml
kubectl get clusterrole node-reader -o yaml

# cluster-admin 같은 기존 ClusterRole 을 붙여 버리면 no 가 나와야 할 항목이 yes 가 된다
kubectl get clusterrolebinding | grep my-sa
EOF
}

exam_main "$@"
