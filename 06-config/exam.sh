#!/usr/bin/env bash
# CKA 6강 실습 — 설정을 이미지 밖으로: ConfigMap · Secret (순차 진행형)
# 사용법: bash exam.sh start  →  풀고  →  bash exam.sh check  →  ...
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 6강 실습 — ConfigMap · Secret (환경변수 · 볼륨 · 반영 · immutable)"
EXAM_NQ=5

NS=config-lab
OUT_DIR=/tmp/06-config
TOKEN_FILE="$WORK_DIR/.q3-token"
PW_FILE="$WORK_DIR/.q4-password"

# 파일 한 줄을 공백 없이 읽는다 (채점용)
fval() { [[ -f "$1" ]] && tr -d ' \t\r\n' < "$1" || true; }
_rand() { LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c "${1:-6}"; }

# ══════════════════════════════════════════════════════════════
exam_cleanup() {
  kdel pod db-client -n default                 # Q1
  kdel configmap db-config -n default
  kdel namespace "$NS" --wait=false             # Q2 ~ Q4
  kdel namespace billing --wait=false           # Q5 — immutable ConfigMap 도 네임스페이스와 함께 지워진다
  rm -rf "$OUT_DIR" "$TOKEN_FILE" "$PW_FILE" "$WORK_DIR/.q5-baseline"
  echo "  db-client / db-config / $NS ns / billing ns / $OUT_DIR 삭제"
}
exam_setup() {
  kubectl create namespace "$NS" &>/dev/null
  mkdir -p "$OUT_DIR"

  # Q2 — 키가 여럿인 ConfigMap (하나만 골라 넣는다)
  kubectl -n "$NS" create configmap app-settings \
    --from-literal=COLOR=blue --from-literal=LOG_LEVEL=debug --from-literal=TIMEOUT=30 &>/dev/null
  echo "  $NS 에 app-settings ConfigMap 배치 (Q2)"

  # Q3 — ConfigMap 으로 만들 웹 페이지. 시작할 때마다 내용이 바뀐다
  local token; token="cfg-$(_rand 6)"
  echo "$token" > "$TOKEN_FILE"
  cat > "$OUT_DIR/index.html" <<HTML
<html><body><h1>config-lab</h1><p>$token</p></body></html>
HTML
  echo "  $OUT_DIR/index.html 준비 (Q3)"

  # Q4 — 풀어 읽을 Secret
  local pw; pw="pw-$(_rand 8)"
  echo "$pw" > "$PW_FILE"
  kubectl -n "$NS" create secret generic legacy-cred \
    --from-literal=username=legacy --from-literal=password="$pw" &>/dev/null
  echo "  $NS 에 legacy-cred Secret 배치 (Q4)"

  # Q5(ConfigMap 수정 → 재배포 → immutable) 용 — 값을 env 로 읽는 Deployment
  kubectl create namespace billing &>/dev/null
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: billing-config
  namespace: billing
data:
  PAYMENT_MODE: sandbox
  CURRENCY: KRW
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: invoice-api
  namespace: billing
  labels: { app: invoice-api }
spec:
  replicas: 2
  selector: { matchLabels: { app: invoice-api } }
  template:
    metadata:
      labels: { app: invoice-api }
    spec:
      terminationGracePeriodSeconds: 2      # sh 는 SIGTERM 을 무시한다 — 재시작이 30초씩 걸리지 않게
      containers:
        - name: api
          image: busybox:1.36
          command: ["sh", "-c", "echo \"mode=$PAYMENT_MODE currency=$CURRENCY\"; sleep 3600"]
          env:
            - name: PAYMENT_MODE
              valueFrom: { configMapKeyRef: { name: billing-config, key: PAYMENT_MODE } }
            - name: CURRENCY
              valueFrom: { configMapKeyRef: { name: billing-config, key: CURRENCY } }
YAML
  # 처음 뜬 파드의 생성 시각(API 서버 기준)을 기록해 둔다 — 채점 때 "그 뒤에 새로 만든 파드인가" 를 본다.
  # 노드·채점 머신 시계가 달라도 상관없게 date 가 아니라 creationTimestamp 끼리 비교한다.
  local i out cnt base=""
  for i in $(seq 1 20); do
    out=$(kubectl -n billing get pods -l app=invoice-api \
      -o jsonpath='{range .items[*]}{.metadata.creationTimestamp}{"\n"}{end}' 2>/dev/null)
    cnt=$(printf '%s\n' "$out" | grep -c 'T'); cnt=${cnt//[^0-9]/}; cnt=${cnt:-0}
    base=$(printf '%s\n' "$out" | grep 'T' | sort | tail -1)
    (( cnt >= 2 )) && break
    sleep 1
  done
  if [[ -n "$base" ]]; then
    echo "$base" > "$WORK_DIR/.q5-baseline"
  else
    rm -f "$WORK_DIR/.q5-baseline"
  fi
  echo "  billing 네임스페이스에 billing-config(ConfigMap) + invoice-api(Deployment) 배치 (Q5)"
}

# ══════════════════════════════════════════════════════════════
# Q1 — ConfigMap + envFrom
# ══════════════════════════════════════════════════════════════
q1_title() { echo "ConfigMap injected as environment variables"; }
q1_text() { cat <<'EOF'
Create a ConfigMap named db-config in the default namespace with the keys
DB_HOST=mysql and DB_PORT=3306.

Then create a Pod named db-client (image busybox) that injects every key of
that ConfigMap as environment variables using envFrom.

  command   ["sh","-c","env | grep DB && sleep 3600"]

The Pod must be Running and both variables must be visible inside it.

Verify:
  kubectl exec db-client -- env | grep DB
EOF
}
q1_title_ko() { echo "ConfigMap 생성 + 파드에 환경변수로 주입"; }
q1_text_ko() { cat <<'EOF'
default 네임스페이스에 db-config ConfigMap 을 만드시오.
데이터: DB_HOST=mysql, DB_PORT=3306

그다음 db-client 파드(이미지 busybox)를 만들어 이 ConfigMap 전체를
envFrom 으로 환경변수에 주입하시오.

  command   ["sh","-c","env | grep DB && sleep 3600"]

파드는 Running 이어야 하고 두 환경변수가 파드 안에서 보여야 한다.

[확인]
  kubectl exec db-client -- env | grep DB
EOF
}
q1_grade() {
  check "ConfigMap db-config 존재" "kubectl get configmap db-config -n default"
  check_output "DB_HOST=mysql" \
    "kubectl get configmap db-config -n default -o jsonpath='{.data.DB_HOST}'" '^mysql$'
  check_output "DB_PORT=3306" \
    "kubectl get configmap db-config -n default -o jsonpath='{.data.DB_PORT}'" '^3306$'
  check "파드 db-client 존재" "kubectl get pod db-client -n default"
  wait_ready "db-client" default
  check_output "db-client Running" \
    "kubectl get pod db-client -n default -o jsonpath='{.status.phase}'" '^Running$'
  if kubectl get pod db-client -n default &>/dev/null; then
    check_output "파드 안에서 DB_HOST=mysql (실제 exec)" \
      "kubectl exec db-client -n default -- env 2>/dev/null" 'DB_HOST=mysql'
    check_output "파드 안에서 DB_PORT=3306 (실제 exec)" \
      "kubectl exec db-client -n default -- env 2>/dev/null" 'DB_PORT=3306'
    check_output "env 하나씩이 아니라 envFrom 으로 주입했는가" \
      "kubectl get pod db-client -n default -o jsonpath='{.spec.containers[0].envFrom[*].configMapRef.name}'" 'db-config'
  else
    check_result "파드 안에서 DB_HOST=mysql (실제 exec)" 1 "파드가 없음"
    check_result "파드 안에서 DB_PORT=3306 (실제 exec)" 1 "파드가 없음"
    check_result "envFrom 으로 주입" 1 "파드가 없음"
  fi
}
q1_hint() { cat <<'EOF'
kubectl create configmap db-config --from-literal=DB_HOST=mysql --from-literal=DB_PORT=3306

# 파드 YAML 뼈대를 뽑고 envFrom 을 넣는다
kubectl run db-client --image=busybox --restart=Never $do \
  -- sh -c 'env | grep DB && sleep 3600' > pod.yaml
#   spec.containers[0] 아래에:
#   envFrom:
#   - configMapRef:
#       name: db-config
EOF
}

# ══════════════════════════════════════════════════════════════
# Q2 — 키 하나만 골라 다른 이름의 환경변수로
# ══════════════════════════════════════════════════════════════
q2_title() { echo "Pick a single ConfigMap key as an environment variable"; }
q2_text() { cat <<'EOF'
The ConfigMap app-settings already exists in the namespace config-lab
(keys COLOR, LOG_LEVEL, TIMEOUT).

Create a Pod named picker in config-lab:

  image     busybox:1.36
  command   ["sh","-c","sleep 3600"]
  env       THEME  = the value of the key COLOR in app-settings

Inject ONLY that one key (do not load the whole ConfigMap).
The Pod must be Running.

Verify:
  kubectl -n config-lab exec picker -- printenv THEME
EOF
}
q2_title_ko() { echo "키 하나만 골라 다른 이름의 환경변수로"; }
q2_text_ko() { cat <<'EOF'
config-lab 네임스페이스에 app-settings ConfigMap 이 이미 있다
(키: COLOR, LOG_LEVEL, TIMEOUT).

config-lab 에 picker 파드를 만드시오.

  이미지     busybox:1.36
  command   ["sh","-c","sleep 3600"]
  env       THEME = app-settings 의 COLOR 키 값

그 키 하나만 넣는다 (ConfigMap 전체를 넣지 않는다).
파드는 Running 이어야 한다.

[확인]
  kubectl -n config-lab exec picker -- printenv THEME
EOF
}
q2_grade() {
  check "picker 파드 존재" "kubectl -n $NS get pod picker"
  check_output "THEME 가 app-settings 를 참조 (configMapKeyRef)" \
    "kubectl -n $NS get pod picker -o jsonpath='{.spec.containers[0].env[?(@.name==\"THEME\")].valueFrom.configMapKeyRef.name}'" '^app-settings$'
  check_output "참조하는 키가 COLOR" \
    "kubectl -n $NS get pod picker -o jsonpath='{.spec.containers[0].env[?(@.name==\"THEME\")].valueFrom.configMapKeyRef.key}'" '^COLOR$'
  check_output "ConfigMap 전체를 넣지 않았다 (envFrom 없음)" \
    "kubectl -n $NS get pod picker -o jsonpath='{.spec.containers[0].envFrom}{\"none\"}'" '^none$'
  wait_ready picker "$NS"
  check_output "파드 안에서 THEME=blue (실제 exec)" \
    "kubectl -n $NS exec picker -- printenv THEME" '^blue$'
}
q2_hint() { cat <<'EOF'
kubectl -n config-lab run picker --image=busybox:1.36 $do -- sh -c 'sleep 3600' > picker.yaml
#   spec.containers[0] 아래에:
#   env:
#   - name: THEME
#     valueFrom:
#       configMapKeyRef:
#         name: app-settings
#         key: COLOR
kubectl apply -f picker.yaml
kubectl -n config-lab exec picker -- printenv THEME
EOF
}

# ══════════════════════════════════════════════════════════════
# Q3 — 파일로 만든 ConfigMap 을 볼륨으로 마운트
# ══════════════════════════════════════════════════════════════
q3_title() { echo "ConfigMap from a file, mounted as a volume"; }
q3_text() { cat <<'EOF'
A web page is prepared at /tmp/06-config/index.html.

  (a) Create a ConfigMap named web-page in the namespace config-lab from
      that file. The key must be index.html.
  (b) Create a Deployment named page in config-lab:
        image      nginx:1.27
        replicas   1
      Mount the ConfigMap web-page as a volume at /usr/share/nginx/html
      so that nginx serves that page.

Verify:
  kubectl -n config-lab exec deploy/page -- cat /usr/share/nginx/html/index.html
EOF
}
q3_title_ko() { echo "파일로 만든 ConfigMap 을 볼륨으로 마운트"; }
q3_text_ko() { cat <<'EOF'
/tmp/06-config/index.html 에 웹 페이지가 준비되어 있다.

  (a) 이 파일로 config-lab 네임스페이스에 web-page ConfigMap 을 만드시오.
      키는 index.html 이어야 한다.
  (b) config-lab 에 page Deployment 를 만드시오.
        이미지      nginx:1.27
        replicas   1
      web-page ConfigMap 을 볼륨으로 /usr/share/nginx/html 에 마운트해서
      nginx 가 그 페이지를 내보내게 한다.

[확인]
  kubectl -n config-lab exec deploy/page -- cat /usr/share/nginx/html/index.html
EOF
}
q3_grade() {
  local token; token=$(cat "$TOKEN_FILE" 2>/dev/null)
  check "web-page ConfigMap 존재" "kubectl -n $NS get configmap web-page"
  check_output "키 index.html 에 준비된 파일 내용" \
    "kubectl -n $NS get configmap web-page -o jsonpath='{.data.index\.html}'" "${token:-없음}"
  check "page Deployment 존재" "kubectl -n $NS get deployment page"
  check_output "볼륨이 web-page ConfigMap" \
    "kubectl -n $NS get deployment page -o jsonpath='{.spec.template.spec.volumes[*].configMap.name}'" '(^| )web-page( |$)'
  check_output "마운트 위치 /usr/share/nginx/html" \
    "kubectl -n $NS get deployment page -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}'" '(^| )/usr/share/nginx/html/?( |$)'
  wait_ready "-l app=page" "$NS"
  check_output "Ready 파드 1개" \
    "kubectl -n $NS get deployment page -o jsonpath='{.status.readyReplicas}'" '^1$'
  check_output "파드 안의 index.html 이 준비된 페이지 (실제 exec)" \
    "kubectl -n $NS exec deploy/page -- cat /usr/share/nginx/html/index.html" "${token:-없음}"
}
q3_hint() { cat <<'EOF'
# 파일 이름이 키가 된다
kubectl -n config-lab create configmap web-page --from-file=/tmp/06-config/index.html
kubectl -n config-lab get configmap web-page -o yaml

kubectl -n config-lab create deployment page --image=nginx:1.27 $do > page.yaml
#   spec.template.spec 아래에:
#   volumes:
#   - name: html
#     configMap:
#       name: web-page
#   containers[0] 아래에:
#   volumeMounts:
#   - name: html
#     mountPath: /usr/share/nginx/html
kubectl apply -f page.yaml
EOF
}

# ══════════════════════════════════════════════════════════════
# Q4 — Secret 읽기(base64) · 만들기 · 환경변수로 넣기
# ══════════════════════════════════════════════════════════════
q4_title() { echo "Secrets: decode one, create one, use it"; }
q4_text() { cat <<'EOF'
Work in the namespace config-lab.

  (a) The Secret legacy-cred already exists. Decode the value of its key
      password and save the plain text to /tmp/06-config/legacy-password.txt
  (b) Create a generic Secret named db-cred with
        username = admin
        password = Sk1ll-eat
  (c) Create a Pod named db-app (image busybox:1.36,
      command ["sh","-c","sleep 3600"]) with two environment variables
        DB_USER      from db-cred, key username
        DB_PASSWORD  from db-cred, key password
      The Pod must be Running.

Verify:
  cat /tmp/06-config/legacy-password.txt
  kubectl -n config-lab exec db-app -- env | grep DB_
EOF
}
q4_title_ko() { echo "Secret — 풀어 읽기 · 만들기 · 환경변수로 넣기"; }
q4_text_ko() { cat <<'EOF'
config-lab 네임스페이스에서 작업한다.

  (a) legacy-cred Secret 이 이미 있다. password 키의 값을 풀어서(디코딩)
      평문을 /tmp/06-config/legacy-password.txt 에 저장하시오.
  (b) generic Secret db-cred 를 만드시오.
        username = admin
        password = Sk1ll-eat
  (c) db-app 파드를 만드시오 (이미지 busybox:1.36,
      command ["sh","-c","sleep 3600"]). 환경변수 두 개:
        DB_USER      ← db-cred 의 username
        DB_PASSWORD  ← db-cred 의 password
      파드는 Running 이어야 한다.

[확인]
  cat /tmp/06-config/legacy-password.txt
  kubectl -n config-lab exec db-app -- env | grep DB_
EOF
}
q4_grade() {
  local pw; pw=$(cat "$PW_FILE" 2>/dev/null)
  check_result "(a) legacy-password.txt = 디코딩한 평문" \
    "$([[ -n "$pw" && "$(fval $OUT_DIR/legacy-password.txt)" == "$pw" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/legacy-password.txt)' — base64 그대로면 오답"
  check "(b) db-cred Secret 존재" "kubectl -n $NS get secret db-cred"
  check_output "(b) 타입 Opaque (generic)" \
    "kubectl -n $NS get secret db-cred -o jsonpath='{.type}'" '^Opaque$'
  check_output "(b) username = admin" \
    "kubectl -n $NS get secret db-cred -o jsonpath='{.data.username}' | base64 -d" '^admin$'
  check_output "(b) password = Sk1ll-eat" \
    "kubectl -n $NS get secret db-cred -o jsonpath='{.data.password}' | base64 -d" '^Sk1ll-eat$'
  check "(c) db-app 파드 존재" "kubectl -n $NS get pod db-app"
  check_output "(c) DB_PASSWORD 가 db-cred 를 참조 (secretKeyRef)" \
    "kubectl -n $NS get pod db-app -o jsonpath='{.spec.containers[0].env[?(@.name==\"DB_PASSWORD\")].valueFrom.secretKeyRef.name}'" '^db-cred$'
  wait_ready db-app "$NS"
  check_output "(c) 파드 안에서 DB_USER=admin (실제 exec)" \
    "kubectl -n $NS exec db-app -- printenv DB_USER" '^admin$'
  check_output "(c) 파드 안에서 DB_PASSWORD=Sk1ll-eat (실제 exec)" \
    "kubectl -n $NS exec db-app -- printenv DB_PASSWORD" '^Sk1ll-eat$'
}
q4_hint() { cat <<'EOF'
# (a) Secret 의 값은 base64 — 암호화가 아니라 풀면 그대로 보인다
kubectl -n config-lab get secret legacy-cred -o jsonpath='{.data.password}' | base64 -d \
  > /tmp/06-config/legacy-password.txt

# (b)
kubectl -n config-lab create secret generic db-cred \
  --from-literal=username=admin --from-literal=password=Sk1ll-eat

# (c) ConfigMap 과 같고 단어만 secretKeyRef
kubectl -n config-lab run db-app --image=busybox:1.36 $do -- sh -c 'sleep 3600' > db-app.yaml
#   env:
#   - name: DB_USER
#     valueFrom: { secretKeyRef: { name: db-cred, key: username } }
#   - name: DB_PASSWORD
#     valueFrom: { secretKeyRef: { name: db-cred, key: password } }
EOF
}

# ══════════════════════════════════════════════════════════════
# Q5 — ConfigMap 값 바꾸기 → 파드에 반영(재배포) → immutable 로 잠그기
# ══════════════════════════════════════════════════════════════
q5_title() { echo "Update a ConfigMap, roll it out, then make it immutable"; }
q5_text() { cat <<'EOF'
In the billing namespace, the Deployment invoice-api reads the key
PAYMENT_MODE from the ConfigMap billing-config as an environment variable.
The current value is PAYMENT_MODE=sandbox.

  (a) Change PAYMENT_MODE in billing-config to live.
      Leave the other keys unchanged.
  (b) Make sure the running Pods of invoice-api actually use the new value.
      Do not change how the Deployment gets the value — it must still read
      PAYMENT_MODE from billing-config.
  (c) Finally, make billing-config immutable.

The Deployment must keep 2 replicas, all Ready.

Verify:
  kubectl -n billing get configmap billing-config -o yaml
  kubectl -n billing exec deploy/invoice-api -- printenv PAYMENT_MODE
EOF
}
q5_title_ko() { echo "ConfigMap 수정 → 파드에 반영(재배포) → immutable 로 잠그기"; }
q5_text_ko() { cat <<'EOF'
billing 네임스페이스의 invoice-api Deployment 는 billing-config ConfigMap 의
PAYMENT_MODE 키를 환경변수로 읽는다. 지금 값은 PAYMENT_MODE=sandbox 이다.

  (a) billing-config 의 PAYMENT_MODE 를 live 로 바꾸시오.
      다른 키는 그대로 둔다.
  (b) 실행 중인 invoice-api 파드가 실제로 새 값을 쓰게 하시오.
      Deployment 가 값을 가져오는 방식은 바꾸지 않는다 —
      PAYMENT_MODE 는 계속 billing-config 에서 읽어야 한다.
  (c) 마지막으로 billing-config 를 immutable(변경 불가)로 만드시오.

Deployment 는 replicas 2 를 유지하고 모두 Ready 여야 한다.

[확인]
  kubectl -n billing get configmap billing-config -o yaml
  kubectl -n billing exec deploy/invoice-api -- printenv PAYMENT_MODE
EOF
}
q5_grade() {
  check "ConfigMap billing-config 존재" "kubectl -n billing get configmap billing-config"
  check_output "PAYMENT_MODE=live" \
    "kubectl -n billing get configmap billing-config -o jsonpath='{.data.PAYMENT_MODE}'" '^live$'
  check_output "다른 키는 그대로 (CURRENCY=KRW)" \
    "kubectl -n billing get configmap billing-config -o jsonpath='{.data.CURRENCY}'" '^KRW$'
  check_output "ConfigMap 이 immutable: true" \
    "kubectl -n billing get configmap billing-config -o jsonpath='{.immutable}'" '^true$'
  check_output "Deployment 가 여전히 billing-config 에서 PAYMENT_MODE 를 읽는다 (configMapKeyRef)" \
    "kubectl -n billing get deployment invoice-api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name==\"PAYMENT_MODE\")].valueFrom.configMapKeyRef.name}'" '^billing-config$'

  wait_ready "-l app=invoice-api" billing
  check_output "Deployment Available" \
    "kubectl -n billing get deployment invoice-api -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}'" '^True$'
  check_output "Ready 파드 2개" \
    "kubectl -n billing get deployment invoice-api -o jsonpath='{.status.readyReplicas}'" '^2$'

  # 지워지는 중이 아닌 Ready 파드만 골라서 — 생성 시각과 실제 환경변수를 본다.
  #   환경변수는 컨테이너가 시작할 때 한 번 정해지므로, 바꾸기 전에 뜬 파드는 옛 값을 그대로 갖고 있다.
  local base lines name ct dt ready v n=0 old=0 wrong=0 vals=""
  base=$(cat "$WORK_DIR/.q5-baseline" 2>/dev/null)
  lines=$(kubectl -n billing get pods -l app=invoice-api \
    -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.creationTimestamp}{"|"}{.metadata.deletionTimestamp}{"|"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null)
  while IFS='|' read -r name ct dt ready; do
    [[ -z "$name" || -n "$dt" || "$ready" != "True" ]] && continue
    n=$((n+1))
    # ISO-8601(UTC) 문자열은 사전순 비교가 곧 시간순 비교다
    if [[ -n "$base" ]] && ! [[ "$ct" > "$base" ]]; then old=$((old+1)); fi
    v=$(kubectl -n billing exec "$name" -c api -- printenv PAYMENT_MODE 2>/dev/null </dev/null)
    v="${v//[$'\r\n\t ']/}"
    [[ "$v" == "live" ]] || { wrong=$((wrong+1)); vals+="$name=${v:-?} "; }
  done <<< "$lines"

  if (( n == 0 )); then
    check_result "Ready 파드가 모두 값을 바꾼 뒤 새로 만들어졌다" 1 "Ready 파드가 없음"
    check_result "모든 Ready 파드 안에서 PAYMENT_MODE=live (exec printenv)" 1 "Ready 파드가 없음"
  else
    if [[ -z "$base" ]]; then
      # 기록이 없으면(start 를 거치지 않음) 생성 시각은 못 본다 — 아래 printenv 검사가 같은 것을 증명한다
      check_result "Ready 파드가 모두 값을 바꾼 뒤 새로 만들어졌다" \
        "$(( wrong == 0 ? 0 : 1 ))" "시작 기록 없음 — 환경변수 값으로 판단"
    else
      check_result "Ready 파드가 모두 값을 바꾼 뒤 새로 만들어졌다 (옛 파드 ${old}개)" \
        "$(( old == 0 ? 0 : 1 ))" "처음 뜬 파드가 아직 Ready — 파드를 새로 만들어야 환경변수가 바뀐다"
    fi
    check_result "모든 Ready 파드 안에서 PAYMENT_MODE=live (exec printenv, ${n}개)" \
      "$(( wrong == 0 ? 0 : 1 ))" "옛 값: ${vals}"
  fi
}
q5_hint() { cat <<'EOF'
# (a) 값 바꾸기
kubectl -n billing edit configmap billing-config          # PAYMENT_MODE: live
#   또는 kubectl -n billing patch configmap billing-config -p '{"data":{"PAYMENT_MODE":"live"}}'

# (b) 환경변수는 컨테이너가 시작할 때 한 번 정해진다 → 파드를 새로 만들어야 반영
kubectl -n billing rollout restart deployment invoice-api
kubectl -n billing rollout status deployment invoice-api
kubectl -n billing exec deploy/invoice-api -- printenv PAYMENT_MODE

# (c) 마지막에 잠근다 — 먼저 잠그면 값을 못 고친다
kubectl -n billing patch configmap billing-config -p '{"immutable":true}'

# 순서를 틀려 잠근 뒤에 값을 바꿔야 한다면: 지우고 다시 만든다
kubectl -n billing get configmap billing-config -o yaml > cm.yaml   # 고친 뒤
kubectl replace --force -f cm.yaml
EOF
}
exam_main "$@"
