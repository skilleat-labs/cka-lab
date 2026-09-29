#!/usr/bin/env bash
# CKA Mock Exam 4 — 2026 출제 주제 20분 점검 (100점 · 5문항)
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
#
# 목적: 2026 합격 후기에서 확인된 13개 주제 중 5개를 20분 안에 푸는지 본다.
#   Q1 PriorityClass · Q2 Helm template · Q3 네이티브 사이드카 · Q4 NetworkPolicy · Q5 기본 StorageClass
# 문제마다 네임스페이스가 따로라 순서와 상관없이 풀 수 있다.
set -uo pipefail
EXAM_UNIT="점"
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA Mock Exam 4 — 2026 출제 주제 20분 점검 (100점 · 5문항)"
EXAM_NQ=5
EXAM_LIMIT_MIN="${EXAM_LIMIT_MIN:-20}"   # 제한시간(분) — 0 이면 무제한

HELM_OUT=/tmp/mock4-argocd.yaml

exam_cleanup() {
  local ns
  for ns in analytics edge payments partner warehouse; do
    kubectl get namespace $ns &>/dev/null && kubectl delete namespace $ns --wait=false &>/dev/null
  done
  kdel priorityclass team-high team-mid report-urgent
  kdel storageclass legacy-std fast-local
  rm -f "$HELM_OUT"
  helm uninstall cd -n gitops &>/dev/null || true
  kdel namespace gitops
  # 네임스페이스가 다 지워져야 start 가 새로 만들 수 있다
  for ns in analytics edge payments partner warehouse gitops; do
    kubectl wait --for=delete namespace/$ns --timeout=90s &>/dev/null || true
  done
  echo "  analytics · edge · payments · partner · warehouse 네임스페이스"
  echo "  PriorityClass team-high · team-mid · report-urgent / StorageClass legacy-std · fast-local / $HELM_OUT 삭제"
}

exam_setup() {
  # ── Q1: 기존 PriorityClass 두 개 + 우선순위 없는 Deployment
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: team-high }
value: 10000
description: "existing — batch owners"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: team-mid }
value: 5000
description: "existing — default tier"
---
apiVersion: v1
kind: Namespace
metadata: { name: analytics }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: report-gen, namespace: analytics, labels: { app: report-gen } }
spec:
  replicas: 2
  selector: { matchLabels: { app: report-gen } }
  template:
    metadata: { labels: { app: report-gen } }
    spec:
      containers:
        - name: gen
          image: busybox:1.36
          command: ["sh", "-c", "sleep 3600"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML
  echo "  Q1  PriorityClass team-high(10000) · team-mid(5000), analytics/report-gen 배치"

  # ── Q2: 준비할 것 없음 (helm 만 확인)
  if command -v helm &>/dev/null; then
    echo "  Q2  helm $(helm version --short 2>/dev/null) 확인"
  else
    echo -e "  ${RED}Q2  helm 이 없습니다.${RESET} 먼저 설치하세요:"
    echo "      curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
  fi

  # ── Q3: 로그를 쓰는 앱 (사이드카만 붙이면 된다)
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: edge }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: audit-api, namespace: edge, labels: { app: audit-api } }
spec:
  replicas: 1
  selector: { matchLabels: { app: audit-api } }
  template:
    metadata: { labels: { app: audit-api } }
    spec:
      containers:
        - name: api
          image: busybox:1.36
          command: ["sh", "-c", "while true; do echo \"$(date) audit event\" >> /var/log/audit/api.log; sleep 3; done"]
          volumeMounts:
            - name: audit-logs
              mountPath: /var/log/audit
      volumes:
        - name: audit-logs
          emptyDir: {}
YAML
  echo "  Q3  edge/audit-api 배치 (/var/log/audit/api.log 에 기록 중)"

  # ── Q4: 보호할 ledger 와 접속을 시도할 파드 세 개
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: payments }
---
apiVersion: v1
kind: Namespace
metadata: { name: partner }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: ledger, namespace: payments, labels: { app: ledger } }
spec:
  replicas: 1
  selector: { matchLabels: { app: ledger } }
  template:
    metadata: { labels: { app: ledger } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [ { containerPort: 80 } ]
---
apiVersion: v1
kind: Service
metadata: { name: ledger, namespace: payments }
spec:
  selector: { app: ledger }
  ports: [ { port: 80, targetPort: 80 } ]
---
apiVersion: v1
kind: Pod
metadata: { name: checkout, namespace: payments, labels: { app: checkout } }
spec:
  containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 3600"] } ]
---
apiVersion: v1
kind: Pod
metadata: { name: scanner, namespace: payments, labels: { app: scanner } }
spec:
  containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 3600"] } ]
---
apiVersion: v1
kind: Pod
metadata: { name: checkout, namespace: partner, labels: { app: checkout } }
spec:
  containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 3600"] } ]
YAML
  echo "  Q4  payments/ledger(+Service) · payments/checkout · payments/scanner · partner/checkout 배치"

  # ── Q5: 이미 기본으로 지정된 StorageClass 하나
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: legacy-std
  annotations: { storageclass.kubernetes.io/is-default-class: "true" }
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
---
apiVersion: v1
kind: Namespace
metadata: { name: warehouse }
YAML
  echo "  Q5  StorageClass legacy-std (현재 기본) · warehouse 네임스페이스"

  local others
  others=$(kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}={.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null \
           | grep '=true$' | cut -d= -f1 | grep -vx legacy-std | tr '\n' ' ')
  [[ -n "$others" ]] && echo -e "  ${ORANGE}참고: 이 클러스터에는 다른 기본 StorageClass 도 있습니다 → ${others}(Q5 에서 함께 해제해야 합니다)${RESET}"
  return 0
}

# ══════════════════════════════════════════════════════════════
# Q1 — PriorityClass 생성 · Deployment 연결
# ══════════════════════════════════════════════════════════════
q1_title() { echo "PriorityClass one below the highest [20 pts]"; }
q1_text() { cat <<'EOF'
Several user-defined PriorityClasses already exist in the cluster.

  (a) Create a PriorityClass named report-urgent whose value is exactly
      ONE LESS than the highest value among the existing user-defined
      PriorityClasses (ignore the built-in system-* classes).
      It must not be the global default.

  (b) Update the existing Deployment report-gen in the analytics namespace
      so that its Pods use report-urgent. Do not delete the Deployment.

All report-gen Pods must be Running with the new priority.

Verify:
  kubectl get priorityclass
  kubectl -n analytics get pods -l app=report-gen -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priority
EOF
}
q1_title_ko() { echo "가장 높은 값보다 1 낮은 PriorityClass [20점]"; }
q1_text_ko() { cat <<'EOF'
클러스터에 사용자가 만든 PriorityClass 가 이미 몇 개 있다.

  (a) report-urgent PriorityClass 를 만든다.
      값은 기존 사용자 정의 PriorityClass 중 가장 높은 값보다 정확히 1 작게.
      (system- 으로 시작하는 기본 클래스는 제외)
      globalDefault 가 되어서는 안 된다.

  (b) analytics 네임스페이스의 기존 Deployment report-gen 이
      report-urgent 를 쓰도록 수정한다. Deployment 를 지우고 다시 만들지 않는다.

report-gen 파드가 모두 새 우선순위로 Running 이어야 한다.

[확인]
  kubectl get priorityclass
  kubectl -n analytics get pods -l app=report-gen -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priority
EOF
}
q1_hint() { cat <<'EOF'
kubectl get priorityclass --sort-by=.value          # system-* 를 빼고 가장 큰 값을 찾는다

kubectl create priorityclass report-urgent --value=<그 값 - 1> --description="report jobs"

# 파드 속성이므로 spec.template.spec 아래 — patch 하면 롤아웃으로 파드가 새로 뜬다
kubectl -n analytics patch deployment report-gen \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"report-urgent"}}}}'
kubectl -n analytics rollout status deployment report-gen
EOF
}
q1_grade() {
  # 기대값은 채점 시점에 계산한다 — 다른 실습이 남긴 클래스가 있어도 "가장 높은 값 - 1" 이 기준
  local max want
  max=$(kubectl get priorityclass -o jsonpath='{range .items[*]}{.metadata.name} {.value}{"\n"}{end}' 2>/dev/null \
        | grep -v '^system-' | grep -v '^report-urgent ' | awk '{print $2}' | sort -n | tail -1)
  max="${max//[^0-9]/}"; max="${max:-10000}"; want=$((max - 1))

  check "report-urgent 존재" "kubectl get priorityclass report-urgent" 3
  check_output "값이 ${want} (가장 높은 사용자 정의 값 ${max} - 1)" \
    "kubectl get priorityclass report-urgent -o jsonpath='{.value}'" "^${want}$" 5
  check_output "globalDefault 가 아니다" \
    "kubectl get priorityclass report-urgent -o jsonpath='{.globalDefault}'" "^(false)?$" 2
  check_output "Deployment 템플릿에 priorityClassName: report-urgent" \
    "kubectl -n analytics get deployment report-gen -o jsonpath='{.spec.template.spec.priorityClassName}'" "^report-urgent$" 4
  wait_ready "-l app=report-gen" analytics || true
  check_output "파드 2개가 Ready" \
    "kubectl -n analytics get deployment report-gen -o jsonpath='{.status.readyReplicas}/{.status.updatedReplicas}'" "^2/2$" 2
  local pr
  pr=$(kubectl -n analytics get pods -l app=report-gen --field-selector=status.phase=Running \
       -o jsonpath='{range .items[*]}{.spec.priority}{"\n"}{end}' 2>/dev/null | sort -u | tr '\n' ' ')
  check_result "Running 파드가 모두 priority ${want} (현재: ${pr:-없음})" \
    "$([[ "$pr" == "$want " ]] && echo 0 || echo 1)" "옛 파드가 남아 있으면 롤아웃이 끝났는지 확인" 4
}

# ══════════════════════════════════════════════════════════════
# Q2 — Helm template (설치하지 않고 렌더링)
# ══════════════════════════════════════════════════════════════
q2_title() { echo "Render a Helm chart without installing it [20 pts]"; }
q2_text() { cat <<'EOF'
The platform team wants the Argo CD manifests for review, NOT an install.

  1) Add the Helm repository
       name  argo
       URL   https://argoproj.github.io/argo-helm

  2) Render the chart argo/argo-cd to a file without installing it
       chart version   7.7.0
       release name    cd
       namespace       gitops
       output file     /tmp/mock4-argocd.yaml

     The output must NOT contain any CustomResourceDefinition.

Nothing may be installed in the cluster (no Helm release, no namespace gitops
is required).

Verify:
  grep -c 'kind: CustomResourceDefinition' /tmp/mock4-argocd.yaml     -> 0
  grep -m1 'helm.sh/chart' /tmp/mock4-argocd.yaml
  helm list -A
EOF
}
q2_title_ko() { echo "Helm 차트를 설치하지 않고 렌더링 [20점]"; }
q2_text_ko() { cat <<'EOF'
플랫폼 팀이 Argo CD 매니페스트를 검토하려 한다. 설치가 아니다.

  1) Helm 저장소를 추가한다
       이름  argo
       주소  https://argoproj.github.io/argo-helm

  2) argo/argo-cd 차트를 설치하지 말고 파일로 렌더링한다
       차트 버전     7.7.0
       릴리스 이름   cd
       네임스페이스  gitops
       저장 경로     /tmp/mock4-argocd.yaml

     결과에 CustomResourceDefinition 이 하나도 없어야 한다.

클러스터에는 아무것도 설치하지 않는다 (Helm 릴리스 없음, gitops 네임스페이스도 필요 없다).

[확인]
  grep -c 'kind: CustomResourceDefinition' /tmp/mock4-argocd.yaml     → 0
  grep -m1 'helm.sh/chart' /tmp/mock4-argocd.yaml
  helm list -A
EOF
}
q2_hint() { cat <<'EOF'
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update

helm template cd argo/argo-cd --version 7.7.0 -n gitops --skip-crds > /tmp/mock4-argocd.yaml
grep -c 'kind: CustomResourceDefinition' /tmp/mock4-argocd.yaml      # 0 이 아니면?

# --skip-crds 는 차트의 crds/ 폴더만 뺀다. 이 차트는 CRD 를 templates/ 안에 둔다.
helm show values argo/argo-cd --version 7.7.0 | grep -A3 '^crds:'   # 차트가 주는 스위치를 찾는다
EOF
}
q2_grade() {
  check "helm 이 설치돼 있다" "command -v helm" 1
  check_output "argo 저장소가 추가됐다" "helm repo list 2>/dev/null" 'argoproj\.github\.io/argo-helm' 2
  check "$HELM_OUT 이 있다" "test -s $HELM_OUT" 3
  check_output "차트 버전 7.7.0 으로 렌더링했다" "grep -m1 'helm.sh/chart: argo-cd-' $HELM_OUT" 'argo-cd-7\.7\.0$' 3
  check_output "네임스페이스 gitops 로 렌더링했다" "grep -m1 '^  namespace:' $HELM_OUT" 'namespace: gitops$' 2
  check_output "릴리스 이름 cd 로 렌더링했다" "grep -m1 'app.kubernetes.io/instance:' $HELM_OUT" 'instance: cd$' 2
  local n; n=$(grep -c 'kind: CustomResourceDefinition' "$HELM_OUT" 2>/dev/null); n="${n//[^0-9]/}"; n="${n:-0}"
  local has=1; [[ -s "$HELM_OUT" ]] && has=0
  check_result "CustomResourceDefinition 이 0개 (현재 ${n}개)" \
    "$([[ $has == 0 && "$n" == "0" ]] && echo 0 || echo 1)" "--skip-crds 로 안 빠지면 차트 values 의 crds 설정을 본다" 5
  local inst; inst=$(helm list -A -q 2>/dev/null | grep -cx cd); inst="${inst//[^0-9]/}"; inst="${inst:-0}"
  check_result "클러스터에 설치하지 않았다 (helm 릴리스 cd 없음)" \
    "$([[ "$inst" == "0" ]] && echo 0 || echo 1)" "릴리스 cd 가 설치돼 있다 — template 만 하면 된다" 2
}

# ══════════════════════════════════════════════════════════════
# Q3 — 네이티브 사이드카
# ══════════════════════════════════════════════════════════════
q3_title() { echo "Add a native sidecar that ships logs [20 pts]"; }
q3_text() { cat <<'EOF'
The Deployment audit-api in the edge namespace writes its log to
/var/log/audit/api.log on the emptyDir volume audit-logs.

Add a NATIVE sidecar container to this Deployment.

  name         audit-shipper
  image        busybox:1.36
  command      sh -c 'tail -F /var/log/audit/api.log'
  mount        the existing volume audit-logs at /var/log/audit

A native sidecar is declared under initContainers with restartPolicy: Always.
After the change the Pod must show READY 2/2 and the sidecar must print the
application's log lines.

Verify:
  kubectl -n edge get pods -l app=audit-api
  kubectl -n edge logs deploy/audit-api -c audit-shipper --tail=3
EOF
}
q3_title_ko() { echo "로그를 읽는 네이티브 사이드카 추가 [20점]"; }
q3_text_ko() { cat <<'EOF'
edge 네임스페이스의 Deployment audit-api 는 emptyDir 볼륨 audit-logs 의
/var/log/audit/api.log 에 로그를 쓴다.

이 Deployment 에 네이티브 사이드카를 추가한다.

  이름         audit-shipper
  이미지       busybox:1.36
  명령         sh -c 'tail -F /var/log/audit/api.log'
  마운트       기존 볼륨 audit-logs 를 /var/log/audit 에

네이티브 사이드카는 initContainers 아래에 restartPolicy: Always 로 선언한다.
바꾼 뒤 파드가 READY 2/2 이고, 사이드카 로그에 앱의 로그가 보여야 한다.

[확인]
  kubectl -n edge get pods -l app=audit-api
  kubectl -n edge logs deploy/audit-api -c audit-shipper --tail=3
EOF
}
q3_hint() { cat <<'EOF'
kubectl -n edge edit deployment audit-api
# spec.template.spec 아래, containers 와 같은 높이에
  initContainers:
    - name: audit-shipper
      image: busybox:1.36
      restartPolicy: Always
      command: ["sh", "-c", "tail -F /var/log/audit/api.log"]
      volumeMounts:
        - name: audit-logs
          mountPath: /var/log/audit
EOF
}
q3_grade() {
  local sel='?(@.name=="audit-shipper")'
  check_output "initContainers 에 audit-shipper 가 있다" \
    "kubectl -n edge get deployment audit-api -o jsonpath='{.spec.template.spec.initContainers[*].name}'" 'audit-shipper' 4
  check_output "이미지 busybox:1.36" \
    "kubectl -n edge get deployment audit-api -o jsonpath='{.spec.template.spec.initContainers[$sel].image}'" '^busybox:1\.36$' 2
  check_output "restartPolicy: Always (네이티브 사이드카)" \
    "kubectl -n edge get deployment audit-api -o jsonpath='{.spec.template.spec.initContainers[$sel].restartPolicy}'" '^Always$' 4
  check_output "audit-logs 볼륨을 /var/log/audit 에 마운트" \
    "kubectl -n edge get deployment audit-api -o jsonpath='{range .spec.template.spec.initContainers[$sel].volumeMounts[*]}{.name}:{.mountPath} {end}'" 'audit-logs:/var/log/audit' 3
  check_output "본 컨테이너 api 는 그대로 남아 있다" \
    "kubectl -n edge get deployment audit-api -o jsonpath='{.spec.template.spec.containers[*].name}'" '(^| )api( |$)' 1
  wait_ready "-l app=audit-api" edge || true
  local ready
  ready=$(kubectl -n edge get pods -l app=audit-api --field-selector=status.phase=Running \
          -o jsonpath='{range .items[*]}{range .status.initContainerStatuses[?(@.name=="audit-shipper")]}{.ready}{end}/{range .status.containerStatuses[*]}{.ready}{end}{"\n"}{end}' 2>/dev/null | head -1)
  check_result "파드가 READY 2/2 (사이드카 ready=true · 본 컨테이너 ready=true)" \
    "$([[ "$ready" == "true/true" ]] && echo 0 || echo 1)" "현재: ${ready:-파드 없음}" 3
  check_output "사이드카 로그에 앱 로그가 보인다" \
    "kubectl -n edge logs deploy/audit-api -c audit-shipper --tail=5" 'audit event' 3
}

# ══════════════════════════════════════════════════════════════
# Q4 — NetworkPolicy
# ══════════════════════════════════════════════════════════════
q4_title() { echo "NetworkPolicy: only checkout may reach ledger [20 pts]"; }
q4_text() { cat <<'EOF'
In the payments namespace, the Deployment ledger (label app=ledger) is exposed
by the Service ledger on port 80. Lock it down with two NetworkPolicies.

  (1) deny-all-ingress
      - selects every Pod in payments and blocks all ingress

  (2) allow-checkout
      - applies to Pods labelled app=ledger
      - allows TCP 80 ONLY from Pods labelled app=checkout
        in the SAME namespace (payments)

Test Pods already exist:
  payments/checkout  (app=checkout)  -> must reach ledger
  payments/scanner   (app=scanner)   -> must be blocked
  partner/checkout   (app=checkout)  -> must be blocked (other namespace)

Verify:
  kubectl -n payments exec checkout -- wget -qO- -T 3 http://ledger
  kubectl -n payments exec scanner  -- wget -qO- -T 3 http://ledger
  kubectl -n partner  exec checkout -- wget -qO- -T 3 http://ledger.payments
EOF
}
q4_title_ko() { echo "NetworkPolicy — checkout 만 ledger 로 [20점]"; }
q4_text_ko() { cat <<'EOF'
payments 네임스페이스의 Deployment ledger(레이블 app=ledger)는
Service ledger 의 80 포트로 노출돼 있다. NetworkPolicy 두 개로 잠근다.

  (1) deny-all-ingress
      - payments 의 모든 파드를 고르고 Ingress 를 전부 막는다

  (2) allow-checkout
      - 대상: app=ledger 파드
      - 허용: 같은 네임스페이스(payments)의 app=checkout 파드에서 오는 TCP 80 만

테스트 파드가 이미 있다.
  payments/checkout  (app=checkout)  → ledger 에 닿아야 한다
  payments/scanner   (app=scanner)   → 막혀야 한다
  partner/checkout   (app=checkout)  → 막혀야 한다 (다른 네임스페이스)

[확인]
  kubectl -n payments exec checkout -- wget -qO- -T 3 http://ledger
  kubectl -n payments exec scanner  -- wget -qO- -T 3 http://ledger
  kubectl -n partner  exec checkout -- wget -qO- -T 3 http://ledger.payments
EOF
}
q4_hint() { cat <<'EOF'
# (1)
spec:
  podSelector: {}
  policyTypes: [Ingress]

# (2) from 에 podSelector 만 쓰면 '같은 네임스페이스' 의 파드만 뜻한다.
#     namespaceSelector: {} 를 함께 쓰면 모든 네임스페이스로 넓어진다 → partner 가 뚫린다
spec:
  podSelector: { matchLabels: { app: ledger } }
  policyTypes: [Ingress]
  ingress:
    - from: [ { podSelector: { matchLabels: { app: checkout } } } ]
      ports: [ { protocol: TCP, port: 80 } ]
EOF
}
q4_grade() {
  check "deny-all-ingress 존재" "kubectl -n payments get networkpolicy deny-all-ingress" 2
  check_output "deny-all-ingress 가 모든 파드를 고른다 (podSelector: {})" \
    "kubectl -n payments get networkpolicy deny-all-ingress -o jsonpath='{.spec.podSelector}'" '^\{\}$' 2
  check "allow-checkout 존재" "kubectl -n payments get networkpolicy allow-checkout" 2
  check_output "allow-checkout 대상이 app=ledger" \
    "kubectl -n payments get networkpolicy allow-checkout -o jsonpath='{.spec.podSelector.matchLabels.app}'" '^ledger$' 2
  check_output "허용 포트 TCP 80" \
    "kubectl -n payments get networkpolicy allow-checkout -o jsonpath='{.spec.ingress[*].ports[*].port}'" '(^| )80( |$)' 1

  wait_ready "-l app=ledger" payments || true
  local probe='wget -qO- -T 3 http://ledger.payments.svc.cluster.local 2>/dev/null'
  local a b c
  a=$(kubectl -n payments exec checkout -- sh -c "$probe" 2>/dev/null)
  b=$(kubectl -n payments exec scanner  -- sh -c "$probe" 2>/dev/null)
  c=$(kubectl -n partner  exec checkout -- sh -c "$probe" 2>/dev/null)
  local served=1; echo "$a" | grep -qi nginx && served=0
  check_result "payments/checkout → ledger 응답 (허용)" "$served" "응답 없음 — 허용 규칙 또는 ledger 파드 확인" 4
  # 허용 경로가 살아 있을 때만 '막힘' 을 믿는다 (ledger 가 죽어서 안 닿는 것과 구분)
  check_result "payments/scanner → ledger 차단" \
    "$([[ $served == 0 ]] && ! echo "$b" | grep -qi nginx && echo 0 || echo 1)" "scanner 가 닿는다 — deny-all-ingress 확인" 3
  check_result "partner/checkout → ledger 차단 (다른 네임스페이스)" \
    "$([[ $served == 0 ]] && ! echo "$c" | grep -qi nginx && echo 0 || echo 1)" "다른 네임스페이스가 닿는다 — namespaceSelector 를 넓게 쓰지 않았는지 확인" 4
}

# ══════════════════════════════════════════════════════════════
# Q5 — 기본 StorageClass 교체 + PVC
# ══════════════════════════════════════════════════════════════
q5_title() { echo "Replace the default StorageClass [20 pts]"; }
q5_text() { cat <<'EOF'
The cluster currently uses legacy-std as its default StorageClass.

  (a) Create a StorageClass named fast-local
        provisioner         kubernetes.io/no-provisioner
        volumeBindingMode   WaitForFirstConsumer
        reclaimPolicy       Retain

  (b) Make fast-local the ONLY default StorageClass of the cluster.
      Do not delete legacy-std.

  (c) In the warehouse namespace create a PVC named scratch
        request 1Gi, access mode ReadWriteOnce
      Do NOT set storageClassName in the PVC — it must receive fast-local
      because it is the default.

Verify:
  kubectl get storageclass                       -> only fast-local shows (default)
  kubectl -n warehouse get pvc scratch -o jsonpath='{.spec.storageClassName}'
EOF
}
q5_title_ko() { echo "기본 StorageClass 교체 + PVC [20점]"; }
q5_text_ko() { cat <<'EOF'
지금 클러스터의 기본 StorageClass 는 legacy-std 다.

  (a) fast-local StorageClass 를 만든다
        provisioner         kubernetes.io/no-provisioner
        volumeBindingMode   WaitForFirstConsumer
        reclaimPolicy       Retain

  (b) fast-local 을 클러스터의 유일한 기본 StorageClass 로 만든다.
      legacy-std 는 지우지 않는다.

  (c) warehouse 네임스페이스에 PVC scratch 를 만든다
        요청 1Gi, 접근 모드 ReadWriteOnce
      PVC 에 storageClassName 을 적지 않는다 — 기본이라서 fast-local 이 붙어야 한다.

[확인]
  kubectl get storageclass                       → fast-local 에만 (default)
  kubectl -n warehouse get pvc scratch -o jsonpath='{.spec.storageClassName}'
EOF
}
q5_hint() { cat <<'EOF'
# (a) 기본 지정은 애너테이션 한 줄
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-local
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain

# (b) 기존 기본을 해제한다 — 둘 다 true 면 '유일한 기본' 이 아니다
kubectl patch storageclass legacy-std \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# (c) PVC 는 기본 클래스가 정해진 '뒤에' 만든다. 먼저 만들면 legacy-std 가 붙는다
# WaitForFirstConsumer 라 파드가 쓰기 전까지 Pending 이 정상이다
EOF
}
q5_grade() {
  check "fast-local 존재" "kubectl get storageclass fast-local" 2
  check_output "provisioner kubernetes.io/no-provisioner" \
    "kubectl get storageclass fast-local -o jsonpath='{.provisioner}'" '^kubernetes\.io/no-provisioner$' 2
  check_output "volumeBindingMode WaitForFirstConsumer" \
    "kubectl get storageclass fast-local -o jsonpath='{.volumeBindingMode}'" '^WaitForFirstConsumer$' 2
  check_output "reclaimPolicy Retain" \
    "kubectl get storageclass fast-local -o jsonpath='{.reclaimPolicy}'" '^Retain$' 2
  check_output "fast-local 이 기본으로 지정됐다" \
    "kubectl get storageclass fast-local -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'" '^true$' 3
  check "legacy-std 는 지우지 않았다" "kubectl get storageclass legacy-std" 1
  local defaults
  defaults=$(kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}={.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null \
             | grep '=true$' | cut -d= -f1 | tr '\n' ' ')
  check_result "기본 StorageClass 가 fast-local 하나뿐 (현재: ${defaults:-없음})" \
    "$([[ "$defaults" == "fast-local " ]] && echo 0 || echo 1)" "다른 클래스의 is-default-class 를 false 로" 3
  check_output "PVC scratch 가 1Gi · ReadWriteOnce" \
    "kubectl -n warehouse get pvc scratch -o jsonpath='{.spec.resources.requests.storage}/{.spec.accessModes[0]}'" '^1Gi/ReadWriteOnce$' 2
  check_output "PVC 에 기본 클래스 fast-local 이 붙었다" \
    "kubectl -n warehouse get pvc scratch -o jsonpath='{.spec.storageClassName}'" '^fast-local$' 3
}

exam_main "$@"
