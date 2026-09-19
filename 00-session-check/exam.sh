#!/usr/bin/env bash
# CKA 1세션 점검 — 순차 진행형
# 사용법: bash exam.sh start  →  풀고  →  bash exam.sh check  →  ...
#
# 기존 exam-start.sh / verify.sh (한꺼번에 출제·채점) 와 같은 문제·같은 채점 기준.
# 이 파일은 한 문제씩 풀고 채점하며 진행하는 방식이다.
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 1세션 점검 — 명령어로 만들 수 있는가"
EXAM_NQ=3

# ══════════════════════════════════════════════════════════════
# 환경 준비
# ══════════════════════════════════════════════════════════════
exam_setup() {
  kubectl delete pod web-pod -n default --ignore-not-found &>/dev/null || true
  kubectl delete deployment web-app -n default --ignore-not-found &>/dev/null || true
  kubectl delete service web-svc -n default --ignore-not-found &>/dev/null || true
  kubectl delete pod svc-check -n default --ignore-not-found &>/dev/null || true
  echo "  이전 실습 리소스(web-pod / web-app / web-svc) 정리"
}

# ══════════════════════════════════════════════════════════════
# Q1 — Pod 생성 + 레이블
# ══════════════════════════════════════════════════════════════
q1_title() { echo "명령어로 Pod 생성 + 레이블 부착"; }
q1_text() { cat <<'EOF'
(1) web-pod Pod 를 kubectl run 명령어로 default 네임스페이스에 생성한다.

      이미지          nginx:1.24
      컨테이너 포트   80 노출
      환경변수        APP_ENV=prod
      조건            YAML 파일을 만들지 말고 한 줄 명령어로 생성

(2) 생성이 끝난 뒤 kubectl label 명령어로 레이블 2개를 추가한다.

      tier=frontend
      env=production

(3) env=production 레이블이 붙은 Pod 만 조회해 결과를 확인한다.

[확인]
  kubectl get pod web-pod --show-labels
  kubectl get pods -l env=production

※ kubectl run 이 자동으로 붙이는 run=web-pod 레이블이 남아 있어야 한다.
EOF
}
q1_hint() { cat <<'EOF'
kubectl run web-pod --image=nginx:1.24 --port=80 --env="APP_ENV=prod"
kubectl label pod web-pod tier=frontend env=production
kubectl get pods -l env=production

# --labels 로 한 번에 주면 run=web-pod 기본 레이블이 사라진다 → 따로 label 할 것
EOF
}
q1_grade() {
  check "web-pod Pod가 default 네임스페이스에 존재한다" \
    "kubectl get pod web-pod -n default"
  check_output "web-pod 이미지가 nginx:1.24이다" \
    "kubectl get pod web-pod -n default -o jsonpath='{.spec.containers[0].image}'" "^nginx:1\.24$"
  check_output "web-pod가 Running 상태이다" \
    "kubectl get pod web-pod -n default -o jsonpath='{.status.phase}'" "^Running$"
  check_output "web-pod가 Ready 상태이다" \
    "kubectl get pod web-pod -n default -o jsonpath='{.status.containerStatuses[0].ready}'" "^true$"
  check_output "web-pod containerPort 80이 노출되어 있다 (--port=80)" \
    "kubectl get pod web-pod -n default -o jsonpath='{.spec.containers[0].ports[0].containerPort}'" "^80$"
  check_output "web-pod에 환경변수 APP_ENV=prod가 설정되어 있다 (--env)" \
    "kubectl get pod web-pod -n default -o jsonpath='{range .spec.containers[0].env[*]}{.name}={.value}{\"\\n\"}{end}'" "^APP_ENV=prod$"
  check_output "kubectl run으로 생성한 흔적(run=web-pod 레이블)이 남아 있다" \
    "kubectl get pod web-pod -n default -o jsonpath='{.metadata.labels.run}'" "^web-pod$"
  check_output "web-pod에 레이블 tier=frontend가 붙어 있다 (kubectl label)" \
    "kubectl get pod web-pod -n default -o jsonpath='{.metadata.labels.tier}'" "^frontend$"
  check_output "web-pod에 레이블 env=production이 붙어 있다 (kubectl label)" \
    "kubectl get pod web-pod -n default -o jsonpath='{.metadata.labels.env}'" "^production$"
  check_output "레이블 셀렉터 -l env=production 으로 web-pod가 조회된다" \
    "kubectl get pods -n default -l env=production -o jsonpath='{.items[*].metadata.name}'" "web-pod"
}

# ══════════════════════════════════════════════════════════════
# Q2 — Deployment 생성 + 스케일
# ══════════════════════════════════════════════════════════════
q2_title() { echo "명령어로 Deployment 생성 + 스케일"; }
q2_text() { cat <<'EOF'
(1) web-app Deployment 를 kubectl create deployment 명령어로 생성한다.

      네임스페이스    default
      이미지          nginx:1.24
      레플리카        3
      컨테이너 포트   80 노출

(2) 생성 후 kubectl scale 명령어로 레플리카를 4 로 늘린다.

(3) 모든 파드가 Ready 상태가 될 때까지 롤아웃 상태를 확인한다.

[확인]
  kubectl get deployment web-app
  kubectl rollout status deployment/web-app
  kubectl get pods -l app=web-app
EOF
}
q2_hint() { cat <<'EOF'
kubectl create deployment web-app --image=nginx:1.24 --replicas=3 --port=80
kubectl scale deployment web-app --replicas=4
kubectl rollout status deployment/web-app

# --port=80 을 빠뜨리면 containerPort 가 비어 FAIL
EOF
}
q2_grade() {
  check "web-app Deployment가 default 네임스페이스에 존재한다" \
    "kubectl get deployment web-app -n default"
  check_output "web-app 이미지가 nginx:1.24이다" \
    "kubectl get deployment web-app -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" "^nginx:1\.24$"
  check_output "web-app replicas가 4이다 (kubectl scale)" \
    "kubectl get deployment web-app -n default -o jsonpath='{.spec.replicas}'" "^4$"
  check_output "web-app 파드 4개가 모두 Ready 상태이다" \
    "kubectl get deployment web-app -n default -o jsonpath='{.status.readyReplicas}'" "^4$"
  check_output "web-app containerPort 80이 노출되어 있다 (--port=80)" \
    "kubectl get deployment web-app -n default -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'" "^80$"
  check_output "web-app 파드 레이블이 app=web-app이다 (create deployment 기본값)" \
    "kubectl get deployment web-app -n default -o jsonpath='{.spec.selector.matchLabels.app}'" "^web-app$"
  check_output "레이블 셀렉터 -l app=web-app 으로 파드 4개가 조회된다" \
    "kubectl get pods -n default -l app=web-app --no-headers 2>/dev/null | wc -l | tr -d ' '" "^4$"
}

# ══════════════════════════════════════════════════════════════
# Q3 — Service 연결
# ══════════════════════════════════════════════════════════════
q3_title() { echo "Deployment 에 명령어로 Service 붙이기"; }
q3_text() { cat <<'EOF'
(1) Q2 에서 만든 web-app Deployment 를 kubectl expose 명령어로 노출한다.

      Service 이름    web-svc
      타입            ClusterIP
      port            80 → targetPort 80
      selector        Deployment 의 레이블(app=web-app)과 일치

(2) Service 의 Endpoints 에 파드 IP 4개가 모두 등록됐는지 확인한다.

(3) 임시 파드에서 web-svc 이름으로 HTTP 접속이 되는지 실제로 확인한다.

[확인]
  kubectl get svc web-svc
  kubectl get endpoints web-svc
  kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- web-svc

※ 채점 시 임시 파드를 띄워 실제 통신을 검증한다 (몇 초 걸림).
EOF
}
q3_hint() { cat <<'EOF'
kubectl expose deployment web-app --name=web-svc --port=80 --target-port=80 --type=ClusterIP
kubectl get endpoints web-svc      # 비어 있으면 selector ↔ 파드 레이블 불일치
EOF
}
q3_grade() {
  check "web-svc Service가 default 네임스페이스에 존재한다" \
    "kubectl get service web-svc -n default"
  check_output "web-svc 타입이 ClusterIP이다" \
    "kubectl get service web-svc -n default -o jsonpath='{.spec.type}'" "^ClusterIP$"
  check_output "web-svc port가 80이다" \
    "kubectl get service web-svc -n default -o jsonpath='{.spec.ports[0].port}'" "^80$"
  check_output "web-svc targetPort가 80이다" \
    "kubectl get service web-svc -n default -o jsonpath='{.spec.ports[0].targetPort}'" "^80$"
  check_output "web-svc selector가 app=web-app이다 (Deployment와 연결됨)" \
    "kubectl get service web-svc -n default -o jsonpath='{.spec.selector.app}'" "^web-app$"

  local ep; ep=$(kubectl get endpoints web-svc -n default -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
  check_result "web-svc Endpoints에 파드 IP 4개가 등록되어 있다" \
    "$([[ "$ep" == "4" ]] && echo 0 || echo 1)" "실제: ${ep}개 — 0이면 selector 불일치"

  # 실제 통신 검증
  kubectl delete pod svc-check -n default --ignore-not-found &>/dev/null || true
  local out; out=$(kubectl run svc-check -n default --image=busybox:1.36 --restart=Never --rm -i \
    --timeout=90s --command -- wget -qO- --timeout=5 http://web-svc 2>/dev/null || echo "")
  kubectl delete pod svc-check -n default --ignore-not-found &>/dev/null || true
  check_result "클러스터 내부에서 http://web-svc 접속 성공 (실제 통신 검증)" \
    "$(echo "$out" | grep -qi nginx && echo 0 || echo 1)" "Endpoints / CoreDNS 확인"
}

exam_main "$@"
