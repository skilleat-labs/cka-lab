# Mock Exam 9 — 시험 전 마지막 점검 · 자주 나오는 6유형 (강사용)

> **문제만 보려면 `QUESTIONS.txt`.** 이 파일에는 정답이 들어 있다.
>
> **한 문제씩 풀기:** `bash exam.sh start` → 풀고 → `bash exam.sh check`. 끝나면 `bash exam.sh clean`.

## 목적

시험 직전에 **자신감을 올리는** 세트. `시험정보/CKA_출제유형_문제와풀이_2025-2026.pdf` 의 풀이를 공부했으면 그대로 풀리게, 문서의 문제 형태에 이름과 값만 바꿔 냈다. 문서의 "놓치기 쉬운 것" 에 없는 함정은 넣지 않았다. Deployment · Service 만들기 같은 기초 문제는 뺐다.

| 문항 | 유형 번호 · 주제 | 출제영역 | 후기 언급 | 배점 | 목표 시간 | 문서와 다른 점 |
|------|------------------|----------|-----------|------|-----------|----------------|
| Q1 | 02 Helm — template + CRD 없이 install | Cluster Architecture | 7/9 | 15 | 5분 | 네임스페이스 `gitops-tools`, 파일 경로 |
| Q2 | 07 HPA — 기존 Deployment 에 붙이기 | Workloads & Scheduling | 4/9 | 15 | 4분 | 70% · 1~5 · 60초 |
| Q3 | 01 Gateway API — Ingress 옮기기 | Services & Networking | 7/9 | 20 | 8분 | 이름만 다르다 (경로 `/` · 포트 80 은 문서와 같다) |
| Q4 | 10 CRD — 목록과 필드 설명을 파일로 | Cluster Architecture | 4/9 | 15 | 4분 | 필드가 `spec.subject` 대신 `spec.privateKey` |
| Q5 | 04 트러블슈팅 — kubelet 이 멈춘 워커 | Troubleshooting | 5/9 | 15 | 4분 | 문서의 Step 3 까지만 (`enable --now` 한 줄). 설정 오류는 없다 |
| Q6 | 06 NetworkPolicy — 세 개 중 고르기 | Services & Networking | 5/9 | 20 | 5분 | 정답 위치가 b. 틀린 두 개의 종류는 문서와 같다 |

목표 시간 합계 30분, 제한 35분. mock-8 과 네 유형(01 · 02 · 04 · 06)이 겹치지만 mock-8 보다 쉽다 — Q5 는 한 겹이고, Q3 은 문서의 예제와 구조가 같다.

## 환경

`exam.sh start` 가 준비하는 것:

| 문항 | 네임스페이스 | 미리 만드는 것 |
|------|--------------|----------------|
| Q1 | (학생이 `gitops-tools` 생성) | Argo CD CRD 3개 (v2.13.0, 없을 때만) |
| Q2 | `streaming` | Deployment `video-api` (cpu requests 50m) |
| Q3 | `cafe` · `nginx-gateway` | **NGINX Gateway Fabric v2.7.0** (없을 때만 설치), `menu`(+`menu-svc:80`), Secret `cafe-tls`, Ingress `menu-ingress`(host `cafe.example.local` · `/`) |
| Q4 | — | cert-manager v1.16.2 CRD 6개 (CRD 만, 없을 때만) |
| Q5 | — | 멈출 워커를 고른다. **kubelet 은 Q5 에 들어갈 때 멈춘다** (`disable --now`, 설정 파일은 건드리지 않는다) |
| Q6 | `front-office` · `back-office` · `guest-zone` | `back-office/orders-api`(+Service) · `front-office/web` · `guest-zone/visitor`, `/tmp/mock9-netpol/policy-a~c.yaml` |

- 제한시간 35분. `EXAM_LIMIT_MIN=0 bash exam.sh start` 로 풀면 무제한 연습.
- **인터넷이 필요하다** — Q1 차트 · CRD, Q3 컨트롤러, Q4 CRD.
- Q1 은 Argo CD 를 실제로 설치한다 (파드 7개, 이미지 약 1GB). 채점은 릴리스 상태만 본다. 디스크가 빠듯하면 채점 뒤 `kubectl -n gitops-tools scale deployment,statefulset --all --replicas=0`.
- Q5 의 노드 제어는 mock-8 과 같은 코드다 — ssh(BatchMode + `sudo -n`)가 되면 ssh, 안 되면 특권 파드. `clean` · 마감 · 시간 초과 · 다시 `start` 때 `enable --now` 로 되살린다. ssh 가 안 되고 학생도 못 고쳤으면 손으로 칠 한 줄(`sudo systemctl enable --now kubelet`)이 화면에 나온다. 멈출 워커가 없는 클러스터에서는 Q5 를 통과 처리(15점)한다. 자세한 설명은 `mock-8/README.md`.
- Q6 은 CNI 가 NetworkPolicy 를 지원해야 한다 (Cilium · Calico).

## 정답

```bash
# Q1
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm show values argo/argo-cd --version 7.7.0 | grep -A3 '^crds:'
helm template argocd argo/argo-cd --version 7.7.0 -n gitops-tools \
  --set crds.install=false > /tmp/mock9-argocd.yaml
grep -c 'kind: CustomResourceDefinition' /tmp/mock9-argocd.yaml     # 0
helm install argocd argo/argo-cd --version 7.7.0 -n gitops-tools --create-namespace \
  --set crds.install=false

# Q2 — 명령으로 만들고 behavior 만 추가
kubectl -n streaming autoscale deployment video-api --name=video-api-scaler \
  --cpu-percent=70 --min=1 --max=5
kubectl -n streaming edit hpa video-api-scaler
#   spec:
#     behavior:
#       scaleDown:
#         stabilizationWindowSeconds: 60

# Q3 — Ingress 에서 host · secretName · path · backend 를 읽어 옮긴다
kubectl -n cafe get ingress menu-ingress -o yaml
cat <<'YAML' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: cafe-gateway
  namespace: cafe
spec:
  gatewayClassName: nginx
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: cafe.example.local
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: cafe-tls
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: cafe-route
  namespace: cafe
spec:
  parentRefs:
  - name: cafe-gateway
  hostnames:
  - cafe.example.local
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: menu-svc
      port: 80
YAML
kubectl -n cafe delete ingress menu-ingress

# Q4
kubectl get crd | grep cert-manager > /tmp/mock9-crds.txt
kubectl explain certificate.spec.privateKey > /tmp/mock9-privatekey.txt

# Q5 — 워커에 들어가서 (노드 이름은 문제에 나온다)
ssh <노드>; sudo -i
systemctl status kubelet --no-pager          # inactive (dead) · disabled
systemctl enable --now kubelet

# Q6 — policy-a: ports 가 없다(모든 포트) · policy-c: namespaceSelector: {} (모든 네임스페이스)
kubectl apply -f /tmp/mock9-netpol/policy-b.yaml
```

## 자주 틀리는 곳 (실제로 넣어 본 점수)

| 문항 | 실수 | 점수 |
|------|------|------|
| Q1 | `--skip-crds` 만 쓰고, install 에 `crds.install=false` 를 안 줌 | 5/15 |
| Q2 | `kubectl autoscale` 만 하고 behavior 를 안 넣음 | 12/15 |
| Q4 | 목록을 `-o name` 으로 전부 저장, explain 을 `certificate.spec` 까지만 | 4/15 |
| Q5 | `systemctl start kubelet` 만 함 (enable 안 함) | 10/15 |
| Q6 | policy-a 적용 (통신 확인으로는 구분이 안 된다 — 파일을 읽어야 한다) | 8/20 |
| Q6 | policy-c 적용 | 5/20 |

아무것도 하지 않고 `check` 하면 6문항 모두 0점이다.

## 검증 상태

- 2026-11-18 minikube `k8s-cilium`(v1.34.0 · Cilium · control-plane 1 + 워커 1)의 control-plane 노드 안에서 일반 사용자로 돌렸다. Helm 4.3.2.
  - 위 정답으로 **100/100**, 최종 리포트까지. 오답 점수는 위 표대로. 빈 상태 전 문항 0점.
  - Q3 은 Gateway 를 만든 직후 채점해도 만점 (데이터 플레인이 뜰 때까지 기다린다).
  - Q5: ssh 경로와 특권 파드 경로 둘 다. 고친 뒤 15점, 못 고친 채 `clean` 하면 ssh 로 되살아난다.
  - `clean` 뒤 네임스페이스 · CRD · helm 저장소 · /tmp 파일이 남지 않는다.
- **VirtualBox 클러스터에서는 아직 돌려 보지 않았다.** 볼 것은 mock-8 과 같다 — start 화면의 "Q5 … 준비 방법", Q3 의 HTTPS 트래픽 항목, Argo CD 이미지를 받는 동안의 디스크 여유.
