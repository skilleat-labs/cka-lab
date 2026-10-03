#!/usr/bin/env bash
# CKA 17강 실습 — Helm 과 Kustomize, 그리고 CRD 조회 (순차 진행형)
#   Q1~Q3 Helm install · upgrade · rollback / Q4 Kustomize
#   Q5 릴리스 이름 없이 helm template (CRD 제외) / Q6 같은 차트를 CRD 없이 install
#   Q7 CRD 목록 · kubectl explain 결과를 파일로
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 17강 실습 — Helm (install · upgrade · rollback · template) · Kustomize · CRD"
EXAM_NQ=7

# ── Q5·Q6: Argo CD 차트 ─────────────────────────────────────────
#   차트 7.7.0 = Argo CD v2.13.0. 이 버전은 CRD 를 crds/ 가 아니라 templates/ 에 두고
#   crds.install 값으로 켜고 끈다 (--skip-crds 로는 안 빠진다).
ARGO_CHART_VER=7.7.0
Q5_OUT=/tmp/argocd.yaml
Q6_REL=argocd
Q6_NS=argocd
ARGO_CRD_BASE="https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.0/manifests/crds"
ARGO_CRDS=(applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io)
ARGO_MARK="$WORK_DIR/.argocd-crds-by-setup"     # 있으면 setup 이 CRD 를 만든 것 → cleanup 이 지운다

# ── Q7: cert-manager CRD 만 (cert-manager 본체는 설치하지 않는다) ──
CM_VERSION=v1.16.2
CM_CRDS_URL="https://github.com/cert-manager/cert-manager/releases/download/${CM_VERSION}/cert-manager.crds.yaml"
CM_CRDS=(certificaterequests.cert-manager.io certificates.cert-manager.io challenges.acme.cert-manager.io
         clusterissuers.cert-manager.io issuers.cert-manager.io orders.acme.cert-manager.io)
CM_MARK="$WORK_DIR/.cert-manager-crds-by-setup"
Q7_LIST=/tmp/cert-manager-crds.txt
Q7_EXPLAIN=/tmp/certificate-subject.txt

exam_cleanup() {
  if command -v helm &>/dev/null; then
    helm uninstall my-nginx &>/dev/null || true
    helm uninstall "$Q6_REL" -n "$Q6_NS" &>/dev/null || true
  fi
  kdel deployment,service -l app.kubernetes.io/instance=my-nginx -n default
  kdel deployment dev-web-app -n default
  kdel namespace "$Q6_NS"
  # CRD 는 setup 이 직접 만든 경우에만 지운다 (원래 있던 Argo CD · cert-manager 는 건드리지 않는다).
  # CRD 를 지우면 그 종류의 오브젝트도 전부 지워진다. --timeout 은 finalizer 에 걸려 영영 기다리는 것을 막는다.
  if [[ -f "$ARGO_MARK" ]]; then
    kubectl delete crd "${ARGO_CRDS[@]}" --ignore-not-found --timeout=60s &>/dev/null &
    rm -f "$ARGO_MARK"
  fi
  if [[ -f "$CM_MARK" ]]; then
    kubectl delete crd "${CM_CRDS[@]}" --ignore-not-found --timeout=60s &>/dev/null &
    rm -f "$CM_MARK"
  fi
  rm -rf /tmp/kustomize-lab "$Q5_OUT" "$Q7_LIST" "$Q7_EXPLAIN" 2>/dev/null || true
  echo "  helm release my-nginx · $Q6_REL($Q6_NS), dev-web-app, /tmp/kustomize-lab 삭제"
  echo "  $Q6_NS 네임스페이스, $Q5_OUT · $Q7_LIST · $Q7_EXPLAIN 삭제"
  echo "  (setup 이 만든 Argo CD · cert-manager CRD 만 삭제 — 원래 있던 CRD 는 남겨둠)"
}
exam_setup() {
  command -v helm &>/dev/null || echo "  [주의] helm 이 설치돼 있지 않습니다 — Q1~Q3 · Q5 · Q6 을 풀 수 없습니다"
  echo "  (인터넷이 필요합니다 — 차트와 CRD 를 내려받습니다)"

  # Q6 — Argo CD CRD 를 미리 설치해 둔다 (차트는 CRD 없이 설치하라는 문제)
  #   ApplicationSet CRD 는 커서 client-side apply 의 annotation 한도(256KiB)를 넘는다 → --server-side
  if kubectl get crd applications.argoproj.io &>/dev/null; then
    echo "  Q6: Argo CD CRD 가 이미 있습니다 — 그대로 씁니다"
  else
    touch "$ARGO_MARK"      # 일부만 만들어져도 cleanup 이 지우도록 먼저 표시
    kubectl apply --server-side \
      -f "$ARGO_CRD_BASE/application-crd.yaml" \
      -f "$ARGO_CRD_BASE/applicationset-crd.yaml" \
      -f "$ARGO_CRD_BASE/appproject-crd.yaml" &>/dev/null \
      && echo "  Q6: Argo CD CRD 3개 설치 (applications · applicationsets · appprojects .argoproj.io)" \
      || echo "  [주의] Argo CD CRD 설치 실패 (인터넷 연결 확인) — Q6 의 Argo CD 파드가 뜨지 않습니다"
  fi

  # Q7 — cert-manager CRD 만 설치 (컨트롤러 없음 → 파드는 생기지 않는다)
  if kubectl get crd certificates.cert-manager.io &>/dev/null; then
    echo "  Q7: cert-manager CRD 가 이미 있습니다 — 그대로 씁니다"
  else
    touch "$CM_MARK"
    kubectl apply -f "$CM_CRDS_URL" &>/dev/null \
      && echo "  Q7: cert-manager ${CM_VERSION} CRD 6개 설치 (CRD 만 — cert-manager 본체는 없음)" \
      || echo "  [주의] cert-manager CRD 설치 실패 (인터넷 연결 확인) — Q7 을 풀 수 없습니다"
  fi
  # kubectl explain 은 CRD 가 Established 된 뒤에야 스키마를 보여 준다
  kubectl wait --for=condition=Established crd/certificates.cert-manager.io --timeout=30s &>/dev/null || true

  echo "  Q6 은 Argo CD 를 실제로 설치합니다 (파드 7개 · 메모리 약 0.5~1GiB). 이미지 내려받기에 몇 분 걸릴 수 있습니다"
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Add a repo and install a chart"; }
q1_text() { cat <<'EOF'
  1) add the chart repository
     name bitnami / url https://charts.bitnami.com/bitnami
  2) install the nginx chart as a release named my-nginx
     set service.type=NodePort

The release must show status "deployed".

Verify:
  helm list
  kubectl get svc -l app.kubernetes.io/instance=my-nginx
EOF
}
q1_title_ko() { echo "repo 추가 후 차트 설치"; }
q1_text_ko() { cat <<'EOF'
  1) 차트 저장소를 추가한다
     이름 bitnami / 주소 https://charts.bitnami.com/bitnami
  2) nginx 차트를 my-nginx 릴리스로 설치한다
     service.type=NodePort 로 설정

릴리스 상태가 deployed 여야 한다.

[확인]
  helm list
  kubectl get svc -l app.kubernetes.io/instance=my-nginx
EOF
}
q1_grade() {
  check "helm 이 설치돼 있다" "command -v helm"
  check_output "bitnami repo 가 등록됨" "helm repo list 2>/dev/null" 'bitnami'
  check_output "릴리스 my-nginx 가 있다" "helm list -A 2>/dev/null" 'my-nginx'
  check_output "상태가 deployed" "helm list -A 2>/dev/null | grep my-nginx" 'deployed'
  check_output "차트가 만든 Service 가 NodePort" \
    "kubectl get svc -l app.kubernetes.io/instance=my-nginx -n default -o jsonpath='{.items[0].spec.type}'" '^NodePort$'
}
q1_hint() { cat <<'EOF'
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install my-nginx bitnami/nginx --set service.type=NodePort
helm list
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Upgrade the release"; }
q2_text() { cat <<'EOF'
Upgrade the my-nginx release so that it runs 3 replicas.

  helm upgrade with replicaCount=3

After the upgrade the release revision must be 2 or higher and three Pods
must be running.

Verify:
  helm history my-nginx
  kubectl get pods -l app.kubernetes.io/instance=my-nginx
EOF
}
q2_title_ko() { echo "릴리스 업그레이드"; }
q2_text_ko() { cat <<'EOF'
my-nginx 릴리스를 레플리카 3개로 업그레이드하시오.

  helm upgrade 로 replicaCount=3

업그레이드 후 릴리스 리비전이 2 이상이고 파드 3개가 떠야 한다.

[확인]
  helm history my-nginx
  kubectl get pods -l app.kubernetes.io/instance=my-nginx
EOF
}
q2_grade() {
  check_output "릴리스 리비전이 2 이상" \
    "helm list -A -o json 2>/dev/null | grep -o '\"revision\":\"[0-9]*\"' | head -1" '"[2-9]"'
  check_output "Deployment 의 replicas 가 3" \
    "kubectl get deployment -l app.kubernetes.io/instance=my-nginx -n default -o jsonpath='{.items[0].spec.replicas}'" '^3$'
  wait_ready "-l app.kubernetes.io/instance=my-nginx" default
  check_output "파드 3개가 Ready" \
    "kubectl get deployment -l app.kubernetes.io/instance=my-nginx -n default -o jsonpath='{.items[0].status.readyReplicas}'" '^3$'
}
q2_hint() { cat <<'EOF'
helm upgrade my-nginx bitnami/nginx --set replicaCount=3 --set service.type=NodePort
helm history my-nginx
kubectl get pods -l app.kubernetes.io/instance=my-nginx
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Roll back the release"; }
q3_text() { cat <<'EOF'
Roll the my-nginx release back to revision 1.

  - check the revisions with helm history
  - roll back to revision 1

After the rollback there must be a new revision (3 or higher) and the
Deployment must be back to 1 replica.

Verify:
  helm history my-nginx
  kubectl get deployment -l app.kubernetes.io/instance=my-nginx
EOF
}
q3_title_ko() { echo "릴리스 롤백"; }
q3_text_ko() { cat <<'EOF'
my-nginx 릴리스를 리비전 1 로 롤백하시오.

  - helm history 로 리비전을 확인한다
  - 리비전 1 로 롤백한다

롤백하면 새 리비전(3 이상)이 생기고 Deployment 의 레플리카가 1 로
돌아와야 한다.

[확인]
  helm history my-nginx
  kubectl get deployment -l app.kubernetes.io/instance=my-nginx
EOF
}
q3_grade() {
  check_output "리비전이 3 이상 (롤백도 새 리비전이다)" \
    "helm list -A -o json 2>/dev/null | grep -o '\"revision\":\"[0-9]*\"' | head -1" '"[3-9]"'
  check_output "history 에 rollback 기록" "helm history my-nginx 2>/dev/null" 'Rollback|rollback'
  check_output "replicas 가 1 로 돌아왔다" \
    "kubectl get deployment -l app.kubernetes.io/instance=my-nginx -n default -o jsonpath='{.items[0].spec.replicas}'" '^1$'
}
q3_hint() { cat <<'EOF'
helm history my-nginx
helm rollback my-nginx 1
helm history my-nginx      # Rollback to 1 이라는 줄이 추가된다
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Kustomize base and overlay"; }
q4_text() { cat <<'EOF'
Build a Kustomize directory under /tmp/kustomize-lab and apply it.

  base/deployment.yaml       a Deployment named web-app (nginx:1.24)
  base/kustomization.yaml    includes deployment.yaml as a resource
  overlays/dev/kustomization.yaml
                             refers to ../../base and sets namePrefix: dev-

Then apply the overlay:
  kubectl apply -k /tmp/kustomize-lab/overlays/dev/

The result must be a Deployment named dev-web-app.

Verify:
  kubectl get deployment dev-web-app
EOF
}
q4_title_ko() { echo "Kustomize base 와 overlay"; }
q4_text_ko() { cat <<'EOF'
/tmp/kustomize-lab 아래에 Kustomize 디렉터리를 만들고 적용하시오.

  base/deployment.yaml       web-app Deployment (nginx:1.24)
  base/kustomization.yaml    deployment.yaml 을 resources 로 포함
  overlays/dev/kustomization.yaml
                             ../../base 를 참조하고 namePrefix: dev- 설정

그다음 overlay 를 적용한다:
  kubectl apply -k /tmp/kustomize-lab/overlays/dev/

결과로 dev-web-app Deployment 가 만들어져야 한다.

[확인]
  kubectl get deployment dev-web-app
EOF
}
q4_grade() {
  check "base/kustomization.yaml 존재" "test -f /tmp/kustomize-lab/base/kustomization.yaml"
  check "base/deployment.yaml 존재" "test -f /tmp/kustomize-lab/base/deployment.yaml"
  check "overlays/dev/kustomization.yaml 존재" "test -f /tmp/kustomize-lab/overlays/dev/kustomization.yaml"
  check_output "overlay 에 namePrefix: dev-" \
    "cat /tmp/kustomize-lab/overlays/dev/kustomization.yaml 2>/dev/null" 'namePrefix:\s*dev-'
  check_output "overlay 가 base 를 참조" \
    "cat /tmp/kustomize-lab/overlays/dev/kustomization.yaml 2>/dev/null" '\.\./\.\./base|resources'
  check "Deployment dev-web-app 이 생성됨" "kubectl get deployment dev-web-app -n default"
  check_output "이미지 nginx:1.24" \
    "kubectl get deployment dev-web-app -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" 'nginx:1\.24'
}
q4_hint() { cat <<'EOF'
mkdir -p /tmp/kustomize-lab/base /tmp/kustomize-lab/overlays/dev
kubectl create deployment web-app --image=nginx:1.24 $do > /tmp/kustomize-lab/base/deployment.yaml

cat > /tmp/kustomize-lab/base/kustomization.yaml <<'YAML'
resources:
  - deployment.yaml
YAML

cat > /tmp/kustomize-lab/overlays/dev/kustomization.yaml <<'YAML'
resources:
  - ../../base
namePrefix: dev-
YAML

kubectl apply -k /tmp/kustomize-lab/overlays/dev/
EOF
}

# ══════════════════════════════════════════════════════════════
q5_title() { echo "Render a chart without installing it — no release name"; }
q5_text() { cat <<'EOF'
Sometimes you need the manifests a chart would produce, without touching
the cluster — for review, for GitOps, or to install the CRDs separately.

  1) add the Helm repository
       name  argo
       url   https://argoproj.github.io/argo-helm

  2) render the chart argo/argo-cd WITHOUT installing it
       chart version   7.7.0
       release name    do NOT pass one — let Helm use its default
       namespace       argocd
       CRDs            must NOT be in the output
       save it to      /tmp/argocd.yaml

Do not install the chart into the cluster.

Verify:
  grep -m1 'app.kubernetes.io/instance:' /tmp/argocd.yaml   -> release-name
  grep -m1 'helm.sh/chart:' /tmp/argocd.yaml                -> argo-cd-7.7.0
  grep -c 'kind: CustomResourceDefinition' /tmp/argocd.yaml -> 0
  helm list -A                                              -> no new release
EOF
}
q5_title_ko() { echo "릴리스 이름 없이 매니페스트만 뽑기"; }
q5_text_ko() { cat <<'EOF'
차트가 만들어 낼 매니페스트만 필요할 때가 있다. 클러스터는 건드리지 않고
검토하거나, GitOps 로 넘기거나, CRD 만 따로 설치하려는 경우다.

  1) Helm 저장소를 추가한다
       이름  argo
       주소  https://argoproj.github.io/argo-helm

  2) argo/argo-cd 차트를 설치하지 말고 렌더링만 한다
       차트 버전     7.7.0
       릴리스 이름   주지 않는다 — Helm 의 기본값을 쓴다
       네임스페이스  argocd
       CRD           결과에 들어가면 안 된다
       저장 경로     /tmp/argocd.yaml

클러스터에 설치하지 않는다.

[확인]
  grep -m1 'app.kubernetes.io/instance:' /tmp/argocd.yaml   → release-name
  grep -m1 'helm.sh/chart:' /tmp/argocd.yaml                → argo-cd-7.7.0
  grep -c 'kind: CustomResourceDefinition' /tmp/argocd.yaml → 0
  helm list -A                                              → 새 릴리스 없음
EOF
}
q5_grade() {
  check "helm 이 설치돼 있다" "command -v helm"
  check_output "argo 저장소가 추가됐다" "helm repo list 2>/dev/null" 'argoproj\.github\.io/argo-helm'
  check "$Q5_OUT 이 있다" "test -s $Q5_OUT"
  check_output "차트 버전 7.7.0 으로 렌더링했다 (--version)" \
    "grep -m1 'helm.sh/chart: argo-cd-' $Q5_OUT 2>/dev/null" 'argo-cd-7\.7\.0$'
  check_output "네임스페이스 argocd 로 렌더링했다" \
    "grep -m1 '^  namespace:' $Q5_OUT 2>/dev/null" 'namespace: argocd$'
  # 릴리스 이름을 안 주면 helm template 은 release-name 이라는 이름을 쓴다
  check_output "릴리스 이름을 주지 않았다 (instance: release-name)" \
    "grep -m1 'app.kubernetes.io/instance:' $Q5_OUT 2>/dev/null" 'instance: release-name$' 2
  check_output "리소스 이름 앞에 release-name- 이 붙었다" \
    "grep -m1 -E '^  name: release-name-' $Q5_OUT 2>/dev/null" 'release-name-'
  # CRD 가 빠졌는지 — 이 차트는 CRD 를 templates/ 에 두므로 crds.install=false 가 필요하다
  local crd; crd=$(grep -c 'kind: CustomResourceDefinition' "$Q5_OUT" 2>/dev/null)
  crd="${crd//[^0-9]/}"; crd="${crd:-0}"
  local has=1; [[ -s "$Q5_OUT" ]] && has=0
  check_result "CRD 가 빠져 있다 (현재 ${crd}개)" \
    "$([[ $has == 0 && "$crd" == "0" ]] && echo 0 || echo 1)" "--skip-crds 로 안 빠지면 차트 values 의 crds 설정을 본다" 2
  # 설치는 하지 말라고 했다 — 이름 없이 install 하려다 --generate-name 을 쓴 경우도 잡는다
  local inst; inst=$(helm list -A -q 2>/dev/null | grep -cE '^(release-name|argo-cd-[0-9]+)$')
  inst="${inst//[^0-9]/}"; inst="${inst:-0}"
  check_result "클러스터에 설치하지는 않았다" \
    "$([[ "$inst" == "0" ]] && echo 0 || echo 1)" "release-name(또는 argo-cd-<숫자>) 릴리스가 있다 — template 만 하면 된다"
}
q5_hint() { cat <<'EOF'
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 인자가 차트 하나뿐이면 helm template 은 릴리스 이름으로 "release-name" 을 쓴다
helm template argo/argo-cd \
  --version 7.7.0 \
  --namespace argocd \
  --skip-crds \
  --set crds.install=false > /tmp/argocd.yaml

grep -m1 'app.kubernetes.io/instance:' /tmp/argocd.yaml     # release-name
grep -c 'kind: CustomResourceDefinition' /tmp/argocd.yaml   # 0 이어야 한다

# --skip-crds 는 차트의 crds/ 폴더만 뺀다. argo-cd 차트는 CRD 를 templates/ 안에 두기 때문에
# 차트가 제공하는 값(crds.install=false)으로 꺼야 한다 → helm show values 로 crds 키를 찾아본다.
#   helm show values argo/argo-cd --version 7.7.0 | grep -A3 '^crds:'
# (helm install 은 이름이 없으면 에러다 — 이름 생략은 template 에서만 된다)
EOF
}

# ══════════════════════════════════════════════════════════════
q6_title() { echo "Install the chart without its CRDs"; }
q6_text() { cat <<'EOF'
The Argo CD CRDs are already installed in the cluster (they are managed
separately). Now install Argo CD itself with Helm.

  chart           argo/argo-cd
  chart version   7.7.0
  release name    argocd
  namespace       argocd   (create it)
  CRDs            the chart must NOT install them

The release must show status "deployed" and the argocd-server Pod must
become Ready (pulling the images can take a few minutes).

Verify:
  kubectl get crd | grep argoproj
  helm list -n argocd
  helm get values argocd -n argocd
  kubectl get pods -n argocd
EOF
}
q6_title_ko() { echo "CRD 를 빼고 차트 설치"; }
q6_text_ko() { cat <<'EOF'
Argo CD 의 CRD 는 클러스터에 이미 설치돼 있다 (따로 관리한다).
이번에는 Argo CD 본체를 Helm 으로 설치하시오.

  차트           argo/argo-cd
  차트 버전      7.7.0
  릴리스 이름    argocd
  네임스페이스   argocd   (만들어서)
  CRD            차트가 설치하면 안 된다

릴리스 상태가 deployed 이고 argocd-server 파드가 Ready 여야 한다
(이미지를 내려받느라 몇 분 걸릴 수 있다).

[확인]
  kubectl get crd | grep argoproj
  helm list -n argocd
  helm get values argocd -n argocd
  kubectl get pods -n argocd
EOF
}
q6_grade() {
  check "helm 이 설치돼 있다" "command -v helm"
  check_output "argocd 네임스페이스에 릴리스 argocd 가 있다" \
    "helm list -n $Q6_NS -q 2>/dev/null" "^${Q6_REL}\$"
  check_output "상태가 deployed" "helm status $Q6_REL -n $Q6_NS 2>/dev/null" 'STATUS: deployed'
  check_output "차트 버전 argo-cd-7.7.0" \
    "helm list -n $Q6_NS 2>/dev/null | grep -E '^${Q6_REL}[[:space:]]'" 'argo-cd-7\.7\.0'
  check_output "crds.install=false 로 설치했다" \
    "helm get values $Q6_REL -n $Q6_NS -o json 2>/dev/null" '"crds":\{[^}]*"install":false' 2
  # 미리 깔아 둔 CRD 가 그대로이고 Helm 릴리스 소유가 아닌지
  local crd owner
  crd=$(kubectl get crd applications.argoproj.io -o name 2>/dev/null)
  owner=$(kubectl get crd applications.argoproj.io -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null)
  check_result "CRD 는 Helm 릴리스가 관리하지 않는다" \
    "$([[ -n "$crd" && -z "$owner" ]] && echo 0 || echo 1)" \
    "$([[ -z "$crd" ]] && echo 'applications.argoproj.io CRD 가 없다 — bash exam.sh start 로 다시 준비' || echo "CRD 가 릴리스 ${owner} 소유다")"
  check "Deployment argocd-server 가 있다" "kubectl get deployment argocd-server -n $Q6_NS"
  wait_ready "-l app.kubernetes.io/name=argocd-server" "$Q6_NS"
  check_output "argocd-server 파드가 Ready" \
    "kubectl get deployment argocd-server -n $Q6_NS -o jsonpath='{.status.readyReplicas}'" '^[1-9]'
}
q6_hint() { cat <<'EOF'
kubectl get crd | grep argoproj                        # CRD 는 이미 있다

helm show values argo/argo-cd --version 7.7.0 | grep -A3 '^crds:'
helm install argocd argo/argo-cd \
  --version 7.7.0 \
  --namespace argocd --create-namespace \
  --set crds.install=false

helm list -n argocd
helm get values argocd -n argocd       # crds: install: false
kubectl get pods -n argocd -w          # 이미지 pull 이 끝날 때까지

# crds.install=false 를 빼면 "CustomResourceDefinition ... exists and cannot be imported
# into the current release" 로 설치가 실패한다 — 이미 있는 CRD 를 Helm 이 가져갈 수 없어서다.
EOF
}

# ══════════════════════════════════════════════════════════════
q7_title() { echo "Save a project's CRD list and a CRD field description"; }
q7_text() { cat <<'EOF'
The cert-manager CRDs are installed in the cluster (only the CRDs, not
cert-manager itself).

  1) Save the list of ALL cert-manager CRDs to
       /tmp/cert-manager-crds.txt
     using kubectl's default output format (do not use -o).
     The file must not contain any other CRDs.

  2) Save the documentation of the field spec.subject of the cert-manager
     Certificate resource to
       /tmp/certificate-subject.txt
     using kubectl.

Verify:
  cat /tmp/cert-manager-crds.txt
  head -8 /tmp/certificate-subject.txt
EOF
}
q7_title_ko() { echo "CRD 목록과 필드 설명을 파일로"; }
q7_text_ko() { cat <<'EOF'
클러스터에 cert-manager 의 CRD 가 설치돼 있다 (CRD 만 있고 cert-manager 본체는 없다).

  1) cert-manager 의 CRD 목록을 전부
       /tmp/cert-manager-crds.txt
     에 저장한다. kubectl 의 기본 출력 형식으로 (-o 를 쓰지 않는다).
     다른 CRD 가 섞이면 안 된다.

  2) cert-manager Certificate 리소스의 spec.subject 필드 설명을
       /tmp/certificate-subject.txt
     에 저장한다. kubectl 로.

[확인]
  cat /tmp/cert-manager-crds.txt
  head -8 /tmp/certificate-subject.txt
EOF
}
q7_grade() {
  # 1) CRD 목록 — 이름이 다 있고, 기본 형식(NAME  CREATED AT)이고, 다른 CRD 가 없어야 한다
  check "$Q7_LIST 이 있다" "test -s $Q7_LIST"
  local want got ts other has=1
  [[ -s "$Q7_LIST" ]] && has=0
  want=$(kubectl get crd -o name 2>/dev/null | grep -c 'cert-manager\.io$'); want="${want//[^0-9]/}"; want="${want:-0}"
  got=$(grep -oE '^[a-z0-9.-]+\.cert-manager\.io' "$Q7_LIST" 2>/dev/null | sort -u | wc -l); got="${got//[^0-9]/}"; got="${got:-0}"
  ts=$(grep -cE '^[a-z0-9.-]+\.cert-manager\.io[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$Q7_LIST" 2>/dev/null); ts="${ts//[^0-9]/}"; ts="${ts:-0}"
  other=$(grep -vE '^NAME[[:space:]]|^[[:space:]]*$|cert-manager\.io' "$Q7_LIST" 2>/dev/null | wc -l); other="${other//[^0-9]/}"; other="${other:-0}"
  check_result "cert-manager CRD 가 모두 들어 있다 (${got}/${want})" \
    "$([[ $has == 0 && "$want" -gt 0 && "$got" == "$want" ]] && echo 0 || echo 1)" \
    "$([[ "$want" == "0" ]] && echo '클러스터에 cert-manager CRD 가 없다 — bash exam.sh start 로 다시 준비' || echo 'kubectl get crd | grep cert-manager')" 2
  check_result "기본 출력 형식이다 (NAME · CREATED AT)" \
    "$([[ $has == 0 && "$want" -gt 0 && "$ts" == "$want" ]] && echo 0 || echo 1)" "-o name / -o yaml 이 아니라 그냥 kubectl get crd 의 줄이어야 한다"
  check_result "다른 CRD 가 섞이지 않았다" \
    "$([[ $has == 0 && "$other" == "0" ]] && echo 0 || echo 1)" "cert-manager 가 아닌 줄 ${other}개 — grep 으로 거른다"

  # 2) kubectl explain 결과
  check "$Q7_EXPLAIN 이 있다" "test -s $Q7_EXPLAIN"
  check_output "Certificate 리소스의 설명이다" "cat $Q7_EXPLAIN 2>/dev/null" '^KIND:[[:space:]]+Certificate$'
  check_output "spec.subject 필드의 설명이다" "cat $Q7_EXPLAIN 2>/dev/null" '^(FIELD|RESOURCE):[[:space:]]+subject'
  check_output "subject 의 하위 필드가 보인다 (organizations 등)" "cat $Q7_EXPLAIN 2>/dev/null" 'organizations'
}
q7_hint() { cat <<'EOF'
# 1) 기본 출력 그대로, cert-manager 것만 거른다 (헤더 줄은 있어도 없어도 된다)
kubectl get crd | grep cert-manager > /tmp/cert-manager-crds.txt
cat /tmp/cert-manager-crds.txt

# 2) 리소스 이름(단수·복수·짧은 이름)으로 필드 경로를 따라간다
kubectl api-resources | grep cert-manager        # certificate 의 이름·그룹 확인
kubectl explain certificate.spec.subject > /tmp/certificate-subject.txt
head -8 /tmp/certificate-subject.txt             # KIND: Certificate / FIELD: subject

# -o name 이나 -o yaml 은 "기본 출력 형식" 이 아니다.
EOF
}

exam_main "$@"
