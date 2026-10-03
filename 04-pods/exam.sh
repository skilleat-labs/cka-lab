#!/usr/bin/env bash
# CKA 4강 실습 — 파드 · ReplicaSet · Deployment (순차 진행형)
# 사용법: bash exam.sh start  →  풀고  →  bash exam.sh check  →  ...
# 모든 리소스는 pod-lab 네임스페이스 안에 만든다 (다른 세트의 default 리소스와 섞이지 않게).
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 4강 실습 — 파드 · ReplicaSet · Deployment"
EXAM_NQ=7

NS=pod-lab
OUT_DIR=/tmp/04-pods
CODE_FILE="$WORK_DIR/.q2-code"
BAD_IMAGE=nginx:1.99.9          # Q7 — 존재하지 않는 태그

# 파일 한 줄을 공백 없이 읽는다 (채점용)
fval() { [[ -f "$1" ]] && tr -d ' \t\r\n' < "$1" || true; }

# ══════════════════════════════════════════════════════════════
exam_cleanup() {
  kdel namespace "$NS" --wait=false
  rm -rf "$OUT_DIR" "$CODE_FILE"
  echo "  $NS 네임스페이스 · $OUT_DIR 삭제"
}
exam_setup() {
  kubectl create namespace "$NS" &>/dev/null
  mkdir -p "$OUT_DIR"

  # Q2 — 들여다볼 파드 두 개. greeter 는 로그에 접속 코드를 한 번 찍는다
  local code; code="pl-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
  echo "$code" > "$CODE_FILE"
  kubectl -n "$NS" run info --image=nginx:1.27 --labels=app=info &>/dev/null
  # sh 는 SIGTERM 을 무시한다 — 정리할 때 30초씩 걸리지 않게 grace 를 1초로
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: greeter
  namespace: $NS
  labels: { app: greeter }
spec:
  terminationGracePeriodSeconds: 1
  containers:
    - name: greeter
      image: busybox:1.36
      command: ["sh", "-c", "echo starting; echo ACCESS-CODE=$code; echo ready; sleep 36000"]
YAML
  echo "  info · greeter 파드 배치 (Q2)"

  # Q3 — 이미지 이름 오타로 못 뜨는 파드
  kubectl -n "$NS" run typo --image=ngnix:1.27 --labels=app=typo &>/dev/null
  echo "  typo 파드 배치 — 일부러 고장 (Q3)"

  # Q5 — 개수를 지키는 ReplicaSet
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: cache
  namespace: $NS
spec:
  replicas: 3
  selector: { matchLabels: { app: cache } }
  template:
    metadata:
      labels: { app: cache }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
YAML
  echo "  cache ReplicaSet(3개) 배치 (Q5)"

  # Q7 — 정상(1.27) 으로 띄운 뒤 없는 태그로 업데이트해 둔다 → 롤아웃이 멈춘 상태
  kubectl -n "$NS" create deployment api --image=nginx:1.27 --replicas=3 &>/dev/null
  kubectl -n "$NS" rollout status deployment/api --timeout=90s &>/dev/null || true
  kubectl -n "$NS" set image deployment/api nginx="$BAD_IMAGE" &>/dev/null
  echo "  api Deployment 배치 후 잘못된 이미지로 업데이트 (Q7)"
}

# ══════════════════════════════════════════════════════════════
# Q1 — 파드 만들기 · 라벨
# ══════════════════════════════════════════════════════════════
q1_title() { echo "Create a Pod with labels"; }
q1_text() { cat <<'EOF'
In the namespace pod-lab, create a Pod named web.

  image    nginx:1.27
  labels   app=web, tier=frontend

It must be a bare Pod (not managed by a Deployment or ReplicaSet) and it
must be Running and Ready.

Verify:
  kubectl -n pod-lab get pod web --show-labels
  kubectl -n pod-lab get pods -l tier=frontend
EOF
}
q1_title_ko() { echo "파드 만들기 · 라벨 붙이기"; }
q1_text_ko() { cat <<'EOF'
pod-lab 네임스페이스에 web 파드를 만드시오.

  이미지   nginx:1.27
  라벨     app=web, tier=frontend

Deployment 나 ReplicaSet 이 아니라 파드 하나로 만들어야 하며,
Running · Ready 상태여야 한다.

[확인]
  kubectl -n pod-lab get pod web --show-labels
  kubectl -n pod-lab get pods -l tier=frontend
EOF
}
q1_grade() {
  check "web 파드 존재" \
    "kubectl -n $NS get pod web"
  check_output "다른 리소스가 관리하지 않는 파드 (ownerReferences 없음)" \
    "kubectl -n $NS get pod web -o jsonpath='{.metadata.ownerReferences}{\"none\"}'" '^none$'
  check_output "이미지 nginx:1.27" \
    "kubectl -n $NS get pod web -o jsonpath='{.spec.containers[0].image}'" '^nginx:1\.27$'
  check_output "라벨 app=web" \
    "kubectl -n $NS get pod web -o jsonpath='{.metadata.labels.app}'" '^web$'
  check_output "라벨 tier=frontend" \
    "kubectl -n $NS get pod web -o jsonpath='{.metadata.labels.tier}'" '^frontend$'
  wait_ready web "$NS"
  check_output "Ready" \
    "kubectl -n $NS get pod web -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" '^True$'
}
q1_hint() { cat <<'EOF'
kubectl -n pod-lab run web --image=nginx:1.27 --labels=app=web,tier=frontend

# 이미 만들었다면 라벨만 더 붙여도 된다
kubectl -n pod-lab label pod web tier=frontend
kubectl -n pod-lab get pod web --show-labels
EOF
}

# ══════════════════════════════════════════════════════════════
# Q2 — 파드 들여다보기 (get -o wide · logs · exec)
# ══════════════════════════════════════════════════════════════
q2_title() { echo "Inspect Pods: IP, node, exec, logs"; }
q2_text() { cat <<'EOF'
Two Pods already run in the namespace pod-lab: info and greeter.
Find the following and save each answer as a single line in the given file.

  (a) IP address of the Pod info          -> /tmp/04-pods/info-ip.txt
  (b) node name the Pod info runs on      -> /tmp/04-pods/info-node.txt
  (c) output of the command  nginx -v
      run inside the Pod info             -> /tmp/04-pods/nginx-version.txt
  (d) the value after ACCESS-CODE= in the
      logs of the Pod greeter             -> /tmp/04-pods/access-code.txt
      (only the value, e.g. pl-abc123)

Verify:
  cat /tmp/04-pods/*.txt
EOF
}
q2_title_ko() { echo "파드 들여다보기 — IP · 노드 · exec · logs"; }
q2_text_ko() { cat <<'EOF'
pod-lab 네임스페이스에 info 와 greeter 파드가 떠 있다.
아래를 찾아 각 파일에 한 줄로 저장하시오.

  (a) info 파드의 IP                     → /tmp/04-pods/info-ip.txt
  (b) info 파드가 떠 있는 노드 이름       → /tmp/04-pods/info-node.txt
  (c) info 파드 안에서 nginx -v 를 실행한
      결과                               → /tmp/04-pods/nginx-version.txt
  (d) greeter 파드 로그의 ACCESS-CODE=
      뒤에 있는 값                       → /tmp/04-pods/access-code.txt
      (값만. 예: pl-abc123)

[확인]
  cat /tmp/04-pods/*.txt
EOF
}
q2_grade() {
  local ip node code
  ip=$(kubectl -n $NS get pod info -o jsonpath='{.status.podIP}' 2>/dev/null)
  node=$(kubectl -n $NS get pod info -o jsonpath='{.spec.nodeName}' 2>/dev/null)
  code=$(cat "$CODE_FILE" 2>/dev/null)
  check_result "(a) info-ip.txt = 파드 IP" \
    "$([[ -n "$ip" && "$(fval $OUT_DIR/info-ip.txt)" == "$ip" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/info-ip.txt)'"
  check_result "(b) info-node.txt = 노드 이름" \
    "$([[ -n "$node" && "$(fval $OUT_DIR/info-node.txt)" == "$node" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/info-node.txt)'"
  check_output "(c) nginx-version.txt 에 nginx/1.27 버전 문자열" \
    "cat $OUT_DIR/nginx-version.txt" 'nginx/1\.27'
  check_result "(d) access-code.txt = 로그의 접속 코드 (값만)" \
    "$([[ -n "$code" && "$(fval $OUT_DIR/access-code.txt)" == "$code" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/access-code.txt)'"
}
q2_hint() { cat <<'EOF'
kubectl -n pod-lab get pod info -o wide          # IP · NODE 칸
kubectl -n pod-lab get pod info -o jsonpath='{.status.podIP}' > /tmp/04-pods/info-ip.txt
kubectl -n pod-lab get pod info -o jsonpath='{.spec.nodeName}' > /tmp/04-pods/info-node.txt

# nginx -v 는 결과를 stderr 로 낸다 — 2>&1 이 없으면 파일이 빈다
kubectl -n pod-lab exec info -- nginx -v > /tmp/04-pods/nginx-version.txt 2>&1

kubectl -n pod-lab logs greeter
kubectl -n pod-lab logs greeter | grep ACCESS-CODE | cut -d= -f2 > /tmp/04-pods/access-code.txt
EOF
}

# ══════════════════════════════════════════════════════════════
# Q3 — 안 뜨는 파드 고치기
# ══════════════════════════════════════════════════════════════
q3_title() { echo "Fix a Pod that does not start"; }
q3_text() { cat <<'EOF'
The Pod typo in the namespace pod-lab never becomes Ready.
Find out why (Events) and fix it so that it runs nginx version 1.27.

The Pod must still be named typo and must be Running and Ready.

Verify:
  kubectl -n pod-lab get pod typo
  kubectl -n pod-lab describe pod typo | tail
EOF
}
q3_title_ko() { echo "안 뜨는 파드 고치기"; }
q3_text_ko() { cat <<'EOF'
pod-lab 네임스페이스의 typo 파드가 Ready 가 되지 않는다.
원인을 찾아(Events) nginx 1.27 이 실행되도록 고치시오.

파드 이름은 그대로 typo 여야 하고 Running · Ready 상태여야 한다.

[확인]
  kubectl -n pod-lab get pod typo
  kubectl -n pod-lab describe pod typo | tail
EOF
}
q3_grade() {
  check "typo 파드 존재" \
    "kubectl -n $NS get pod typo"
  check_output "이미지 nginx:1.27" \
    "kubectl -n $NS get pod typo -o jsonpath='{.spec.containers[0].image}'" '^nginx:1\.27$'
  wait_ready typo "$NS"
  check_output "Ready" \
    "kubectl -n $NS get pod typo -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" '^True$'
}
q3_hint() { cat <<'EOF'
kubectl -n pod-lab get pod typo                    # STATUS: ErrImagePull / ImagePullBackOff
kubectl -n pod-lab describe pod typo               # 맨 아래 Events — 이미지 이름을 본다

# 파드에서 image 는 바꿀 수 있는 몇 안 되는 칸이다
kubectl -n pod-lab set image pod/typo typo=nginx:1.27      # 컨테이너 이름 = 파드 이름(run 으로 만든 경우)

# 또는 지우고 다시 만든다
kubectl -n pod-lab delete pod typo
kubectl -n pod-lab run typo --image=nginx:1.27
EOF
}

# ══════════════════════════════════════════════════════════════
# Q4 — ReplicaSet 만들고 스케일
# ══════════════════════════════════════════════════════════════
q4_title() { echo "Create and scale a ReplicaSet"; }
q4_text() { cat <<'EOF'
In the namespace pod-lab, create a ReplicaSet named web-rs from a YAML file.

  replicas   3
  selector   app=web-rs
  image      nginx:1.27

When its 3 Pods are Ready, scale the ReplicaSet to 5 replicas.
Create the ReplicaSet itself — not a Deployment.

Verify:
  kubectl -n pod-lab get rs web-rs
  kubectl -n pod-lab get pods -l app=web-rs
EOF
}
q4_title_ko() { echo "ReplicaSet 만들고 늘리기"; }
q4_text_ko() { cat <<'EOF'
pod-lab 네임스페이스에 web-rs ReplicaSet 을 YAML 파일로 만드시오.

  replicas   3
  selector   app=web-rs
  이미지      nginx:1.27

파드 3개가 Ready 가 되면 ReplicaSet 을 5 개로 늘리시오.
Deployment 가 아니라 ReplicaSet 을 직접 만들어야 한다.

[확인]
  kubectl -n pod-lab get rs web-rs
  kubectl -n pod-lab get pods -l app=web-rs
EOF
}
q4_grade() {
  check "web-rs ReplicaSet 존재" \
    "kubectl -n $NS get rs web-rs"
  check_output "Deployment 가 아니라 직접 만든 ReplicaSet (ownerReferences 없음)" \
    "kubectl -n $NS get rs web-rs -o jsonpath='{.metadata.ownerReferences}{\"none\"}'" '^none$'
  check_output "selector app=web-rs" \
    "kubectl -n $NS get rs web-rs -o jsonpath='{.spec.selector.matchLabels.app}'" '^web-rs$'
  check_output "이미지 nginx:1.27" \
    "kubectl -n $NS get rs web-rs -o jsonpath='{.spec.template.spec.containers[0].image}'" '^nginx:1\.27$'
  check_output "replicas 5" \
    "kubectl -n $NS get rs web-rs -o jsonpath='{.spec.replicas}'" '^5$'
  wait_ready "-l app=web-rs" "$NS"
  check_output "파드 5개 Ready" \
    "kubectl -n $NS get rs web-rs -o jsonpath='{.status.readyReplicas}'" '^5$'
}
q4_hint() { cat <<'EOF'
# ReplicaSet 은 create 명령이 없다 → Deployment 뼈대를 뽑아 kind 만 고친다
kubectl -n pod-lab create deployment web-rs --image=nginx:1.27 --replicas=3 \
  --dry-run=client -o yaml > web-rs.yaml
#   kind: Deployment  →  kind: ReplicaSet
#   strategy: {} 줄과 status: {} 줄은 지운다
kubectl apply -f web-rs.yaml
kubectl -n pod-lab get rs web-rs -w

kubectl -n pod-lab scale rs web-rs --replicas=5
EOF
}

# ══════════════════════════════════════════════════════════════
# Q5 — 라벨로 파드 하나를 ReplicaSet 에서 떼어 내기
# ══════════════════════════════════════════════════════════════
q5_title() { echo "Take a Pod out of a ReplicaSet with labels"; }
q5_text() { cat <<'EOF'
The ReplicaSet cache in the namespace pod-lab keeps 3 Pods (app=cache).

Take exactly one of its Pods out of the ReplicaSet for debugging,
WITHOUT deleting it: change that Pod's label app to app=debug.

Final state:
  - one Pod (originally created by cache) with app=debug, still Running,
    and no longer owned by the ReplicaSet
  - the ReplicaSet cache again has 3 Ready Pods with app=cache

Verify:
  kubectl -n pod-lab get pods --show-labels
  kubectl -n pod-lab get rs cache
EOF
}
q5_title_ko() { echo "라벨로 파드 하나를 ReplicaSet 에서 떼어 내기"; }
q5_text_ko() { cat <<'EOF'
pod-lab 네임스페이스의 cache ReplicaSet 이 파드 3개(app=cache)를 지키고 있다.

그중 파드 하나를 디버깅용으로 ReplicaSet 에서 떼어 내시오.
파드를 지우지 말고, 그 파드의 라벨 app 을 app=debug 로 바꾼다.

최종 상태:
  - cache 가 만들었던 파드 하나가 app=debug 로 바뀌어 Running 이고,
    더는 ReplicaSet 소속이 아니다
  - cache ReplicaSet 은 다시 app=cache 파드 3개가 Ready

[확인]
  kubectl -n pod-lab get pods --show-labels
  kubectl -n pod-lab get rs cache
EOF
}
q5_grade() {
  local dbg n_dbg owner
  dbg=$(kubectl -n $NS get pods -l app=debug -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  n_dbg=$(wc -w <<<"$dbg" | tr -d ' ')
  check_result "app=debug 파드가 정확히 1개 (${n_dbg}개)" \
    "$([[ "$n_dbg" == "1" ]] && echo 0 || echo 1)" "현재: ${dbg:-없음}"
  check_result "그 파드는 cache 가 만든 파드다 (이름이 cache-)" \
    "$([[ "$n_dbg" == "1" && "$dbg" == cache-* ]] && echo 0 || echo 1)" "새로 만든 파드가 아니라 기존 파드의 라벨을 바꾼다"
  if [[ "$n_dbg" == "1" ]]; then
    owner=$(kubectl -n $NS get pod "$dbg" -o jsonpath='{.metadata.ownerReferences[*].name}' 2>/dev/null)
    check_result "ReplicaSet 소속에서 빠졌다 (ownerReferences 없음)" \
      "$([[ -z "$owner" ]] && echo 0 || echo 1)" "owner=$owner"
    check_output "debug 파드가 Running" \
      "kubectl -n $NS get pod $dbg -o jsonpath='{.status.phase}'" '^Running$'
  else
    check_result "ReplicaSet 소속에서 빠졌다 (ownerReferences 없음)" 1 "app=debug 파드가 1개가 아니다"
    check_result "debug 파드가 Running" 1 "app=debug 파드가 1개가 아니다"
  fi
  check "cache ReplicaSet 존재 (지우지 않았다)" \
    "kubectl -n $NS get rs cache"
  wait_ready "-l app=cache" "$NS"
  check_output "cache 가 다시 3개 Ready" \
    "kubectl -n $NS get rs cache -o jsonpath='{.status.readyReplicas}'" '^3$'
  check_output "app=cache 파드가 3개" \
    "kubectl -n $NS get pods -l app=cache --no-headers 2>/dev/null | wc -l | tr -d ' '" '^3$'
}
q5_hint() { cat <<'EOF'
kubectl -n pod-lab get pods -l app=cache
kubectl -n pod-lab label pod cache-xxxxx app=debug --overwrite    # 이름은 위에서 하나 고른다

# ReplicaSet 은 라벨로 자기 파드를 센다 → 2개로 줄었다고 보고 하나를 새로 만든다
kubectl -n pod-lab get pods --show-labels
kubectl -n pod-lab get pod cache-xxxxx -o jsonpath='{.metadata.ownerReferences}'   # 비어 있다
EOF
}

# ══════════════════════════════════════════════════════════════
# Q6 — Deployment 만들고 버전 바꾸기
# ══════════════════════════════════════════════════════════════
q6_title() { echo "Create a Deployment and update its image"; }
q6_text() { cat <<'EOF'
In the namespace pod-lab, create a Deployment named shop.

  image      nginx:1.27
  replicas   3

Then update its image to nginx:1.28 with a rolling update and wait until
the rollout has finished.

Final state: nginx:1.28, 3 Ready Pods. The old ReplicaSet (nginx:1.27)
must still exist, scaled down to 0.

Verify:
  kubectl -n pod-lab rollout status deployment/shop
  kubectl -n pod-lab get deploy,rs -l app=shop
EOF
}
q6_title_ko() { echo "Deployment 만들고 버전 바꾸기"; }
q6_text_ko() { cat <<'EOF'
pod-lab 네임스페이스에 shop Deployment 를 만드시오.

  이미지      nginx:1.27
  replicas   3

그다음 이미지를 nginx:1.28 로 롤링 업데이트하고 끝날 때까지 기다리시오.

최종 상태: nginx:1.28, 파드 3개 Ready.
옛 ReplicaSet(nginx:1.27) 은 0 개로 줄어든 채 남아 있어야 한다.

[확인]
  kubectl -n pod-lab rollout status deployment/shop
  kubectl -n pod-lab get deploy,rs -l app=shop
EOF
}
q6_grade() {
  check "shop Deployment 존재" \
    "kubectl -n $NS get deployment shop"
  check_output "이미지 nginx:1.28" \
    "kubectl -n $NS get deployment shop -o jsonpath='{.spec.template.spec.containers[0].image}'" '^nginx:1\.28$'
  check_output "replicas 3" \
    "kubectl -n $NS get deployment shop -o jsonpath='{.spec.replicas}'" '^3$'
  wait_ready "-l app=shop" "$NS"
  check_output "새 버전 파드 3개가 Ready (updatedReplicas · readyReplicas)" \
    "kubectl -n $NS get deployment shop -o jsonpath='{.status.updatedReplicas}/{.status.readyReplicas}'" '^3/3$'
  check_output "옛 ReplicaSet(nginx:1.27)이 0개로 남아 있다" \
    "kubectl -n $NS get rs -l app=shop -o jsonpath='{range .items[*]}{.spec.template.spec.containers[0].image}={.spec.replicas}{\"\\n\"}{end}'" '^nginx:1\.27=0$'
}
q6_hint() { cat <<'EOF'
kubectl -n pod-lab create deployment shop --image=nginx:1.27 --replicas=3
kubectl -n pod-lab rollout status deployment/shop

kubectl -n pod-lab set image deployment/shop nginx=nginx:1.28     # 컨테이너 이름은 nginx
kubectl -n pod-lab rollout status deployment/shop
kubectl -n pod-lab get rs -l app=shop          # 새 RS 3 · 옛 RS 0
EOF
}

# ══════════════════════════════════════════════════════════════
# Q7 — 멈춘 롤아웃 되돌리기
# ══════════════════════════════════════════════════════════════
q7_title() { echo "Roll back a broken rollout"; }
q7_text() { cat <<'EOF'
Someone updated the Deployment api in the namespace pod-lab and the
rollout got stuck.

  (a) Find the image the broken update tried to use and save it
      (e.g. repo:tag) to /tmp/04-pods/bad-image.txt
  (b) Roll the Deployment back to the previous working revision.

Final state: all 3 Pods of api Ready, no Pod failing to pull an image.

Verify:
  kubectl -n pod-lab rollout history deployment/api
  kubectl -n pod-lab get pods -l app=api
EOF
}
q7_title_ko() { echo "멈춘 롤아웃 되돌리기"; }
q7_text_ko() { cat <<'EOF'
누군가 pod-lab 네임스페이스의 api Deployment 를 업데이트했는데
롤아웃이 멈췄다.

  (a) 잘못된 업데이트가 쓰려던 이미지를 찾아 /tmp/04-pods/bad-image.txt
      에 저장하시오 (예: 저장소:태그)
  (b) Deployment 를 바로 앞의 정상 리비전으로 되돌리시오.

최종 상태: api 파드 3개가 모두 Ready, 이미지를 못 받는 파드가 없어야 한다.

[확인]
  kubectl -n pod-lab rollout history deployment/api
  kubectl -n pod-lab get pods -l app=api
EOF
}
q7_grade() {
  check_result "(a) bad-image.txt = $BAD_IMAGE" \
    "$([[ "$(fval $OUT_DIR/bad-image.txt)" == "$BAD_IMAGE" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/bad-image.txt)'"
  check_output "(b) 이미지가 nginx:1.27 로 돌아왔다" \
    "kubectl -n $NS get deployment api -o jsonpath='{.spec.template.spec.containers[0].image}'" '^nginx:1\.27$'
  local rev; rev=$(kubectl -n $NS get deployment api -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null)
  rev="${rev//[^0-9]/}"; rev="${rev:-0}"
  check_result "롤백으로 되돌렸다 (revision ${rev} ≥ 3)" \
    "$([[ "$rev" -ge 3 ]] && echo 0 || echo 1)" "지우고 새로 만들면 revision 이 1 부터 다시 시작한다"
  wait_ready "-l app=api" "$NS"
  check_output "파드 3개 Ready (updatedReplicas · readyReplicas)" \
    "kubectl -n $NS get deployment api -o jsonpath='{.status.updatedReplicas}/{.status.readyReplicas}'" '^3/3$'
  check_output "$BAD_IMAGE 를 쓰는 파드가 남지 않았다" \
    "kubectl -n $NS get pods -l app=api -o jsonpath='{.items[*].spec.containers[0].image}{\" end\"}'" "^(nginx:1\.27 )*end$"
}
q7_hint() { cat <<'EOF'
kubectl -n pod-lab rollout status deployment/api --timeout=10s   # 멈춰 있다
kubectl -n pod-lab get pods -l app=api                           # ErrImagePull / ImagePullBackOff
kubectl -n pod-lab get deployment api -o jsonpath='{.spec.template.spec.containers[0].image}' > /tmp/04-pods/bad-image.txt

kubectl -n pod-lab rollout history deployment/api
kubectl -n pod-lab rollout undo deployment/api                   # 바로 앞 리비전으로
kubectl -n pod-lab rollout status deployment/api
EOF
}

exam_main "$@"
