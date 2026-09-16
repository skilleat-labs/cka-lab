# NetworkPolicy — 파드 사이의 방화벽

> CKA 도메인: Services & Networking (20%) · 출제 빈도 ★★★ (거의 매 시험)
> 예제 YAML 은 `docs/networkpolicy-examples/` 에 파일로 있다. 바로 `kubectl apply -f` 할 수 있다.

---

## 1. 한 줄 정의

**NetworkPolicy 는 "어떤 파드가 어떤 파드와 통신할 수 있는가"를 레이블로 정하는 규칙이다.**

쿠버네티스는 기본적으로 **모든 파드가 모든 파드와 통신할 수 있다.** 네임스페이스가 달라도, 노드가 달라도 막히는 게 없다. NetworkPolicy 는 이 "전부 열림" 상태에 벽을 세운다.

```
  [기본 상태 — 전부 열림]              [NetworkPolicy 적용 후]

   frontend ──────► backend             frontend ──────► backend
      │                │                                    │
      │                ▼                                    ▼
      └──────────────► db               frontend ──X──►    db
                                                   (차단)
   누구나 db 에 접근 가능              backend 만 db 에 접근 가능
```

---

## 2. 아키텍처 — 누가 실제로 막는가

여기가 가장 많이 오해하는 부분이다. **NetworkPolicy 리소스 자체는 아무것도 막지 않는다.** 그냥 API 서버에 저장된 "규칙 선언"일 뿐이다. 실제로 패킷을 막는 건 **CNI 플러그인**이다.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Control Plane                                                      │
│                                                                     │
│   kubectl apply -f policy.yaml                                      │
│          │                                                          │
│          ▼                                                          │
│   ┌──────────────┐        ┌──────────┐                              │
│   │ kube-apiserver│ ─────► │   etcd   │   NetworkPolicy 오브젝트 저장   │
│   └──────┬───────┘        └──────────┘                              │
│          │  watch (변경 감지)                                         │
└──────────┼──────────────────────────────────────────────────────────┘
           │
           │  "policy 가 바뀌었다" 이벤트를 모든 노드의 CNI 에이전트가 받음
           │
   ┌───────┴───────────────┬───────────────────────┐
   ▼                       ▼                       ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ worker-1         │  │ worker-2         │  │ control-plane    │
│                  │  │                  │  │                  │
│ ┌──────────────┐ │  │ ┌──────────────┐ │  │ ┌──────────────┐ │
│ │ calico-node  │ │  │ │ calico-node  │ │  │ │ calico-node  │ │
│ │ (DaemonSet)  │ │  │ │ (DaemonSet)  │ │  │ │ (DaemonSet)  │ │
│ └──────┬───────┘ │  │ └──────┬───────┘ │  │ └──────┬───────┘ │
│        │ 규칙을   │  │        │         │  │        │         │
│        ▼ 번역     │  │        ▼         │  │        ▼         │
│ ┌──────────────┐ │  │ ┌──────────────┐ │  │ ┌──────────────┐ │
│ │ iptables /   │ │  │ │ iptables /   │ │  │ │ iptables /   │ │
│ │ eBPF 규칙    │ │  │ │ eBPF 규칙    │ │  │ │ eBPF 규칙    │ │
│ └──────┬───────┘ │  │ └──────┬───────┘ │  │ └──────┬───────┘ │
│        │         │  │        │         │  │        │         │
│   ┌────┴────┐    │  │   ┌────┴────┐    │  │        │         │
│   │ pod A   │    │  │   │ pod C   │    │  │  (파드 없음)      │
│   │ pod B   │    │  │   │ pod D   │    │  │                  │
│   └─────────┘    │  │   └─────────┘    │  │                  │
└──────────────────┘  └──────────────────┘  └──────────────────┘

  패킷이 파드로 들어오거나 나갈 때, 그 노드의 커널(iptables/eBPF)이
  CNI 가 넣어둔 규칙으로 허용/차단을 결정한다.
```

**흐름 정리**

1. `kubectl apply` → API 서버가 NetworkPolicy 오브젝트를 etcd 에 저장
2. 각 노드의 CNI 에이전트(Calico 는 `calico-node` DaemonSet)가 API 서버를 watch 하다가 변경을 감지
3. 에이전트가 정책을 **자기 노드의 iptables 또는 eBPF 규칙으로 번역**해서 커널에 넣음
4. 이후 파드로 오가는 모든 패킷은 커널 레벨에서 검사됨 — 쿠버네티스 컴포넌트를 거치지 않는다

**핵심 결론 두 가지**

| | 의미 |
|---|---|
| **CNI 가 NetworkPolicy 를 지원해야 한다** | Calico, Cilium, Weave, Antrea 는 지원. **Flannel 은 미지원** — 정책을 만들어도 조용히 무시된다 |
| **차단은 커널에서 일어난다** | apiserver 나 kube-proxy 가 죽어도 이미 적용된 정책은 계속 동작한다 |

이 클러스터의 CNI 확인:

```bash
kubectl get pods -n kube-system | grep -E 'calico|cilium|flannel|weave'
```

---

## 3. 동작 원칙 — 이 다섯 가지를 외우면 끝

### 원칙 1. 정책에 "선택된" 파드만 제한받는다

NetworkPolicy 의 `podSelector` 가 가리키는 파드만 영향을 받는다. 선택되지 않은 파드는 여전히 전부 열려 있다.

```
  namespace: prod

  ┌─────────────────────────────────────────────────┐
  │                                                 │
  │   NetworkPolicy "db-policy"                     │
  │   podSelector: app=db                           │
  │         │                                       │
  │         ▼ 이 파드만 제한됨                        │
  │   ┌──────────┐                                  │
  │   │  app=db  │ ◄── 규칙에 맞는 트래픽만 통과       │
  │   └──────────┘                                  │
  │                                                 │
  │   ┌──────────┐    ┌──────────┐                  │
  │   │ app=web  │    │ app=api  │  ◄── 정책 없음    │
  │   └──────────┘    └──────────┘      = 전부 열림   │
  │                                                 │
  └─────────────────────────────────────────────────┘
```

### 원칙 2. 선택되는 순간 "기본 거부"로 바뀐다

파드가 어떤 정책에든 선택되면, **그 방향(Ingress 또는 Egress)은 정책에 명시된 것만 허용**되고 나머지는 전부 막힌다. 화이트리스트 방식이다.

```
  정책 없음:         [모든 트래픽 허용]
  정책 1개 이상:     [정책에 적힌 것만 허용, 나머지 거부]
```

### 원칙 3. 여러 정책은 합집합(OR)이다

같은 파드를 선택하는 정책이 여러 개면 **허용 목록이 합쳐진다.** "정책 A 에서 허용 OR 정책 B 에서 허용"이면 통과. 정책끼리 충돌 개념이 없다 — 하나라도 허용하면 통과.

```
  정책 A: app=web 에서 오는 것 허용     ┐
                                        ├──► app=db 는 web 과 api 둘 다 받음
  정책 B: app=api 에서 오는 것 허용     ┘
```

### 원칙 4. Ingress 와 Egress 는 독립이다

`policyTypes` 로 어느 방향을 제어할지 정한다.

```
                       ┌──────────┐
    Ingress (들어옴)    │          │    Egress (나감)
   ─────────────────►  │   pod    │  ─────────────────►
                       │          │
                       └──────────┘

  policyTypes: [Ingress]          → 들어오는 것만 제한, 나가는 건 자유
  policyTypes: [Egress]           → 나가는 것만 제한, 들어오는 건 자유
  policyTypes: [Ingress, Egress]  → 양쪽 다 제한
```

`policyTypes` 를 생략하면: `ingress` 필드가 있으면 Ingress 포함, `egress` 필드가 있으면 Egress 포함. **명시하는 습관을 들이는 게 안전하다.**

### 원칙 5. 연결은 양쪽이 다 허용해야 성립한다

A → B 통신이 되려면 **A 의 Egress 가 B 를 허용**하고 **B 의 Ingress 가 A 를 허용**해야 한다. 한쪽만 열면 안 된다.

```
       A (Egress 정책 있음)              B (Ingress 정책 있음)
   ┌──────────────┐                  ┌──────────────┐
   │  egress:     │                  │  ingress:    │
   │   to: B  ✓   │ ───────────────► │   from: A ✓  │  → 통과
   └──────────────┘                  └──────────────┘

   ┌──────────────┐                  ┌──────────────┐
   │  egress:     │                  │  ingress:    │
   │   to: B  ✓   │ ───────X───────► │   from: C    │  → B 가 A 를 안 받음 → 차단
   └──────────────┘                  └──────────────┘
```

응답 패킷은 자동으로 허용된다(stateful). 요청만 허용하면 응답까지 따로 열 필요 없다.

---

## 4. 셀렉터 3종 — 누구를 허용할 것인가

`from`(Ingress) 또는 `to`(Egress) 아래에 세 가지를 쓸 수 있다.

| 셀렉터 | 선택 대상 | 예 |
|---|---|---|
| `podSelector` | **같은 네임스페이스**의 파드 (레이블로) | `app=web` 인 파드 |
| `namespaceSelector` | 다른 네임스페이스의 **모든** 파드 (네임스페이스 레이블로) | `team=frontend` 네임스페이스의 전부 |
| `ipBlock` | CIDR 대역 (클러스터 밖 포함) | `10.0.0.0/8`, 단 `10.0.1.0/24` 제외 |

### AND 와 OR — 시험에서 가장 많이 틀리는 지점

`from` 아래 **한 항목(`-`) 안에** `podSelector` 와 `namespaceSelector` 를 같이 쓰면 **AND**. **별도 항목(`-`)** 으로 나누면 **OR**.

```yaml
# ── AND: "team=frontend 네임스페이스의 파드 중에서 app=web 인 것만"
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        team: frontend
    podSelector:                  # ← 같은 항목 안 (앞에 '-' 없음)
      matchLabels:
        app: web

# ── OR: "team=frontend 네임스페이스의 모든 파드" 또는 "같은 ns 의 app=web 파드"
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        team: frontend
  - podSelector:                  # ← 별도 항목 (앞에 '-' 있음)
      matchLabels:
        app: web
```

```
  AND (한 항목)                          OR (두 항목)

  namespace=frontend                    namespace=frontend  ──┐
        ∩                                                     ├──► 허용
  app=web                               app=web (같은 ns)  ───┘
        ↓
  둘 다 만족하는 파드만 허용              둘 중 하나만 만족해도 허용
```

**하이픈 하나 차이로 의미가 완전히 바뀐다.** YAML 을 쓸 때 들여쓰기와 `-` 위치를 확인하는 습관이 필요하다.

### 빈 셀렉터의 의미

| 표현 | 의미 |
|---|---|
| `podSelector: {}` | **모든 파드** (네임스페이스 안 전체) |
| `namespaceSelector: {}` | **모든 네임스페이스** |
| `from: []` 또는 `from` 생략 | **아무것도 허용 안 함** (= 전부 차단) |
| `ingress: []` | Ingress 전부 차단 |
| `ingress: - {}` | Ingress 전부 **허용** (빈 규칙 = 모두 매칭) |

`[]` 와 `- {}` 는 정반대다. 헷갈리기 쉽다.

### namespaceSelector 는 네임스페이스에 레이블이 있어야 한다

네임스페이스에는 기본으로 `kubernetes.io/metadata.name=<이름>` 레이블이 자동으로 붙어 있다(v1.21+). 이걸 쓰면 별도 레이블 없이 이름으로 고를 수 있다.

```yaml
namespaceSelector:
  matchLabels:
    kubernetes.io/metadata.name: monitoring
```

직접 레이블을 붙이려면:

```bash
kubectl label namespace frontend team=frontend
```

---

## 5. 시나리오 — 3계층 앱 격리

가장 전형적인 출제 형태다. 이 그림을 그릴 수 있으면 대부분의 문제를 풀 수 있다.

```
  namespace: prod

  ┌────────────┐        ┌────────────┐        ┌────────────┐
  │  frontend  │ ─────► │  backend   │ ─────► │     db     │
  │  app=web   │  :8080 │  app=api   │  :3306 │  app=db    │
  └────────────┘        └────────────┘        └────────────┘
        ▲                                            ▲
        │ :80                                        │
   [Ingress 컨트롤러                             X ──┘
    또는 외부]                               frontend 가 db 로
                                              직접 가는 건 차단

  목표
    · frontend  ← 외부(모든 곳)에서 80 으로만 들어올 수 있음
    · backend   ← frontend 에서 8080 으로만
    · db        ← backend 에서 3306 으로만
    · 그 외 모든 인바운드는 차단
```

이걸 구현하는 정책 3개:

```yaml
# 1) db 는 backend 에서만
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-allow-backend
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api
    ports:
    - protocol: TCP
      port: 3306
---
# 2) backend 는 frontend 에서만
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-frontend
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 8080
---
# 3) frontend 는 어디서든 80 으로
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-allow-all-80
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes: [Ingress]
  ingress:
  - ports:
    - protocol: TCP
      port: 80
```

세 번째 정책은 `from` 이 없다. **`from` 을 생략하면 "출발지 무관"** 이고, `ports` 만 있으니 "80 포트로 오는 건 누구든 허용"이 된다.

---

## 6. 예제 YAML 모음

전부 `docs/networkpolicy-examples/` 에 파일로 있다.

### 6-1. 기본 거부 — 네임스페이스 전체 Ingress 차단

가장 먼저 배우고 가장 자주 나온다. 이걸 깔고 나서 필요한 것만 여는 게 정석이다.

```yaml
# 01-default-deny-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: prod
spec:
  podSelector: {}          # 네임스페이스의 모든 파드
  policyTypes:
  - Ingress
  # ingress 필드 자체가 없음 → 허용 목록이 비어 있음 → 전부 차단
```

### 6-2. 기본 거부 — Ingress + Egress 둘 다

```yaml
# 02-default-deny-all.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: prod
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

**주의**: Egress 를 전부 막으면 **DNS 도 막힌다.** 파드가 서비스 이름을 못 찾게 된다. 6-6 을 같이 적용해야 한다.

### 6-3. 특정 파드에서만 허용 (podSelector)

```yaml
# 03-allow-from-pod.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-allow-backend
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api
    ports:
    - protocol: TCP
      port: 3306
```

### 6-4. 특정 네임스페이스에서 허용 (namespaceSelector)

```yaml
# 04-allow-from-namespace.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-monitoring
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    ports:
    - protocol: TCP
      port: 9090
```

### 6-5. AND 조건 — 특정 네임스페이스의 특정 파드만

```yaml
# 05-allow-namespace-and-pod.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-ns-web-only
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          team: frontend
      podSelector:               # 같은 항목 → AND
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 8080
```

### 6-6. Egress — DNS 는 열고 특정 대상만 허용

Egress 정책을 쓸 때 **반드시 같이 넣어야 하는 패턴**이다.

```yaml
# 06-egress-allow-dns-and-db.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-egress
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Egress
  egress:
  # (1) DNS — kube-system 의 CoreDNS 로 53 포트
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  # (2) db 파드로 3306
  - to:
    - podSelector:
        matchLabels:
          app: db
    ports:
    - protocol: TCP
      port: 3306
```

### 6-7. ipBlock — CIDR 대역 허용, 일부 제외

```yaml
# 07-ipblock.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-office
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 192.168.56.0/24
        except:
        - 192.168.56.100/32
    ports:
    - protocol: TCP
      port: 80
```

`ipBlock` 은 주로 **클러스터 밖** IP 용이다. 파드 IP 를 ipBlock 으로 잡는 건 CNI 에 따라 동작이 다르니 파드는 podSelector 로 고른다.

### 6-8. 전부 허용 (기본 거부를 특정 파드만 해제)

```yaml
# 08-allow-all-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-all
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - {}                         # 빈 규칙 = 모든 출발지, 모든 포트 허용
```

---

## 7. 검증 방법

정책이 "있다"와 "동작한다"는 다르다. 실제로 트래픽을 쏴봐야 안다.

```bash
# 1) 정책 확인
kubectl get networkpolicy -n prod
kubectl describe networkpolicy db-allow-backend -n prod

# 2) 어떤 파드가 선택됐는지 — describe 의 PodSelector 와 파드 레이블 대조
kubectl get pods -n prod --show-labels

# 3) 실제 통신 테스트 — 허용돼야 하는 경로
kubectl run test-api -n prod --rm -it --image=busybox:1.36 --restart=Never \
  --labels="app=api" -- wget -qO- --timeout=3 http://db-svc:3306

# 4) 차단돼야 하는 경로 — timeout 이 나야 정상
kubectl run test-web -n prod --rm -it --image=busybox:1.36 --restart=Never \
  --labels="app=web" -- wget -qO- --timeout=3 http://db-svc:3306
```

차단된 연결은 **거부(reject)가 아니라 드롭(drop)** 이다. 즉시 에러가 아니라 timeout 으로 나타난다. `--timeout=3` 을 안 주면 한참 기다린다.

**테스트 파드의 레이블이 중요하다.** `--labels` 로 정책이 허용하는 레이블을 붙여야 "허용 경로" 테스트가 되고, 다른 레이블이면 "차단 경로" 테스트가 된다.

---

## 8. CKA 에서 걸리는 지점

| 함정 | 설명 |
|---|---|
| **CNI 가 지원 안 함** | Flannel 클러스터에서 정책을 만들어도 아무 일도 안 일어난다. 시험 환경은 지원하지만, 랩에서 "안 막히는데요?"의 1순위 원인 |
| **AND / OR 하이픈** | `- namespaceSelector` 아래 `podSelector` 를 같은 항목에 두면 AND, `-` 를 붙이면 OR. 문제가 "A 네임스페이스의 B 파드에서만"이면 AND |
| **Egress 막으면 DNS 죽음** | `policyTypes: [Egress]` 를 쓰는 순간 53 포트를 열어주지 않으면 서비스 이름 해석이 안 된다 |
| **port 는 파드 포트** | 정책의 `port` 는 Service 의 port 가 아니라 **파드 컨테이너가 듣는 포트**(targetPort)다. Service 가 80→8080 이면 정책엔 8080 |
| **`[]` vs `- {}`** | `ingress: []` 는 전부 차단, `ingress: - {}` 는 전부 허용. 정반대 |
| **policyTypes 생략** | `egress` 필드를 안 썼는데 `policyTypes: [Egress]` 를 넣으면 Egress 전부 차단. 반대로 `egress` 를 썼는데 policyTypes 에 Egress 가 없으면 무시됨 |
| **네임스페이스 스코프** | NetworkPolicy 는 네임스페이스 리소스다. `-n` 을 빼먹으면 default 에 만들어져서 대상 파드를 못 찾는다 |
| **응답은 자동 허용** | 요청 방향만 열면 된다. "응답도 열어야 하나?" 고민할 필요 없다 |

### 시험에서 빠르게 쓰는 법

NetworkPolicy 는 `kubectl create` 명령이 없다. YAML 을 써야 한다. 공식 문서의 예제를 복사해서 고치는 게 가장 빠르다:

```
kubernetes.io/docs/concepts/services-networking/network-policies/
```

시험 중 이 페이지를 북마크해두고, "NetworkPolicy resource" 섹션의 전체 예제(podSelector + namespaceSelector + ipBlock + egress 가 다 들어 있음)를 복사한 뒤 필요 없는 부분을 지우는 방식이 빠르다.

---

## 9. 이 저장소의 관련 실습

| 세트 | 문제 | 내용 |
|---|---|---|
| `06-networking` | P3 | `backend-policy` — frontend 에서만 backend 로 |
| `07-ingress` | P4 | `production` 네임스페이스 격리 |
| `mock-2` | Q3 | `deny-all` + `allow-web` (3306 만) |

예제 YAML 로 직접 실험해보려면:

```bash
kubectl create namespace prod
kubectl apply -f docs/networkpolicy-examples/01-default-deny-ingress.yaml
kubectl apply -f docs/networkpolicy-examples/03-allow-from-pod.yaml
kubectl describe networkpolicy -n prod
```
