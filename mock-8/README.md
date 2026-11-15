# Mock Exam 8 — 후기 상위 7유형 40분 점검 (강사용)

> **문제만 보려면 `QUESTIONS.txt`.** 이 파일에는 정답이 들어 있다.
>
> **한 문제씩 풀기:** `bash exam.sh start` → 풀고 → `bash exam.sh check`. 끝나면 `bash exam.sh clean`.

## 목적

`시험정보/CKA_출제유형_문제와풀이_2025-2026.pdf` 의 19개 유형(2025-06 ~ 2026-06 합격 후기 9건) 중, **한 클러스터에서 40분 안에 풀 수 있는 7개**를 모았다. 실제 시험이 문항당 7분쯤(120분 · 16~17문항)인데 이 세트는 문항당 5.7분이라 조금 더 빠듯하다.

| 문항 | 유형 번호 · 주제 | 출제영역 | 후기 언급 | 배점 | 목표 시간 | 함정 |
|------|------------------|----------|-----------|------|-----------|------|
| Q1 | 02 Helm — template + CRD 없이 install | Cluster Architecture | 7/9 | 15 | 5분 | `--skip-crds` 로는 CRD 가 안 빠진다 (`crds.install=false`). install 에도 같은 값이 필요하다 |
| Q2 | 07 HPA — 기존 Deployment 에 붙이기 | Workloads & Scheduling | 4/9 | 10 | 4분 | HPA 이름이 Deployment 와 다르다(`--name`). `behavior` 는 명령 옵션이 없다. dry-run YAML 끝에 붙이면 `status.behavior` 로 거부된다 |
| Q3 | 01 Gateway API — Ingress 옮기기 | Services & Networking | 7/9 | 20 | 8분 | 리스너 `hostname` 누락, 백엔드 포트(8080)를 80 으로 적음, Ingress 를 안 지움 |
| Q4 | 08 StorageClass — 유일한 기본 | Storage | 4/9 | 10 | 4분 | 기존 기본(`bulk-hdd`)을 해제하지 않음 · 지워 버림 |
| Q5 | 04 트러블슈팅 — kubelet 이 멈춘 워커 | Troubleshooting | 5/9 | 15 | 8분 | 두 겹이다: disabled + 정지, 그리고 드롭인의 실행 파일 경로가 틀렸다. `enable --now` 만 하면 계속 죽는다 |
| Q6 | 06 NetworkPolicy — 세 개 중 고르기 | Services & Networking | 5/9 | 15 | 5분 | policy-2 는 되는 쪽만 확인하면 맞아 보인다 (같은 네임스페이스까지 연다) |
| Q7 | 11 PriorityClass — 최댓값 - 1 | Workloads & Scheduling | 3/9 | 15 | 3분 | `spec.template.spec` 아래. 값은 만든 뒤 못 바꾼다 |

목표 시간 합계 37분. 뺀 유형은 CNI 설치 · 컨트롤플레인 고장 · cri-dockerd · etcd 복원 — 오래 걸리거나 클러스터를 통째로 써서 다른 문제와 같이 못 돌린다.

## 환경

`exam.sh start` 가 준비하는 것:

| 문항 | 네임스페이스 | 미리 만드는 것 |
|------|--------------|----------------|
| Q1 | (학생이 `cd-system` 생성) | Argo CD CRD 3개 (v2.13.0, 없을 때만). 릴리스 · 저장소는 학생이 만든다 |
| Q2 | `checkout` | Deployment `cart-api` (replicas 2 · cpu requests 50m) |
| Q3 | `bookstore` · `nginx-gateway` | **NGINX Gateway Fabric v2.7.0** (없을 때만 설치, GatewayClass `nginx`), `catalog`(+`catalog-svc:8080`), Secret `books-tls`, Ingress `books-ingress`(host `books.example.local` · `/catalog`) |
| Q4 | — | StorageClass `bulk-hdd` (기본). 클러스터에 원래 있던 기본 클래스는 적어 두었다가 `clean` 이 되돌린다 |
| Q5 | — | 멈출 워커를 고른다 (taint 없는 Ready 워커 중 이름순 마지막). **kubelet 은 Q5 에 들어갈 때 멈춘다** |
| Q6 | `shopfront` · `stockroom` | `stockroom/stock-api`(+Service) · `stockroom/audit` · `shopfront/web`, `/tmp/mock8-netpol/policy-1~3.yaml` |
| Q7 | `telemetry` | PriorityClass `tier-critical`(800000) · `tier-standard`(400000) · `tier-batch`(1000), Deployment `metrics-relay`(2개) |

- 제한시간 40분. `EXAM_LIMIT_MIN=0 bash exam.sh start` 로 풀면 무제한 연습.
- **인터넷이 필요하다** — Q1 차트 · CRD, Q3 컨트롤러. 08-ingress · mock-7 을 돌린 클러스터면 컨트롤러 설치를 건너뛴다.
- **Q1 은 Argo CD 를 실제로 설치한다** (파드 7개, 이미지 약 1GB). 채점은 릴리스 상태만 보고 파드 Ready 는 기다리지 않는다. 디스크가 빠듯한 환경에서는 채점 뒤 `kubectl -n cd-system scale deployment,statefulset --all --replicas=0` 으로 이미지 내려받기를 멈출 수 있다 (점수에 영향 없다).
- **Q5 가 kubelet 을 멈추는 방법**
  - 그 워커에 `/etc/systemd/system/kubelet.service.d/20-override.conf` 를 얹어 `ExecStart` 의 실행 파일 경로를 없는 경로(`/usr/local/bin/kubelet`)로 바꾸고, 12초 뒤 `systemctl disable --now kubelet` 을 건다. 패키지가 깐 파일(`10-kubeadm.conf`)은 건드리지 않는다. 원래 `ExecStart` 줄을 읽어서 만들기 때문에 kubelet 위치가 다른 배포판에서도 된다.
  - 노드에서 root 로 실행하는 길은 둘이다. ① control-plane → 워커로 **비밀번호 없는 ssh + `sudo -n`** 이 되면 ssh. ② 안 되면 그 노드에 **특권 파드**(hostPID + nsenter, `kube-system/mock8-node-helper-*`)를 잠깐 띄운다. start 화면의 "준비 방법" 에 어느 쪽인지 나온다.
  - 되살리기: `clean` · 마지막 문제 뒤 마감 · 시간 초과 · 다시 `start` · `reset` 때 드롭인을 지우고 `enable --now` 한다. **ssh 가 안 되고 학생도 못 고친 경우에는 자동으로 되살릴 수 없다** (kubelet 이 죽어 있으면 파드를 못 띄운다) — 화면에 손으로 칠 세 줄이 나온다.
  - 다른 문제의 파드(Q3 백엔드 · Q6 · Q7)는 nodeAffinity 로 그 워커를 피해 뜬다. Q5 를 못 고친 채 넘어가도 Q3 · Q6 · Q7 채점이 흔들리지 않는다.
  - 조건에 맞는 워커가 없으면(단일 노드, 또는 워커를 멈추면 파드를 받을 노드가 안 남는 경우) Q5 는 내지 않고 **통과 처리(15점)** 한다.
- Q6 은 CNI 가 NetworkPolicy 를 지원해야 한다 (Cilium · Calico. Flannel 은 안 된다).

## 정답

```bash
# Q1 — --skip-crds 는 차트의 crds/ 폴더만 뺀다. 이 차트는 CRD 를 templates/ 에 두고 crds.install 로 켜고 끈다
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm show values argo/argo-cd --version 7.7.0 | grep -A3 '^crds:'
helm template cd-main argo/argo-cd --version 7.7.0 -n cd-system \
  --set crds.install=false > /tmp/mock8-argocd.yaml
grep -c 'kind: CustomResourceDefinition' /tmp/mock8-argocd.yaml     # 0
helm install cd-main argo/argo-cd --version 7.7.0 -n cd-system --create-namespace \
  --set crds.install=false

# Q2
cat <<'YAML' | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: cart-api-hpa, namespace: checkout }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: cart-api }
  minReplicas: 2
  maxReplicas: 6
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 60 } }
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 45
YAML

# Q3 — Ingress 에서 host · secretName · path · backend 를 읽어 옮긴다
kubectl -n bookstore get ingress books-ingress -o yaml
cat <<'YAML' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: books-gateway, namespace: bookstore }
spec:
  gatewayClassName: nginx
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      hostname: books.example.local
      tls:
        mode: Terminate
        certificateRefs:
          - { kind: Secret, name: books-tls }
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: books-route, namespace: bookstore }
spec:
  parentRefs: [ { name: books-gateway } ]
  hostnames: [ books.example.local ]
  rules:
    - matches: [ { path: { type: PathPrefix, value: /catalog } } ]
      backendRefs: [ { name: catalog-svc, port: 8080 } ]
YAML
kubectl -n bookstore delete ingress books-ingress

# Q4
cat <<'YAML' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-nvme
  annotations: { storageclass.kubernetes.io/is-default-class: "true" }
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
YAML
kubectl patch storageclass bulk-hdd \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# Q5 — 워커에 들어가서 (노드 이름은 문제에 나온다)
ssh <노드>; sudo -i
systemctl status kubelet --no-pager          # inactive (dead) · disabled · Drop-In 에 20-override.conf
systemctl enable --now kubelet               # 그래도 activating (auto-restart)
journalctl -u kubelet -n 20 --no-pager       # Failed at step EXEC spawning /usr/local/bin/kubelet (203/EXEC)
systemctl cat kubelet                        # 마지막 ExecStart 가 없는 경로를 가리킨다
rm /etc/systemd/system/kubelet.service.d/20-override.conf    # 또는 파일 안의 경로를 실제 위치(which kubelet)로 고친다
systemctl daemon-reload && systemctl restart kubelet

# Q6 — policy-1: 네임스페이스에 name=shopfront 레이블이 없다(아무도 못 들어온다)
#       policy-2: from 항목이 둘(OR) — "- podSelector: {}" 가 stockroom 의 모든 파드를 연다
kubectl get ns shopfront --show-labels
kubectl apply -f /tmp/mock8-netpol/policy-3.yaml

# Q7
kubectl get priorityclass --sort-by=.value           # 사용자 정의 최댓값 800000
kubectl create priorityclass relay-priority --value=799999 --description="metrics relay"
kubectl -n telemetry patch deployment metrics-relay \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"relay-priority"}}}}'
kubectl -n telemetry rollout status deployment metrics-relay
```

## 자주 틀리는 곳 (실제로 넣어 본 점수)

| 문항 | 실수 | 점수 |
|------|------|------|
| Q1 | `--skip-crds` 만 쓰고, install 에 `crds.install=false` 를 안 줌 (install 은 "exists and cannot be imported" 로 실패) | 5/15 |
| Q2 | `kubectl autoscale` 만 하고 behavior 를 안 넣음 | 8/10 |
| Q3 | 리스너 hostname 누락 + 백엔드 포트 80 + Ingress 안 지움 | 13/20 |
| Q3 | Gateway 를 만들기 전에 Ingress 만 지움 | 0/20 |
| Q4 | fast-nvme 을 기본으로 만들었지만 bulk-hdd 를 해제하지 않음 | 7/10 |
| Q4 | bulk-hdd 를 지우고 다시 만듦 | 9/10 (되돌릴 수 없다) |
| Q5 | `enable --now` 만 함 (경로는 그대로) | 4/15 (특권 파드 경로에서는 0/15 — 노드 안을 못 본다) |
| Q6 | policy-1 적용 | 1/15 |
| Q6 | policy-2 적용 | 4/15 |
| Q6 | policy-2 와 policy-3 을 둘 다 적용 | 8/15 |
| Q6 | 파일을 고쳐서 적용 | 14/15 |
| Q7 | 값을 +1 로 계산 · globalDefault true | 6/15 |

아무것도 하지 않고 `check` 하면 7문항 모두 0점이다.

## 채점에서 알아둘 것

- Q3 · Q7 은 리소스를 만든 직후 채점해도 되게 기다린다 — Q3 은 게이트웨이 데이터 플레인 파드가 뜰 때까지 30초까지, Q7 은 롤아웃이 끝날 때까지 20초까지.
- Q5 는 노드가 Ready 인 것만으로는 점수를 주지 않는다. kubelet 을 멈춘 뒤에도 노드는 40~50초 동안 Ready 로 보이고, 문제에 들어간 직후 12초는 아직 멈추기 전이기 때문이다. 노드 안에서 `is-active` 가 active 이고 정지 예약이 끝난 뒤일 때만 인정한다.
- Q5 의 kubelet 상태 확인이 특권 파드 경로이면 채점이 5초쯤, kubelet 이 죽은 직후에는 30초쯤 걸린다.
- Q6 은 실패 메모에 어느 후보가 왜 틀렸는지 적지 않는다 (고르는 것이 문제다).

## 검증 상태

- 2026-11-15 minikube `k8s-cilium`(v1.34.0 · Cilium · docker 드라이버 · **control-plane 1 + 워커 1**, control-plane 에 taint 없음)의 control-plane 노드 안에서 일반 사용자로 돌렸다. Helm 4.3.2, Q1 은 Helm 3.19.0 으로도 한 번.
  - 위 정답으로 **100/100**, 최종 리포트까지. 오답 점수는 위 표대로.
  - start → 풀이 → clean → 두 번째 start (CRD · 저장소 · StorageClass · PriorityClass · 파일이 남지 않는다).
  - Q5: ssh 경로와 특권 파드 경로 둘 다. 고치기 전 0점 · 드롭인을 고친 경우 · 드롭인을 지운 경우 15점. 문제에 들어간 직후 채점(0점), kubelet 이 죽은 직후 채점(0점).
  - Q5 를 못 고친 채 Q3 · Q6 · Q7 을 풀어 만점 (워커 NotReady 상태).
  - 제한시간 초과 → 자동 마감 → kubelet 복구 시도. ssh 가 없으면 손으로 칠 명령이 나오고, ssh 가 있으면 `clean` 이 되살린다.
  - 멈출 워커가 없는 경우(워커에 taint 를 걸어 흉내) Q5 통과 처리.
- **VirtualBox 클러스터(control-plane + worker-1 · worker-2, Ubuntu 24.04)에서는 아직 돌려 보지 않았다.** 확인할 것:
  - control-plane → 워커 ssh 가 비밀번호 없이 되는지 (안 되면 특권 파드 경로로 간다 — start 화면에 표시)
  - 우분투의 kubelet 드롭인 위치(`/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf`)에서 Q5 고장 · 복구
  - control-plane 에 taint 가 있고 워커가 2대일 때 파드 배치 (worker-2 를 멈추고 나머지는 worker-1 로 간다)
  - Argo CD 이미지를 내려받는 동안 VM 디스크 · 메모리 여유
