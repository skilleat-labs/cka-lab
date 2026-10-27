# Mock Exam 7 — 스토리지 · NetworkPolicy · Gateway API · 자원 · 우선순위 (강사용)

> **문제만 보려면 `QUESTIONS.txt`.** 이 파일에는 정답이 들어 있다.
>
> **한 문제씩 풀기:** `bash exam.sh start` → 풀고 → `bash exam.sh check`. 끝나면 `bash exam.sh clean`.

## 목적

리소스를 "만들었는지" 가 아니라 **실제로 돌아가는지** 를 보는 5문제. 모든 문항이 마지막에 실제 동작(마운트 · 통신 · 라우팅 · 파드 생성 · 선점)으로 채점된다.

| 문항 | 주제 | 출제영역 | 함정 |
|------|------|----------|------|
| Q1 | StorageClass 로 PVC → 기존 Deployment 에 마운트 | Storage | `WaitForFirstConsumer` 라 마운트 전에는 Pending 이 정상. 미끼 클래스 `media-archive` |
| Q2 | NetworkPolicy — 네임스페이스 **AND** 파드 | Services & Networking | `from` 항목을 둘로 나누면 OR. 이미 있는 `legacy-open`(`ingress: [{}]`)이 전부 열어 둔다 — 정책은 더해진다 |
| Q3 | Gateway API — 호스트 + 경로 라우팅 | Services & Networking | 컨트롤러가 만든 Service 의 nodePort 를 직접 찾아 확인해야 한다 |
| Q4 | ResourceQuota 에 막혀 파드 0개인 Deployment 에 requests/limits | Workloads & Scheduling | 컨테이너가 **두 개** — `app` 만 넣으면 계속 FailedCreate. 원인은 `describe rs` 에 있다 |
| Q5 | PriorityClass 로 Pending 파드를 선점으로 밀어 넣기 | Workloads & Scheduling | `spec` 이 아니라 `spec.template.spec`. trainer 를 줄이거나 지우면 오답 |

## 환경

`exam.sh start` 가 준비하는 것:

| 문항 | 네임스페이스 | 미리 만드는 것 |
|------|--------------|----------------|
| Q1 | `media` | StorageClass `media-store`(WaitForFirstConsumer) · `media-archive`(미끼), PV `media-pv-1`(1Gi) · `media-pv-2`(2Gi) · `archive-pv-1`, Deployment `media-web`(볼륨 없음) |
| Q2 | `orders` · `web-team`(team=web) · `qa-team`(team=qa) | `api` Deployment+Service, 정책 `legacy-open`, 테스트 파드 `orders/monitor` · `web-team/frontend` · `web-team/batch` · `qa-team/frontend` |
| Q3 | `portal` · `nginx-gateway` | **NGINX Gateway Fabric v2.7.0** (없을 때만 설치, GatewayClass `nginx`), 백엔드 `portal-main` · `portal-api` (경로와 상관없이 자기 이름을 돌려준다) |
| Q4 | `batch` | ResourceQuota `batch-quota`(requests 500m/512Mi · limits 1/1Gi · pods 5), Deployment `worker`(컨테이너 `app` · `log-agent`, 자원 설정 없음 → 파드 0개) |
| Q5 | `ml` | 노드 하나에 확장 리소스 `example.com/accelerator: 2`, PriorityClass `ml-batch`(100), `trainer`(2개, 장치 2개 다 씀) · `inference`(Pending) |

- 제한시간 40분. `EXAM_LIMIT_MIN=0 bash exam.sh start` 로 풀면 무제한 연습.
- **Q3 는 인터넷이 필요하다.** 08-ingress · tutoring/session-3 과 같은 컨트롤러·버전이라 그 세트를 돌린 클러스터면 설치를 건너뛴다. 설치가 실패하면 Q3 는 0점 처리되고 다시 `start` 하라고 안내한다. `clean` 은 컨트롤러를 남겨 둔다 (완전 제거: `kubectl delete ns nginx-gateway`).
- Q5 의 장치는 진짜 GPU 가 아니라 노드 status 에 붙인 **확장 리소스**다. 실제 CPU·메모리를 잡지 않으므로 메모리가 빠듯한 VM 에서도 돈다. 장치를 붙일 노드는 taint 없는 Ready 노드 중 첫 번째, 없으면(단일 노드) 아무 Ready 노드. `clean` 이 노드에서 지운다.
- Q1 의 hostPath 경로는 start 할 때마다 바뀐다 (`/mnt/mock7-media-<시각>-N`). 지난 시도의 index.html 로 통과하지 않게.
- Q2 는 CNI 가 NetworkPolicy 를 지원해야 한다 (Cilium · Calico 면 된다. Flannel 은 안 된다).

## 정답

```bash
# Q1 — PVC 를 만들면 Pending (WaitForFirstConsumer). 파드가 쓰면 Bound
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: media-data, namespace: media }
spec:
  storageClassName: media-store
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
YAML
kubectl -n media patch deployment media-web -p '{"spec":{"template":{"spec":{
  "volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"media-data"}}],
  "containers":[{"name":"web","volumeMounts":[{"name":"data","mountPath":"/usr/share/nginx/html"}]}]}}}}'
kubectl -n media rollout status deployment media-web
kubectl -n media exec deploy/media-web -c web -- sh -c 'echo media-ok > /usr/share/nginx/html/index.html'
kubectl -n media get pvc media-data          # Bound · media-pv-1

# Q2 — 한 from 항목 안에 namespaceSelector + podSelector (AND), legacy-open 삭제
cat <<'YAML' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: api-allow-frontend, namespace: orders }
spec:
  podSelector: { matchLabels: { app: api } }
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: { matchLabels: { team: web } }
          podSelector: { matchLabels: { app: frontend } }
      ports: [ { protocol: TCP, port: 80 } ]
YAML
kubectl -n orders delete networkpolicy legacy-open

# Q3
cat <<'YAML' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: portal-gw, namespace: portal }
spec:
  gatewayClassName: nginx
  listeners:
    - { name: http, port: 80, protocol: HTTP }
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: portal-route, namespace: portal }
spec:
  parentRefs: [ { name: portal-gw } ]
  hostnames: [ portal.example.local ]
  rules:
    - matches: [ { path: { type: PathPrefix, value: /api } } ]
      backendRefs: [ { name: portal-api, port: 80 } ]
    - matches: [ { path: { type: PathPrefix, value: / } } ]
      backendRefs: [ { name: portal-main, port: 80 } ]
YAML
kubectl -n portal get svc                        # portal-gw-nginx  80:3xxxx/TCP
curl -H 'Host: portal.example.local' http://<NodeIP>:3xxxx/api/orders   # portal-api /api/orders

# Q4 — 원인: describe rs → "must specify limits.cpu for: app,log-agent"
kubectl -n batch set resources deployment worker -c app \
  --requests=cpu=100m,memory=128Mi --limits=cpu=200m,memory=256Mi
kubectl -n batch set resources deployment worker -c log-agent \
  --requests=cpu=50m,memory=32Mi --limits=cpu=100m,memory=64Mi
kubectl -n batch rollout status deployment worker
kubectl -n batch describe resourcequota batch-quota     # used 450m / 480Mi

# Q5
cat <<'YAML' | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: inference-critical }
value: 1000000
preemptionPolicy: PreemptLowerPriority
globalDefault: false
description: "latency-sensitive inference"
YAML
kubectl -n ml patch deployment inference \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"inference-critical"}}}}'
kubectl -n ml get pods -o wide     # inference Running, trainer Running 1 · Pending 1
```

## 자주 틀리는 곳

| 문항 | 실수 | 채점에서 보이는 것 |
|------|------|-------------------|
| Q1 | PVC 가 Pending 이라 PV 를 직접 만들거나 volumeName 을 적음 | 지문 위반. 만든 PV 이름이 `media-pv-*` 가 아니면 Bound 항목 FAIL |
| Q1 | storageClassName 을 빼먹음 | 기본 클래스가 없으면 영영 Pending, 있으면 다른 클래스 → FAIL |
| Q1 | Deployment 를 지우고 YAML 로 다시 만듦 | "지우고 다시 만들지 않았다" FAIL (uid 비교) |
| Q1 | 마운트 전에 index.html 을 씀 | 컨테이너 파일시스템에 썼다가 롤아웃으로 사라진다 → 내용 FAIL |
| Q2 | `- namespaceSelector` / `- podSelector` 로 항목을 나눔 (OR) | AND 구조 FAIL, web-team/batch 가 닿는다 |
| Q2 | legacy-open 을 그대로 둠 | batch · qa · monitor 차단 3개 모두 FAIL — 정책은 더해진다 |
| Q3 | hostnames 를 뺌 | 다른 Host 도 portal 로 가서 1점 FAIL |
| Q3 | `/` 규칙을 위에 둬서 /api 가 안 될까 걱정 | 괜찮다 — 더 긴 접두사가 이긴다 |
| Q4 | app 에만 자원을 넣음 | 계속 FailedCreate → 파드 0개 |
| Q4 | 쿼터를 늘리거나 지움 | "쿼터 그대로" FAIL |
| Q5 | `spec.priorityClassName` 에 넣으려 함 | Deployment 에는 그런 필드가 없다 — 템플릿 항목 FAIL |
| Q5 | trainer 를 1 로 줄이거나 파드를 지움 | "trainer 그대로" · "Running 1 · Pending 1" FAIL |

## 검증 상태

- 문법(`bash -n`)과 배점 합계(문항당 20점)는 확인했다.
- 2026-10-27 minikube `k8s-cilium`(v1.34.0 · Cilium · **단일 노드**)에서 start → 풀이 → check → clean → 두 번째 start → clean 을 돌렸다. 위 정답으로 **100/100**.
  - 함정 답도 넣어 봤다: Q2 OR 구조 10점 · legacy-open 남김 12점 / Q4 app 에만 자원 7점. 의도대로 깎인다.
  - Q3 컨트롤러 설치(NGF v2.7.0) · 두 번째 start 의 "이미 설치됨" 건너뛰기 · Q5 선점 이벤트(`Preempted`) 확인.
  - clean 뒤 네임스페이스 · PV · SC · PriorityClass · 노드 확장 리소스가 모두 사라진다.
- Q3 트래픽 항목은 **노드 IP 로 curl 이 되는 곳에서** 돌려야 한다. VirtualBox 클러스터처럼 control-plane 에서 실행하면 된다 (Mac + docker 드라이버 minikube 에서는 노드 IP 가 안 닿아 트래픽 3항목이 FAIL — 노드 안에서 돌리면 통과).
- **워커가 2대인 VM 클러스터에서는 아직 돌려 보지 않았다.** Q5 는 taint 없는 첫 Ready 노드에 장치를 붙인다.
