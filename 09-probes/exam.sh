#!/usr/bin/env bash
# CKA 9강 실습 — 파드가 건강한지 확인하기: probe (순차 진행형)
# 사용법: bash exam.sh start  →  풀고  →  bash exam.sh check  →  ...
# 모든 리소스는 probe-lab 네임스페이스 안에 만든다.
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 9강 실습 — probe (CrashLoopBackOff · liveness · readiness · startup)"
EXAM_NQ=6

NS=probe-lab
OUT_DIR=/tmp/09-probes
TOKEN_FILE="$WORK_DIR/.q1-token"
SICK_FILE="$WORK_DIR/.q3-pod"       # Q3 — 일부러 아프게 만든 파드 이름

# 파일 한 줄을 공백 없이 읽는다 (채점용)
fval() { [[ -f "$1" ]] && tr -d ' \t\r\n' < "$1" || true; }
_rand() { LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c "${1:-6}"; }

# Deployment 의 현재 리비전 ReplicaSet 이 쓰는 pod-template-hash
#   옛 RS 의 파드(CrashLoop 중이거나 지우는 중)는 채점에서 뺀다
cur_hash() {
  local rev
  rev=$(kubectl -n "$NS" get deployment "$1" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null)
  [[ -z "$rev" ]] && return 0
  kubectl -n "$NS" get rs -o jsonpath='{range .items[*]}{.metadata.ownerReferences[0].name}{"|"}{.metadata.annotations.deployment\.kubernetes\.io/revision}{"|"}{.metadata.labels.pod-template-hash}{"\n"}{end}' 2>/dev/null \
    | awk -F'|' -v d="$1" -v r="$rev" '$1==d && $2==r {print $3; exit}'
}
# 현재 RS 의 파드 중 지우는 중이 아닌 것 — 한 줄에 "이름|Ready|재시작합계"
cur_pods() {
  local h; h=$(cur_hash "$1")
  [[ -z "$h" ]] && return 0
  kubectl -n "$NS" get pods -l "pod-template-hash=$h" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.deletionTimestamp}{"|"}{.status.conditions[?(@.type=="Ready")].status}{"|"}{.status.containerStatuses[*].restartCount}{"\n"}{end}' 2>/dev/null \
    | awk -F'|' '$1!="" && $2=="" { s=0; n=split($4,a," "); for(i=1;i<=n;i++) s+=a[i]; print $1"|"$3"|"s }'
}
# 현재 RS 파드가 want 개, 모두 Ready, 재시작 0 인지 — check_result 두 개를 남긴다
grade_cur_pods() {   # grade_cur_pods <deploy> <want>
  local d="$1" want="$2" lines name ready rs n=0 nready=0 nrestart=0 bad=""
  lines=$(cur_pods "$d")
  while IFS='|' read -r name ready rs; do
    [[ -z "$name" ]] && continue
    n=$((n+1))
    [[ "$ready" == "True" ]] && nready=$((nready+1))
    if [[ "${rs:-0}" != "0" ]]; then nrestart=$((nrestart+1)); bad+="$name=${rs} "; fi
  done <<< "$lines"
  check_result "현재 리비전 파드 ${want}개가 모두 Ready (${nready}/${n})" \
    "$([[ "$n" == "$want" && "$nready" == "$want" ]] && echo 0 || echo 1)" \
    "Ready ${nready}개 / 현재 리비전 파드 ${n}개 — 아직 뜨는 중이면 잠시 뒤 다시 check"
  check_result "현재 리비전 파드가 한 번도 재시작하지 않았다 (RESTARTS 0)" \
    "$([[ "$n" -gt 0 && "$nrestart" == "0" ]] && echo 0 || echo 1)" \
    "${bad:-현재 리비전 파드가 없음} — probe 가 틀리면 kubelet 이 재시작한다"
}
dep_rev() {
  local r; r=$(kubectl -n "$NS" get deployment "$1" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null)
  r="${r//[^0-9]/}"; echo "${r:-0}"
}

# ══════════════════════════════════════════════════════════════
exam_cleanup() {
  kdel namespace "$NS" --wait=false
  rmf "$OUT_DIR"
  rm -f "$TOKEN_FILE" "$SICK_FILE"
  echo "  $NS 네임스페이스 · $OUT_DIR 삭제"
}
exam_setup() {
  kubectl create namespace "$NS" &>/dev/null
  mkdir -p "$OUT_DIR"

  # Q1 — 계속 죽는 파드(flaky) + 한 번 돌고 끝나는 파드(tidy). 토큰은 시작할 때마다 바뀐다
  local token; token="boot-$(_rand 6)"
  echo "$token" > "$TOKEN_FILE"
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: flaky
  namespace: $NS
  labels: { app: flaky }
spec:
  terminationGracePeriodSeconds: 1
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo loading config; echo TOKEN=$token; sleep 4; echo giving up; exit 3"]
---
apiVersion: v1
kind: Pod
metadata:
  name: tidy
  namespace: $NS
  labels: { app: tidy }
spec:
  restartPolicy: OnFailure
  terminationGracePeriodSeconds: 1
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo cleaning; sleep 2; exit 0"]
YAML
  echo "  flaky(계속 죽음) · tidy(한 번 돌고 끝) 파드 배치 (Q1)"

  # Q2 — probe 없는 Deployment
  kubectl -n "$NS" create deployment storefront --image=nginx:1.28 --replicas=2 &>/dev/null
  echo "  storefront Deployment 배치 — probe 없음 (Q2)"

  # Q3 — readinessProbe 가 달린 catalog + Service. 파드 하나는 Q3 에 들어갈 때 아프게 만든다
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: $NS
  labels: { app: catalog }
spec:
  replicas: 3
  selector: { matchLabels: { app: catalog } }
  template:
    metadata:
      labels: { app: catalog }
    spec:
      containers:
        - name: nginx
          image: nginx:1.28
          ports: [{ containerPort: 80 }]
          readinessProbe:
            httpGet: { path: /, port: 80 }
            periodSeconds: 3
---
apiVersion: v1
kind: Service
metadata:
  name: catalog
  namespace: $NS
spec:
  selector: { app: catalog }
  ports: [{ port: 80, targetPort: 80 }]
YAML
  echo "  catalog Deployment(3개, readiness) + Service 배치 (Q3)"

  # Q4 — 뜨는 데 45초 걸리는데 liveness 는 15초면 판정 → 영영 못 뜬다
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger
  namespace: $NS
  labels: { app: ledger }
spec:
  replicas: 1
  selector: { matchLabels: { app: ledger } }
  template:
    metadata:
      labels: { app: ledger }
    spec:
      terminationGracePeriodSeconds: 1      # sh 는 SIGTERM 을 무시한다 — 재시작이 30초씩 걸리지 않게
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "echo warming up; sleep 45; touch /tmp/started; echo started; sleep 36000"]
          livenessProbe:
            exec: { command: ["cat", "/tmp/started"] }
            periodSeconds: 5
            failureThreshold: 3
YAML
  echo "  ledger Deployment 배치 — 느리게 뜨는데 liveness 만 있음 (Q4)"

  # Q5 — liveness 경로가 틀려 계속 재시작되는 nginx
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway
  namespace: $NS
  labels: { app: gateway }
spec:
  replicas: 2
  selector: { matchLabels: { app: gateway } }
  template:
    metadata:
      labels: { app: gateway }
    spec:
      containers:
        - name: nginx
          image: nginx:1.28
          ports: [{ containerPort: 80 }]
          livenessProbe:
            httpGet: { path: /health, port: 80 }
            periodSeconds: 5
            failureThreshold: 2
YAML
  echo "  gateway Deployment 배치 — liveness 가 일부러 틀림 (Q5)"

  # Q6 — 파드를 기다리는 Service (파드는 학생이 만든다)
  kubectl -n "$NS" create service clusterip relay --tcp=80:80 &>/dev/null   # 셀렉터 app=relay
  echo "  relay Service 배치 — 아직 파드 없음 (Q6)"
}

# ══════════════════════════════════════════════════════════════
# Q1 — restartPolicy · CrashLoopBackOff 읽기
# ══════════════════════════════════════════════════════════════
q1_title() { echo "Read a CrashLoopBackOff Pod"; }
q1_text() { cat <<'EOF'
Two Pods run in the namespace probe-lab: flaky and tidy.
flaky keeps restarting. Find the following and save each answer as a
single line in the given file.

  (a) exit code of the last terminated container of flaky
                                          -> /tmp/09-probes/exit-code.txt
  (b) reason of that last termination (Last State)
                                          -> /tmp/09-probes/reason.txt
  (c) restartPolicy of the Pod flaky      -> /tmp/09-probes/policy.txt
  (d) the value after TOKEN= that the previous (crashed) container
      printed to its log (only the value, e.g. boot-abc123)
                                          -> /tmp/09-probes/token.txt
  (e) the STATUS that kubectl get shows for the Pod tidy, which has
      finished and is not restarted       -> /tmp/09-probes/tidy-status.txt

Do not change or delete the Pods.

Verify:
  cat /tmp/09-probes/*.txt
EOF
}
q1_title_ko() { echo "CrashLoopBackOff 파드 읽기 — 종료 코드 · 사유 · restartPolicy · 로그"; }
q1_text_ko() { cat <<'EOF'
probe-lab 네임스페이스에 flaky 와 tidy 파드가 있다.
flaky 는 계속 재시작된다. 아래를 찾아 각 파일에 한 줄로 저장하시오.

  (a) flaky 의 마지막으로 끝난 컨테이너의 종료 코드(Exit Code)
                                          → /tmp/09-probes/exit-code.txt
  (b) 그 종료의 사유 (Last State 의 Reason)
                                          → /tmp/09-probes/reason.txt
  (c) flaky 파드의 restartPolicy          → /tmp/09-probes/policy.txt
  (d) 직전에 죽은 컨테이너가 로그에 찍은 TOKEN= 뒤의 값
      (값만. 예: boot-abc123)              → /tmp/09-probes/token.txt
  (e) 이미 끝났고 다시 뜨지 않는 tidy 파드를 kubectl get 으로 봤을 때의
      STATUS                              → /tmp/09-probes/tidy-status.txt

파드는 고치거나 지우지 않는다.

[확인]
  cat /tmp/09-probes/*.txt
EOF
}
q1_grade() {
  local code reason policy token tst
  code=$(kubectl -n "$NS" get pod flaky -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}' 2>/dev/null)
  [[ -z "$code" ]] && code=$(kubectl -n "$NS" get pod flaky -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null)
  reason=$(kubectl -n "$NS" get pod flaky -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null)
  [[ -z "$reason" ]] && reason=$(kubectl -n "$NS" get pod flaky -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null)
  policy=$(kubectl -n "$NS" get pod flaky -o jsonpath='{.spec.restartPolicy}' 2>/dev/null)
  tst=$(kubectl -n "$NS" get pod tidy -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null)
  token=$(cat "$TOKEN_FILE" 2>/dev/null)
  check_result "(a) exit-code.txt = 마지막 종료 코드" \
    "$([[ -n "$code" && "$(fval $OUT_DIR/exit-code.txt)" == "$code" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/exit-code.txt)'"
  check_result "(b) reason.txt = Last State 의 Reason" \
    "$([[ -n "$reason" && "$(fval $OUT_DIR/reason.txt)" == "$reason" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/reason.txt)' — State 의 CrashLoopBackOff 가 아니라 Last State 를 본다"
  check_result "(c) policy.txt = flaky 의 restartPolicy" \
    "$([[ -n "$policy" && "$(fval $OUT_DIR/policy.txt)" == "$policy" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/policy.txt)'"
  check_result "(d) token.txt = 로그의 TOKEN 값 (값만)" \
    "$([[ -n "$token" && "$(fval $OUT_DIR/token.txt)" == "$token" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/token.txt)'"
  check_result "(e) tidy-status.txt = tidy 의 STATUS" \
    "$([[ -n "$tst" && "$(fval $OUT_DIR/tidy-status.txt)" == "$tst" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/tidy-status.txt)'"
  check_result "flaky 파드를 지우지 않았다 (RESTARTS 가 쌓여 있다)" \
    "$(r=$(kubectl -n "$NS" get pod flaky -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null); [[ "${r:-0}" =~ ^[0-9]+$ && "${r:-0}" -ge 1 ]] && echo 0 || echo 1)" \
    "flaky 가 없거나 아직 한 번도 재시작하지 않았다 — 지웠다면 bash exam.sh clean 후 다시 start"
}
q1_hint() { cat <<'EOF'
kubectl -n probe-lab get pods                         # flaky: CrashLoopBackOff · tidy: Completed
kubectl -n probe-lab describe pod flaky | grep -A9 '^    State'
#   State: Waiting (CrashLoopBackOff)  ← 지금 쉬는 중
#   Last State: Terminated  Reason: Error  Exit Code: 3   ← 이것을 적는다

J='{.status.containerStatuses[0].lastState.terminated'
kubectl -n probe-lab get pod flaky -o jsonpath="$J.exitCode}" > /tmp/09-probes/exit-code.txt
kubectl -n probe-lab get pod flaky -o jsonpath="$J.reason}"   > /tmp/09-probes/reason.txt
kubectl -n probe-lab get pod flaky -o jsonpath='{.spec.restartPolicy}' > /tmp/09-probes/policy.txt

# 직전 컨테이너의 로그 — 막 다시 떴다면 지금 컨테이너 로그는 비어 있을 수 있다
kubectl -n probe-lab logs flaky --previous | grep TOKEN= | cut -d= -f2 > /tmp/09-probes/token.txt

# OnFailure 는 0 으로 끝나면 다시 띄우지 않는다
kubectl -n probe-lab get pod tidy                     # STATUS 칸
echo Completed > /tmp/09-probes/tidy-status.txt
EOF
}

# ══════════════════════════════════════════════════════════════
# Q2 — Deployment 에 liveness(httpGet) 달기
# ══════════════════════════════════════════════════════════════
q2_title() { echo "Add an HTTP livenessProbe to a Deployment"; }
q2_text() { cat <<'EOF'
The Deployment storefront (nginx:1.28, 2 replicas, container nginx) in the
namespace probe-lab has no probes.

Add a livenessProbe to its container:

  type                  httpGet
  path                  /
  port                  80
  initialDelaySeconds   5
  periodSeconds         10

Do not delete the Deployment. After the rollout, both Pods must be Ready
and must not restart. Wait about 40 seconds after the rollout before
checking, so that the probe has run several times.

Verify:
  kubectl -n probe-lab rollout status deployment/storefront
  kubectl -n probe-lab describe deployment storefront | grep Liveness
  kubectl -n probe-lab get pods -l app=storefront
EOF
}
q2_title_ko() { echo "Deployment 에 liveness(httpGet) 달기"; }
q2_text_ko() { cat <<'EOF'
probe-lab 네임스페이스의 storefront Deployment(nginx:1.28, 2개,
컨테이너 이름 nginx)에는 probe 가 없다.

컨테이너에 livenessProbe 를 추가하시오.

  방법                  httpGet
  path                  /
  port                  80
  initialDelaySeconds   5
  periodSeconds         10

Deployment 를 지우지 않는다. 롤아웃이 끝난 뒤 파드 2개가 Ready 이고
재시작하지 않아야 한다. probe 가 몇 번 돌도록 롤아웃이 끝나고 40초쯤
기다린 뒤 채점한다.

[확인]
  kubectl -n probe-lab rollout status deployment/storefront
  kubectl -n probe-lab describe deployment storefront | grep Liveness
  kubectl -n probe-lab get pods -l app=storefront
EOF
}
q2_grade() {
  local P="{.spec.template.spec.containers[0].livenessProbe"
  check "storefront Deployment 존재" "kubectl -n $NS get deployment storefront"
  check_output "liveness 방법 httpGet · path /" \
    "kubectl -n $NS get deployment storefront -o jsonpath='$P.httpGet.path}'" '^/$'
  check_output "liveness port 80" \
    "kubectl -n $NS get deployment storefront -o jsonpath='$P.httpGet.port}'" '^80$'
  check_output "initialDelaySeconds 5" \
    "kubectl -n $NS get deployment storefront -o jsonpath='$P.initialDelaySeconds}'" '^5$'
  check_output "periodSeconds 10" \
    "kubectl -n $NS get deployment storefront -o jsonpath='$P.periodSeconds}'" '^10$'
  check_result "Deployment 를 지우지 않고 고쳤다 (revision $(dep_rev storefront) ≥ 2)" \
    "$([[ "$(dep_rev storefront)" -ge 2 ]] && echo 0 || echo 1)" "지우고 새로 만들면 revision 이 1 부터 다시 시작한다"
  local h; h=$(cur_hash storefront)
  [[ -n "$h" ]] && wait_ready "-l pod-template-hash=$h" "$NS"
  grade_cur_pods storefront 2
}
q2_hint() { cat <<'EOF'
kubectl explain deployment.spec.template.spec.containers.livenessProbe.httpGet

kubectl -n probe-lab edit deployment storefront
#   spec.template.spec.containers[0] 아래, image 와 같은 높이에:
#   livenessProbe:
#     httpGet:
#       path: /
#       port: 80
#     initialDelaySeconds: 5
#     periodSeconds: 10

# 또는 한 줄로
kubectl -n probe-lab patch deployment storefront --type=json -p '[{"op":"add",
  "path":"/spec/template/spec/containers/0/livenessProbe",
  "value":{"httpGet":{"path":"/","port":80},"initialDelaySeconds":5,"periodSeconds":10}}]'

kubectl -n probe-lab rollout status deployment/storefront
sleep 40; kubectl -n probe-lab get pods -l app=storefront     # RESTARTS 0
EOF
}

# ══════════════════════════════════════════════════════════════
# Q3 — readiness 실패 → Endpoints 에서 빠진다 → 되살리기
# ══════════════════════════════════════════════════════════════
q3_enter() {
  # catalog 3개가 다 뜬 뒤 하나를 골라 index.html 을 지운다 → / 가 403 → readiness 실패
  kubectl -n "$NS" rollout status deployment/catalog --timeout=120s &>/dev/null || true
  local pods p
  pods=$(kubectl -n "$NS" get pods -l app=catalog \
    -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.deletionTimestamp}{"|"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
    | awk -F'|' '$1!="" && $2=="" && $3=="True" {print $1}')
  local arr=($pods)
  if (( ${#arr[@]} == 0 )); then
    # 엔진의 enter 오류 파일에 남기면 "들어간 것" 으로 치지 않고 다음 show 때 다시 부른다
    echo "catalog 파드가 아직 Ready 가 아니다" >> "$ENTER_ERR"; return 0
  fi
  p="${arr[RANDOM % ${#arr[@]}]}"
  if kubectl -n "$NS" exec "$p" -c nginx -- rm -f /usr/share/nginx/html/index.html &>/dev/null; then
    echo "$p" > "$SICK_FILE"
    echo "  catalog 파드 하나를 아프게 만들었습니다 — 몇 초 뒤 0/1 이 됩니다"
  else
    echo "catalog 파드($p)에 exec 하지 못했다" >> "$ENTER_ERR"
  fi
}
q3_title() { echo "readinessProbe and Endpoints"; }
q3_text() { cat <<'EOF'
In the namespace probe-lab, the Deployment catalog (3 replicas) has a
readinessProbe (httpGet / on port 80) and is exposed by the Service catalog.
One of its Pods is Running but no longer receives traffic from the Service.

  (a) Find that Pod and save its name to /tmp/09-probes/not-ready.txt
  (b) Make that SAME Pod receive traffic again WITHOUT deleting or
      restarting it: nginx returns 403 for / because the file
      /usr/share/nginx/html/index.html is missing in that Pod.
      Create the file again (any content).

Final state: the Service catalog has 3 endpoints and that Pod still has
RESTARTS 0.

Verify:
  kubectl -n probe-lab get pods -l app=catalog
  kubectl -n probe-lab get endpoints catalog
EOF
}
q3_title_ko() { echo "readiness 실패 → Endpoints 에서 빠진 파드 찾고 되살리기"; }
q3_text_ko() { cat <<'EOF'
probe-lab 네임스페이스의 catalog Deployment(3개)에는 readinessProbe
(포트 80 의 / 에 httpGet)가 달려 있고, catalog Service 가 이 파드들로 보낸다.
파드 하나가 Running 인데 Service 의 요청을 받지 못하고 있다.

  (a) 그 파드를 찾아 이름을 /tmp/09-probes/not-ready.txt 에 저장하시오.
  (b) 그 파드를 지우거나 재시작하지 말고 다시 요청을 받게 하시오.
      그 파드 안에 /usr/share/nginx/html/index.html 이 없어서 nginx 가
      / 에 403 을 돌려준다. 파일을 다시 만든다 (내용은 아무거나).

최종 상태: catalog Service 의 Endpoints 가 3개이고, 그 파드의 RESTARTS 는
여전히 0 이다.

[확인]
  kubectl -n probe-lab get pods -l app=catalog
  kubectl -n probe-lab get endpoints catalog
EOF
}
q3_grade() {
  local sick ip rs n_ep
  sick=$(cat "$SICK_FILE" 2>/dev/null)
  check_result "(a) not-ready.txt = Endpoints 에서 빠졌던 파드 이름" \
    "$([[ -n "$sick" && "$(fval $OUT_DIR/not-ready.txt)" == "$sick" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/not-ready.txt)'$([[ -z "$sick" ]] && echo ' — 시작 기록 없음: bash exam.sh show 로 Q3 를 다시 연다')"
  if [[ -n "$sick" ]] && kubectl -n "$NS" get pod "$sick" &>/dev/null; then
    check_result "(b) 그 파드를 지우지 않았다 (같은 이름이 남아 있다)" 0
    wait_ready "$sick" "$NS"
    check_output "(b) 그 파드가 다시 Ready" \
      "kubectl -n $NS get pod $sick -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" '^True$'
    rs=$(kubectl -n "$NS" get pod "$sick" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    check_result "(b) 재시작 없이 되살아났다 (RESTARTS ${rs:-?})" \
      "$([[ "$rs" == "0" ]] && echo 0 || echo 1)" "readiness 는 재시작하지 않는다 — 파일만 만들면 몇 초 뒤 돌아온다"
    ip=$(kubectl -n "$NS" get pod "$sick" -o jsonpath='{.status.podIP}' 2>/dev/null); ip="${ip:-없음}"
    check_output "(b) Endpoints 에 그 파드 IP(${ip:-?})가 돌아왔다" \
      "kubectl -n $NS get endpoints catalog -o jsonpath='{.subsets[*].addresses[*].ip}'" "(^| )${ip//./\\.}( |$)"
  else
    check_result "(b) 그 파드를 지우지 않았다 (같은 이름이 남아 있다)" 1 "파드 '${sick:-?}' 가 없다 — 지우면 새 이름의 파드가 생긴다"
    check_result "(b) 그 파드가 다시 Ready" 1 "파드가 없음"
    check_result "(b) 재시작 없이 되살아났다" 1 "파드가 없음"
    check_result "(b) Endpoints 에 그 파드 IP 가 돌아왔다" 1 "파드가 없음"
  fi
  n_ep=$(kubectl -n "$NS" get endpoints catalog -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
  check_result "catalog Endpoints 3개 (${n_ep:-0}개)" \
    "$([[ "$n_ep" == "3" ]] && echo 0 || echo 1)"
}
q3_hint() { cat <<'EOF'
kubectl -n probe-lab get pods -l app=catalog -o wide   # READY 0/1 인 파드 · IP
kubectl -n probe-lab get endpoints catalog             # 그 IP 만 빠져 있다

P=$(kubectl -n probe-lab get pods -l app=catalog --no-headers | awk '$2=="0/1"{print $1}')
echo $P
kubectl -n probe-lab describe pod $P | grep Unhealthy  # statuscode: 403
echo $P > /tmp/09-probes/not-ready.txt

# 지우지 말고 파일만 되돌린다 — 다음 검사(3초)에 성공하면 1/1, Endpoints 에도 돌아온다
kubectl -n probe-lab exec $P -- sh -c 'echo ok > /usr/share/nginx/html/index.html'
kubectl -n probe-lab get endpoints catalog
EOF
}

# ══════════════════════════════════════════════════════════════
# Q4 — startupProbe 로 느린 앱에 유예 주기
# ══════════════════════════════════════════════════════════════
q4_title() { echo "Give a slow-starting app a startupProbe"; }
q4_text() { cat <<'EOF'
The Deployment ledger in the namespace probe-lab never becomes Ready.
Its app needs about 45 seconds to start (it then creates /tmp/started),
but its livenessProbe (exec cat /tmp/started, every 5s, 3 failures) kills
the container before it has finished starting.

Without deleting the Deployment and without removing or changing the
livenessProbe, add a startupProbe to the container:

  type        exec   command: cat /tmp/started
  budget      failureThreshold x periodSeconds >= 60 seconds
              (e.g. periodSeconds 10, failureThreshold 6)

The new Pod must become Ready with RESTARTS 0. It takes about one minute
after the change: run  rollout status  and check after it finishes.

Verify:
  kubectl -n probe-lab rollout status deployment/ledger --timeout=120s
  kubectl -n probe-lab get pods -l app=ledger
EOF
}
q4_title_ko() { echo "느리게 뜨는 앱에 startupProbe 로 유예 주기"; }
q4_text_ko() { cat <<'EOF'
probe-lab 네임스페이스의 ledger Deployment 가 끝내 Ready 가 되지 않는다.
앱은 뜨는 데 45초쯤 걸리고(다 뜨면 /tmp/started 를 만든다), 그런데
livenessProbe(exec cat /tmp/started, 5초마다, 3번 실패)가 다 뜨기 전에
컨테이너를 죽인다.

Deployment 를 지우지 말고, livenessProbe 는 지우거나 바꾸지 말고,
컨테이너에 startupProbe 를 추가하시오.

  방법      exec   명령: cat /tmp/started
  유예      failureThreshold × periodSeconds ≥ 60초
            (예: periodSeconds 10, failureThreshold 6)

새 파드가 RESTARTS 0 으로 Ready 가 되어야 한다. 고친 뒤 1분쯤 걸린다 —
rollout status 가 끝난 다음 채점한다. (채점도 최대 75초까지 기다린다)

[확인]
  kubectl -n probe-lab rollout status deployment/ledger --timeout=120s
  kubectl -n probe-lab get pods -l app=ledger
EOF
}
q4_grade() {
  local S="{.spec.template.spec.containers[0].startupProbe" L="{.spec.template.spec.containers[0].livenessProbe"
  local per fth
  check "ledger Deployment 존재" "kubectl -n $NS get deployment ledger"
  check_output "startupProbe 가 exec cat /tmp/started" \
    "kubectl -n $NS get deployment ledger -o jsonpath='$S.exec.command[*]}'" '^cat /tmp/started$'
  per=$(kubectl -n "$NS" get deployment ledger -o jsonpath="$S.periodSeconds}" 2>/dev/null)
  fth=$(kubectl -n "$NS" get deployment ledger -o jsonpath="$S.failureThreshold}" 2>/dev/null)
  per="${per//[^0-9]/}"; fth="${fth//[^0-9]/}"
  check_result "유예 failureThreshold × periodSeconds ≥ 60초 (${fth:-?} × ${per:-?})" \
    "$([[ -n "$per" && -n "$fth" ]] && (( per * fth >= 60 )) && echo 0 || echo 1)" \
    "45초 안에 판정이 끝나면 다시 죽는다"
  check_output "livenessProbe 는 그대로 (exec cat /tmp/started · 5초 · 3번)" \
    "kubectl -n $NS get deployment ledger -o jsonpath='$L.exec.command[*]}|$L.periodSeconds}|$L.failureThreshold}'" '^cat /tmp/started\|5\|3$'
  check_result "Deployment 를 지우지 않고 고쳤다 (revision $(dep_rev ledger) ≥ 2)" \
    "$([[ "$(dep_rev ledger)" -ge 2 ]] && echo 0 || echo 1)" "지우고 새로 만들면 revision 이 1 부터 다시 시작한다"
  local h; h=$(cur_hash ledger)
  # 앱이 45초 걸려 뜬다 — 이 문제만 기다림을 길게
  [[ -n "$h" ]] && EXAM_WAIT=75 wait_ready "-l pod-template-hash=$h" "$NS"
  grade_cur_pods ledger 1
}
q4_hint() { cat <<'EOF'
kubectl -n probe-lab get pods -l app=ledger          # RESTARTS 가 오르고 CrashLoopBackOff
kubectl -n probe-lab describe pod -l app=ledger | grep -E 'Unhealthy|Killing'

kubectl -n probe-lab edit deployment ledger
#   livenessProbe 와 같은 높이에 추가:
#   startupProbe:
#     exec:
#       command: ["cat", "/tmp/started"]
#     periodSeconds: 10
#     failureThreshold: 6        # 10 × 6 = 60초까지 기다려 준다. 성공하면 liveness 가 넘겨받는다

# 또는 한 줄로
kubectl -n probe-lab patch deployment ledger --type=json -p '[{"op":"add",
  "path":"/spec/template/spec/containers/0/startupProbe",
  "value":{"exec":{"command":["cat","/tmp/started"]},"periodSeconds":10,"failureThreshold":6}}]'

kubectl -n probe-lab rollout status deployment/ledger --timeout=120s    # 1분쯤
kubectl -n probe-lab get pods -l app=ledger          # 새 파드 1/1 · RESTARTS 0
EOF
}

# ══════════════════════════════════════════════════════════════
# Q5 — 틀린 liveness 고치기
# ══════════════════════════════════════════════════════════════
q5_title() { echo "Fix a wrong livenessProbe"; }
q5_text() { cat <<'EOF'
The Pods of the Deployment gateway (nginx:1.28, 2 replicas) in the
namespace probe-lab keep restarting, although nginx itself is fine.

  (a) Find the HTTP status code that the failing liveness check gets
      (from the Unhealthy events) and save only the number to
      /tmp/09-probes/gateway-status.txt
  (b) Fix the livenessProbe so that it checks the path / on port 80
      (nginx serves its default page there). Keep it an httpGet
      livenessProbe. Do not delete the Deployment.

Final state: 2 Pods of the new revision Ready, with RESTARTS 0.
Wait about 30 seconds after the rollout before checking.

Verify:
  kubectl -n probe-lab describe pod -l app=gateway | grep Unhealthy
  kubectl -n probe-lab get pods -l app=gateway
EOF
}
q5_title_ko() { echo "틀린 liveness 고치기 — 계속 재시작되는 Deployment"; }
q5_text_ko() { cat <<'EOF'
probe-lab 네임스페이스의 gateway Deployment(nginx:1.28, 2개)의 파드가
nginx 는 멀쩡한데 계속 재시작된다.

  (a) 실패하는 liveness 검사가 받은 HTTP 응답 코드를 (Unhealthy 이벤트에서)
      찾아 숫자만 /tmp/09-probes/gateway-status.txt 에 저장하시오.
  (b) livenessProbe 가 포트 80 의 / 를 검사하도록 고치시오
      (nginx 는 거기서 기본 페이지를 내보낸다). httpGet livenessProbe 는
      그대로 유지한다. Deployment 를 지우지 않는다.

최종 상태: 새 리비전 파드 2개가 Ready, RESTARTS 0.
롤아웃이 끝나고 30초쯤 기다린 뒤 채점한다.

[확인]
  kubectl -n probe-lab describe pod -l app=gateway | grep Unhealthy
  kubectl -n probe-lab get pods -l app=gateway
EOF
}
q5_grade() {
  local P="{.spec.template.spec.containers[0].livenessProbe"
  check_result "(a) gateway-status.txt = 404" \
    "$([[ "$(fval $OUT_DIR/gateway-status.txt)" == "404" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/gateway-status.txt)'"
  check "gateway Deployment 존재" "kubectl -n $NS get deployment gateway"
  check_output "(b) liveness 가 httpGet · path /" \
    "kubectl -n $NS get deployment gateway -o jsonpath='$P.httpGet.path}'" '^/$'
  check_output "(b) liveness port 80" \
    "kubectl -n $NS get deployment gateway -o jsonpath='$P.httpGet.port}'" '^80$'
  check_result "(b) Deployment 를 지우지 않고 고쳤다 (revision $(dep_rev gateway) ≥ 2)" \
    "$([[ "$(dep_rev gateway)" -ge 2 ]] && echo 0 || echo 1)" "지우고 새로 만들면 revision 이 1 부터 다시 시작한다"
  local h; h=$(cur_hash gateway)
  [[ -n "$h" ]] && wait_ready "-l pod-template-hash=$h" "$NS"
  grade_cur_pods gateway 2
}
q5_hint() { cat <<'EOF'
kubectl -n probe-lab get pods -l app=gateway                       # Running 인데 RESTARTS 가 오른다
kubectl -n probe-lab describe pod -l app=gateway | grep -E 'Liveness|Unhealthy|Killing'
#   Liveness probe failed: HTTP probe failed with statuscode: 404   ← 포트는 맞고 경로가 틀림
echo 404 > /tmp/09-probes/gateway-status.txt

# 파드가 아니라 Deployment 를 고친다 → 롤링 업데이트로 새 파드에 반영
kubectl -n probe-lab patch deployment gateway --type=json -p '[{"op":"replace",
  "path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/"}]'
#   또는 kubectl -n probe-lab edit deployment gateway   (path: /health → /)

kubectl -n probe-lab rollout status deployment/gateway
sleep 30; kubectl -n probe-lab get pods -l app=gateway             # 새 파드 RESTARTS 0
EOF
}

# ══════════════════════════════════════════════════════════════
# Q6 — tcpSocket readiness · liveness 를 단 파드 만들기
# ══════════════════════════════════════════════════════════════
q6_title() { echo "Create a Pod with tcpSocket probes"; }
q6_text() { cat <<'EOF'
The Service relay already exists in the namespace probe-lab
(selector app=relay, port 80) but has no endpoints yet.

Create a Pod named relay in probe-lab:

  image     nginx:1.28
  label     app=relay
  readinessProbe   tcpSocket port 80, initialDelaySeconds 5, periodSeconds 10
  livenessProbe    tcpSocket port 80, periodSeconds 20

The Pod must be Ready and its IP must appear in the endpoints of the
Service relay.

Verify:
  kubectl -n probe-lab describe pod relay | grep -E 'Liveness|Readiness'
  kubectl -n probe-lab get endpoints relay
EOF
}
q6_title_ko() { echo "tcpSocket readiness · liveness 를 단 파드 만들기"; }
q6_text_ko() { cat <<'EOF'
probe-lab 네임스페이스에 relay Service(셀렉터 app=relay, 포트 80)가
이미 있는데 아직 Endpoints 가 비어 있다.

probe-lab 에 relay 파드를 만드시오.

  이미지    nginx:1.28
  라벨      app=relay
  readinessProbe   tcpSocket 포트 80, initialDelaySeconds 5, periodSeconds 10
  livenessProbe    tcpSocket 포트 80, periodSeconds 20

파드는 Ready 여야 하고, 그 IP 가 relay Service 의 Endpoints 에 들어가야 한다.
(readiness 첫 검사가 5초 뒤라 만든 직후 몇 초는 0/1 이다)

[확인]
  kubectl -n probe-lab describe pod relay | grep -E 'Liveness|Readiness'
  kubectl -n probe-lab get endpoints relay
EOF
}
q6_grade() {
  local R="{.spec.containers[0].readinessProbe" L="{.spec.containers[0].livenessProbe" ip
  check "relay 파드 존재" "kubectl -n $NS get pod relay"
  check_output "이미지 nginx:1.28" \
    "kubectl -n $NS get pod relay -o jsonpath='{.spec.containers[0].image}'" '^(docker\.io/library/)?nginx:1\.28$'
  check_output "라벨 app=relay" \
    "kubectl -n $NS get pod relay -o jsonpath='{.metadata.labels.app}'" '^relay$'
  check_output "readiness tcpSocket 포트 80" \
    "kubectl -n $NS get pod relay -o jsonpath='$R.tcpSocket.port}'" '^80$'
  check_output "readiness initialDelaySeconds 5 · periodSeconds 10" \
    "kubectl -n $NS get pod relay -o jsonpath='$R.initialDelaySeconds}/$R.periodSeconds}'" '^5/10$'
  check_output "liveness tcpSocket 포트 80" \
    "kubectl -n $NS get pod relay -o jsonpath='$L.tcpSocket.port}'" '^80$'
  check_output "liveness periodSeconds 20" \
    "kubectl -n $NS get pod relay -o jsonpath='$L.periodSeconds}'" '^20$'
  wait_ready relay "$NS"
  check_output "Ready" \
    "kubectl -n $NS get pod relay -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" '^True$'
  ip=$(kubectl -n "$NS" get pod relay -o jsonpath='{.status.podIP}' 2>/dev/null); ip="${ip:-없음}"
  check_output "relay Endpoints 에 파드 IP(${ip:-?})" \
    "kubectl -n $NS get endpoints relay -o jsonpath='{.subsets[*].addresses[*].ip}'" "(^| )${ip//./\\.}( |$)"
}
q6_hint() { cat <<'EOF'
# run 은 기본 라벨이 run=relay — Service 셀렉터에 맞게 app=relay 로 준다
kubectl -n probe-lab run relay --image=nginx:1.28 --labels=app=relay $do > relay.yaml
#   containers[0] 아래, image 와 같은 높이에:
#   readinessProbe:
#     tcpSocket:
#       port: 80
#     initialDelaySeconds: 5
#     periodSeconds: 10
#   livenessProbe:
#     tcpSocket:
#       port: 80
#     periodSeconds: 20
kubectl apply -f relay.yaml
kubectl -n probe-lab get pod relay -w                  # 5~15초 뒤 1/1
kubectl -n probe-lab get endpoints relay
EOF
}

exam_main "$@"
