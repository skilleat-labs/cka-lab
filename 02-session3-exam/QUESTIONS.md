# CKA 3세션 시험 — 문제지

**제한 시간 35분 · 총 32항목**

문제를 풀기 전에 아래를 실행해 환경을 준비한다.

```bash
bash exam-start.sh
```

다 풀었으면 채점한다.

```bash
bash verify.sh
```

---

## 이미 준비되어 있는 것

문제를 풀기 위해 따로 설치하거나 만들 필요가 없다.

| 항목 | 내용 |
|------|------|
| 네임스페이스 | `shop` |
| StorageClass | `exam-storage` |
| PersistentVolume | 2Gi 짜리 3개 (`exam-pv-1~3`) |
| GatewayClass | `nginx` (NGINX Gateway Fabric) |

---

## Q1. Deployment 를 만들고 Service 로 연결

In the `shop` namespace, create a Deployment named **`shop-web`** using image **`nginx:1.24`** with **2** replicas, exposing container port **80**.

Expose it with a **ClusterIP** Service named **`shop-svc`** on port **80** → targetPort **80**.

The Service must actually route traffic to both pods.

**조건**

- namespace: `shop`
- Deployment: `shop-web` / `nginx:1.24` / replicas 2 / containerPort 80
- Service: `shop-svc` / ClusterIP / 80 → 80
- Endpoints 에 파드 IP 2개가 등록되어야 한다

**확인용 명령**

```bash
kubectl get deployment,svc,endpoints -n shop
kubectl run tmp -n shop --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://shop-svc
```

---

## Q2. 주어진 StorageClass 로 PVC 를 만들어 Deployment 에 연결

A StorageClass named **`exam-storage`** already exists in the cluster.

In the `shop` namespace, create a PersistentVolumeClaim named **`shop-data`** that requests **1Gi** with access mode **ReadWriteOnce** using that StorageClass.

Then mount it into the **`shop-web`** Deployment at **`/data`**.

The PVC must reach **Bound** state and the pods must be running with the volume mounted.

**조건**

- PVC: `shop-data` / storageClassName `exam-storage` / 1Gi / ReadWriteOnce
- `shop-web` Deployment 에 마운트 — mountPath `/data`
- PVC 상태가 `Bound` 여야 하고, 파드가 정상 기동해야 한다
- 주의: `/usr/share/nginx/html` 이 아니라 `/data` 에 마운트할 것

**확인용 명령**

```bash
kubectl get sc,pv,pvc -n shop
kubectl describe pvc shop-data -n shop
kubectl exec -n shop deploy/shop-web -- df -h /data
```

---

## Q3. Gateway API 로 외부에 노출

The GatewayClass **`nginx`** is already installed in the cluster.

In the `shop` namespace, create a Gateway named **`shop-gw`** using that GatewayClass, with a listener named **`http`** on port **80** (protocol HTTP).

Create an HTTPRoute named **`shop-route`** attached to that Gateway, routing all traffic (path prefix **`/`**) to the **`shop-svc`** Service on port **80**.

Finally, expose the Gateway outside the cluster on **nodePort 30081** so that `curl http://<NodeIP>:30081` returns the nginx page.

**조건**

- Gateway: `shop-gw` / gatewayClassName `nginx` / listener `http` · port 80 · HTTP
- HTTPRoute: `shop-route` / parentRef `shop-gw` / backendRef `shop-svc`:80
- 외부 노출: Gateway 가 만든 Service 를 nodePort **30081** 로 변경
- 힌트: Gateway 를 만들면 컨트롤러가 `shop` 네임스페이스에 Service 를 자동 생성한다. `kubectl get svc -n shop` 으로 찾는다.

**확인용 명령**

```bash
kubectl get gateway,httproute -n shop
kubectl describe gateway shop-gw -n shop
kubectl get svc -n shop
curl http://<NodeIP>:30081
```

---

## 채점 배분

| 문제 | 항목 수 |
|------|--------|
| Q1 Deployment + Service | 11 |
| Q2 StorageClass + PVC | 9 |
| Q3 Gateway API | 12 |
| **합계** | **32** |

세 문제는 이어진다. Q1 에서 만든 Deployment 에 Q2 가 스토리지를 붙이고, Q1 의 Service 를 Q3 가 외부로 노출한다. 순서대로 푼다.

막히면 `bash exam-start.sh --hints` 로 힌트를 볼 수 있다. **시험 중에는 사용하지 않는다.**
