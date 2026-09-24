#!/usr/bin/env bash
# CKA 특강 실습 — NetworkPolicy (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 특강 실습 — NetworkPolicy (기본 거부 · 선택 허용 · Egress)"
EXAM_NQ=5

NS=netpol

exam_cleanup() {
  kdel namespace "$NS"
  kdel namespace "${NS}-client"
  echo "  $NS / ${NS}-client 네임스페이스 삭제 (안의 리소스도 함께)"
}
exam_setup() {
  kubectl create namespace "$NS" &>/dev/null
  kubectl create namespace "${NS}-client" &>/dev/null
  kubectl label namespace "${NS}-client" team=partner --overwrite &>/dev/null
  # 대상 서버: web (포트 80)
  kubectl -n "$NS" run web --image=nginx:1.24 --labels=app=web --port=80 &>/dev/null
  kubectl -n "$NS" expose pod web --name=web-svc --port=80 &>/dev/null
  # 같은 네임스페이스의 클라이언트 두 종류
  kubectl -n "$NS" run trusted  --image=busybox:1.36 --labels=role=trusted  --command -- sleep 3600 &>/dev/null
  kubectl -n "$NS" run stranger --image=busybox:1.36 --labels=role=stranger --command -- sleep 3600 &>/dev/null
  echo "  $NS 에 web(nginx) · web-svc · trusted · stranger 준비"
  echo "  ${NS}-client 네임스페이스에 team=partner 레이블 부여"
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Default deny for ingress"; }
q1_text() { cat <<'EOF'
In namespace netpol, create a NetworkPolicy named default-deny-ingress that
denies all incoming traffic to every Pod in that namespace.

  podSelector   {}        (selects every Pod)
  policyTypes   Ingress
  (no ingress rules at all)

Verify:
  kubectl -n netpol get networkpolicy default-deny-ingress
EOF
}
q1_title_ko() { echo "인그레스 기본 거부"; }
q1_text_ko() { cat <<'EOF'
netpol 네임스페이스에 default-deny-ingress 라는 NetworkPolicy 를 만들어
그 네임스페이스의 모든 파드로 들어오는 트래픽을 전부 막는다.

  podSelector   {}        (모든 파드를 고른다)
  policyTypes   Ingress
  (ingress 규칙은 하나도 두지 않는다)

[확인]
  kubectl -n netpol get networkpolicy default-deny-ingress
EOF
}
q1_grade() {
  check "NetworkPolicy default-deny-ingress 존재" \
    "kubectl -n $NS get networkpolicy default-deny-ingress"
  check_output "policyTypes 에 Ingress" \
    "kubectl -n $NS get networkpolicy default-deny-ingress -o jsonpath='{.spec.policyTypes[*]}'" 'Ingress'
  # 정책이 아예 없을 때도 통과해 버리지 않도록, 존재를 확인한 뒤에 내용을 본다
  local exists ps ing
  exists=$(kubectl -n "$NS" get networkpolicy default-deny-ingress -o name 2>/dev/null)
  ps=$(kubectl -n "$NS" get networkpolicy default-deny-ingress -o jsonpath='{.spec.podSelector}' 2>/dev/null)
  ing=$(kubectl -n "$NS" get networkpolicy default-deny-ingress -o jsonpath='{.spec.ingress}' 2>/dev/null)
  check_result "podSelector 가 비어 있다 (모든 파드)" \
    "$([[ -n "$exists" && "$ps" == "{}" ]] && echo 0 || echo 1)" \
    "실제: ${ps:-정책이 없다}"
  check_result "ingress 규칙이 없다" \
    "$([[ -n "$exists" && -z "$ing" ]] && echo 0 || echo 1)" \
    "$([[ -z "$exists" ]] && echo "정책이 없다" || echo "규칙이 있으면 '기본 거부' 가 아니다")"
}
q1_hint() { cat <<'EOF'
# 공식 문서에서 "default deny all ingress" 예제를 그대로 가져오면 된다
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-ingress, namespace: netpol }
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Allow one label only"; }
q2_text() { cat <<'EOF'
Still in namespace netpol, create a NetworkPolicy named allow-trusted so that
Pods labeled role=trusted can reach the Pod labeled app=web on TCP port 80.

Pods with other labels (for example role=stranger) must stay blocked.

Verify:
  kubectl -n netpol exec trusted  -- wget -qO- --timeout=3 web-svc   # works
  kubectl -n netpol exec stranger -- wget -qO- --timeout=3 web-svc   # blocked
EOF
}
q2_title_ko() { echo "한 레이블만 허용"; }
q2_text_ko() { cat <<'EOF'
같은 netpol 네임스페이스에 allow-trusted 라는 NetworkPolicy 를 만들어
role=trusted 레이블이 붙은 파드만 app=web 파드의 TCP 80 포트에 닿게 한다.

다른 레이블(예: role=stranger)은 계속 막혀 있어야 한다.

[확인]
  kubectl -n netpol exec trusted  -- wget -qO- --timeout=3 web-svc   # 된다
  kubectl -n netpol exec stranger -- wget -qO- --timeout=3 web-svc   # 막힌다
EOF
}
q2_grade() {
  check "NetworkPolicy allow-trusted 존재" "kubectl -n $NS get networkpolicy allow-trusted"
  check_output "대상이 app=web" \
    "kubectl -n $NS get networkpolicy allow-trusted -o jsonpath='{.spec.podSelector.matchLabels.app}'" '^web$'
  check_output "허용 대상이 role=trusted" \
    "kubectl -n $NS get networkpolicy allow-trusted -o jsonpath='{.spec.ingress[0].from[0].podSelector.matchLabels.role}'" '^trusted$'
  check_output "포트 80" \
    "kubectl -n $NS get networkpolicy allow-trusted -o jsonpath='{.spec.ingress[0].ports[0].port}'" '^80$'
  check_output "trusted 에서 실제로 닿는다" \
    "kubectl -n $NS exec trusted -- wget -qO- --timeout=3 web-svc 2>/dev/null" 'nginx' 2
  check_result "stranger 는 막혀 있다" \
    "$(kubectl -n $NS exec stranger -- wget -qO- --timeout=3 web-svc &>/dev/null && echo 1 || echo 0)" \
    "stranger 가 닿으면 안 된다" 2
}
q2_hint() { cat <<'EOF'
spec:
  podSelector:
    matchLabels: { app: web }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels: { role: trusted }
      ports:
        - protocol: TCP
          port: 80
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Allow another namespace"; }
q3_text() { cat <<'EOF'
The namespace netpol-client is labeled team=partner.

Create a NetworkPolicy named allow-partner-ns in namespace netpol that also
lets every Pod from namespaces labeled team=partner reach app=web on port 80.

Keep the previous policies in place.

Verify:
  kubectl get namespace netpol-client --show-labels
  kubectl -n netpol get networkpolicy
EOF
}
q3_title_ko() { echo "다른 네임스페이스를 허용"; }
q3_text_ko() { cat <<'EOF'
netpol-client 네임스페이스에는 team=partner 레이블이 붙어 있다.

netpol 네임스페이스에 allow-partner-ns 라는 NetworkPolicy 를 만들어
team=partner 레이블이 붙은 네임스페이스의 파드도 app=web 의 80 포트에
닿을 수 있게 한다.

앞에서 만든 정책은 그대로 둔다.

[확인]
  kubectl get namespace netpol-client --show-labels
  kubectl -n netpol get networkpolicy
EOF
}
q3_grade() {
  check "NetworkPolicy allow-partner-ns 존재" "kubectl -n $NS get networkpolicy allow-partner-ns"
  check_output "대상이 app=web" \
    "kubectl -n $NS get networkpolicy allow-partner-ns -o jsonpath='{.spec.podSelector.matchLabels.app}'" '^web$'
  check_output "namespaceSelector 가 team=partner" \
    "kubectl -n $NS get networkpolicy allow-partner-ns -o jsonpath='{.spec.ingress[0].from[0].namespaceSelector.matchLabels.team}'" '^partner$'
  check_output "포트 80" \
    "kubectl -n $NS get networkpolicy allow-partner-ns -o jsonpath='{.spec.ingress[0].ports[0].port}'" '^80$'
}
q3_hint() { cat <<'EOF'
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: { team: partner }
      ports: [{ protocol: TCP, port: 80 }]

# podSelector 와 namespaceSelector 를 같은 '-' 아래 두면 AND 다.
# 서로 다른 '-' 로 두면 OR 가 된다 — 이 문제는 네임스페이스만 보면 된다.
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Egress — let DNS through"; }
q4_text() { cat <<'EOF'
Create a NetworkPolicy named trusted-egress in namespace netpol that applies
to Pods labeled role=trusted and restricts their OUTGOING traffic to:

  - TCP port 80 to Pods labeled app=web
  - UDP port 53 (DNS) to anywhere

If you forget the DNS rule, name resolution stops working —
that is the most common mistake with egress policies.

Verify:
  kubectl -n netpol exec trusted -- nslookup web-svc
EOF
}
q4_title_ko() { echo "Egress — DNS 를 열어 둬야 한다"; }
q4_text_ko() { cat <<'EOF'
netpol 네임스페이스에 trusted-egress 라는 NetworkPolicy 를 만들어
role=trusted 파드의 나가는 트래픽을 다음만 허용한다.

  - app=web 파드로 TCP 80
  - 어디로든 UDP 53 (DNS)

DNS 규칙을 빼먹으면 이름을 못 찾게 된다.
egress 정책에서 가장 흔한 실수다.

[확인]
  kubectl -n netpol exec trusted -- nslookup web-svc
EOF
}
q4_grade() {
  check "NetworkPolicy trusted-egress 존재" "kubectl -n $NS get networkpolicy trusted-egress"
  check_output "policyTypes 에 Egress" \
    "kubectl -n $NS get networkpolicy trusted-egress -o jsonpath='{.spec.policyTypes[*]}'" 'Egress'
  check_output "대상이 role=trusted" \
    "kubectl -n $NS get networkpolicy trusted-egress -o jsonpath='{.spec.podSelector.matchLabels.role}'" '^trusted$'
  check_output "UDP 53 이 열려 있다" \
    "kubectl -n $NS get networkpolicy trusted-egress -o jsonpath='{range .spec.egress[*]}{range .ports[*]}{.protocol}{.port}{\" \"}{end}{end}'" 'UDP53'
  check_output "TCP 80 이 열려 있다" \
    "kubectl -n $NS get networkpolicy trusted-egress -o jsonpath='{range .spec.egress[*]}{range .ports[*]}{.protocol}{.port}{\" \"}{end}{end}'" 'TCP80'
  check_output "이름 조회가 된다 (DNS 가 살아 있다)" \
    "kubectl -n $NS exec trusted -- nslookup web-svc 2>/dev/null" 'web-svc' 2
}
q4_hint() { cat <<'EOF'
spec:
  podSelector: { matchLabels: { role: trusted } }
  policyTypes: ["Egress"]
  egress:
    - to: [{ podSelector: { matchLabels: { app: web } } }]
      ports: [{ protocol: TCP, port: 80 }]
    - ports: [{ protocol: UDP, port: 53 }]     # to 를 생략하면 어디로든
EOF
}

# ══════════════════════════════════════════════════════════════
q5_title() { echo "Read what a policy does"; }
q5_text() { cat <<'EOF'
Look at the policies you created and answer in a file.

Write to /tmp/netpol-answer.txt exactly one line, the name of the policy
that makes every Pod in the namespace default-deny even though it
allows nothing by itself.

Then, on a second line, write how many NetworkPolicies exist in
namespace netpol.

Example:
  some-policy-name
  4
EOF
}
q5_title_ko() { echo "정책을 읽어 낸다"; }
q5_text_ko() { cat <<'EOF'
지금까지 만든 정책을 보고 파일로 답한다.

/tmp/netpol-answer.txt 의 첫 줄에, 그 자체로는 아무것도 허용하지 않으면서
네임스페이스의 모든 파드를 기본 거부 상태로 만드는 정책의 이름을 적는다.

둘째 줄에는 netpol 네임스페이스에 있는 NetworkPolicy 개수를 적는다.

예시:
  some-policy-name
  4
EOF
}
q5_grade() {
  check "/tmp/netpol-answer.txt 가 있다" "test -s /tmp/netpol-answer.txt"
  check_output "첫 줄이 default-deny-ingress" "head -1 /tmp/netpol-answer.txt 2>/dev/null" '^default-deny-ingress$'
  local want got
  want=$(kubectl -n "$NS" get networkpolicy --no-headers 2>/dev/null | wc -l | tr -d ' ')
  got=$(sed -n '2p' /tmp/netpol-answer.txt 2>/dev/null | tr -d ' ')
  check_result "둘째 줄의 개수가 실제와 같다" \
    "$([[ -n "$got" && "$got" == "$want" ]] && echo 0 || echo 1)" \
    "실제 ${want}개 / 적어낸 값 '${got:-비어 있음}'"
}
q5_hint() { cat <<'EOF'
kubectl -n netpol get networkpolicy

# 기본 거부를 만드는 것은 podSelector 가 {} 이고 규칙이 없는 정책이다.
# 정책이 하나라도 그 파드를 고르면, 허용하지 않은 나머지는 전부 막힌다.
EOF
}

exam_main "$@"
