# CKA 2세션 시험 — 문제지

**권장 제한 시간 25분 · 총 30항목**

문제를 풀기 전에 아래를 실행해 환경을 준비한다.

```bash
bash exam-start.sh
```

다 풀었으면 채점한다.

```bash
bash verify.sh
```

> 출제 범위: 네임스페이스 지정 · Service NodePort · ConfigMap · Deployment 롤아웃/롤백
> 문제 형식은 실제 CKA 기출 스타일(`In namespace <ns>, create ...`)을 따랐다.

---

## E1. 네임스페이스를 지정해 Deployment 와 NodePort Service 만들기

Create a namespace named **`ops`**.

In the `ops` namespace, create a Deployment named **`cache-app`** using image **`nginx:1.24`** with **2** replicas, exposing container port **80**.

Then expose it with a **NodePort** Service named **`cache-svc`** on port **80** → targetPort **80**, using nodePort **30090**.

**조건**

- namespace: `ops` (직접 생성)
- Deployment: `cache-app` / `nginx:1.24` / replicas 2 / containerPort 80
- Service: `cache-svc` / NodePort / 80 → 80 / nodePort **30090** (반드시 이 값)
- 모든 리소스는 `default` 가 아니라 **`ops`** 네임스페이스에 있어야 한다

**확인용 명령**

```bash
kubectl get deployment,svc -n ops
kubectl get endpoints cache-svc -n ops
curl http://<NodeIP>:30090
```

---

## E2. ConfigMap 을 파드에 두 가지 방식으로 주입

Create a namespace named **`app`**.

In the `app` namespace, create a ConfigMap named **`app-config`** with keys **`APP_ENV=production`** and **`LOG_LEVEL=info`**.

Then create a Pod named **`config-pod`** (image **`busybox:1.36`**, command **`sleep 3600`**) that consumes the ConfigMap in **both** ways:

- (a) all keys injected as environment variables
- (b) the same ConfigMap mounted as a volume at **`/etc/app-config`**

**조건**

- namespace: `app` (직접 생성)
- ConfigMap: `app-config` / `APP_ENV=production` / `LOG_LEVEL=info`
- Pod: `config-pod` / `busybox:1.36` / `sleep 3600`
- 주입 방식 2가지: `envFrom` 전체 주입 **+** 볼륨 마운트 `/etc/app-config`

**확인용 명령**

```bash
kubectl exec config-pod -n app -- env | grep -E 'APP_ENV|LOG_LEVEL'
kubectl exec config-pod -n app -- cat /etc/app-config/LOG_LEVEL
```

> 볼륨으로 마운트하면 키 이름이 파일명, 값이 파일 내용이 된다.

---

## E3. Deployment 스케일 · 롤링 업데이트 · 롤백

In the `app` namespace, create a Deployment named **`frontend`** using image **`nginx:1.24`** with **2** replicas.

Then perform the following operations in order:

- (a) scale the Deployment to **4** replicas
- (b) perform a rolling update to image **`nginx:1.25`** and wait until it completes
- (c) **roll back** to the previous revision

After the rollback, the Deployment must be running **`nginx:1.24`** with **4** replicas.

**조건**

- namespace: `app` (E2 에서 만든 것 재사용)
- Deployment: `frontend` / 최초 `nginx:1.24` / replicas 2
- (a) replicas 4 로 스케일 → (b) `nginx:1.25` 로 롤링 업데이트 → (c) 롤백
- 최종 상태: 이미지 `nginx:1.24` / replicas 4 / 전부 Ready
- 세 단계를 실제로 거쳐야 한다 — 처음부터 `nginx:1.24` 로 두고 스케일만 하면 오답

**확인용 명령**

```bash
kubectl get deployment frontend -n app
kubectl rollout history deployment/frontend -n app
kubectl get rs -n app
```

> 롤백은 이전 ReplicaSet 을 다시 살리는 동작이다. 업데이트 후에도 예전 RS 가 replicas 0 인 채로 남아 있고, 그게 롤백의 재료다.

---

## 채점 배분

| 문제 | 항목 수 |
|------|--------|
| E1 네임스페이스 + NodePort | 13 |
| E2 ConfigMap (env + volume) | 10 |
| E3 Deployment 롤아웃·롤백 | 7 |
| **합계** | **30** |

막히면 `bash exam-start.sh --hints` 로 힌트를 볼 수 있다. **시험 중에는 사용하지 않는다.**
