# 3세션 시험 — Deployment/Service · StorageClass/PVC · Gateway API

> 출제 범위: Deployment + Service 연결 · 주어진 StorageClass 로 PVC 생성 후 마운트 · Gateway API 외부 노출
> 모든 환경은 `exam-start.sh` 가 자동으로 준비한다. 수강생은 문제만 풀면 된다.

## 사용법

```bash
bash exam-start.sh      # 환경 준비 + 문제 출제 (권장 35분)
bash verify.sh          # 채점

bash exam-start.sh --hints          # 정답 힌트 포함 — 시험 중 사용 금지
bash exam-start.sh --skip-gateway   # Gateway API 설치 없이 Q1·Q2만 준비
```

## exam-start.sh 가 준비하는 것

| 항목 | 내용 |
|------|------|
| 네임스페이스 | `shop` 생성 |
| StorageClass | `exam-storage` (hostPath 기반, `no-provisioner`, Immediate 바인딩) |
| PersistentVolume | `exam-pv-1~3` — 각 2Gi, hostPath `/mnt/exam-data-N`, `DirectoryOrCreate` |
| Gateway API | Gateway API CRD + NGINX Gateway Fabric v2.7.0 (NodePort 배포판), GatewayClass `nginx` |

**전제 조건**
- kubeadm 클러스터에서 `kubectl get nodes` 가 Ready
- 이미지 pull 가능 (`nginx:1.24`, `busybox:1.36`)
- Gateway API 설치를 위해 **인터넷 연결 필요** (최초 1회). 실패해도 Q1·Q2는 정상 진행된다.

첫 실행은 컨트롤러 이미지를 받느라 2~3분 걸릴 수 있다. 이미 설치되어 있으면 재설치를 건너뛴다.

---

## Q1. Deployment 를 만들고 Service 로 연결 (11항목)

| 항목 | 값 |
|------|-----|
| namespace | `shop` (이미 생성됨) |
| Deployment | `shop-web` / `nginx:1.24` / replicas 2 / containerPort 80 |
| Service | `shop-svc` / ClusterIP / 80 → 80 |

**채점 포인트**
- 이미지·replicas·containerPort, 파드 2개 Ready
- Service 타입·port·targetPort
- **Endpoints 에 파드 IP 2개** — 0이면 selector 불일치
- **실제 통신** — 임시 파드에서 `wget http://shop-svc` 가 nginx 응답을 받는지

## Q2. 주어진 StorageClass 로 PVC 생성 후 Deployment 에 연결 (9항목)

| 항목 | 값 |
|------|-----|
| PVC | `shop-data` / storageClassName `exam-storage` / 1Gi / ReadWriteOnce |
| 마운트 | `shop-web` Deployment 에 mountPath **`/data`** |

**채점 포인트**
- storageClassName·accessModes·요청 용량
- PVC 가 **Bound** 상태이고 `exam-pv-*` 에 바인딩되었는지
- Deployment 가 PVC 를 볼륨으로 참조하고 `/data` 에 마운트하는지
- **파드 내부에서 실제로 `/data` 에 쓰고 읽을 수 있는지** (`kubectl exec` 검증)

> `/usr/share/nginx/html` 에 마운트하면 nginx 문서 루트가 빈 디렉토리가 되어 Q1 의 통신 검증이 깨진다. 그래서 `/data` 로 지정했다.
>
> 이 StorageClass 는 미리 만들어둔 hostPath PV(2Gi × 3)를 쓴다. 요청 용량이 PV 보다 크거나 accessModes 가 다르면 Bound 되지 않는다. `kubectl describe pvc` 로 원인을 읽는 연습을 하는 지점이다.

## Q3. Gateway API 로 외부 노출 (12항목)

| 항목 | 값 |
|------|-----|
| Gateway | `shop-gw` / gatewayClassName `nginx` / listener `http` · port 80 · HTTP |
| HTTPRoute | `shop-route` / parentRef `shop-gw` / backendRef `shop-svc`:80 |
| 외부 노출 | Gateway 가 만든 Service 를 **nodePort 30081** 로 변경 |

**채점 포인트**
- Gateway·HTTPRoute 의 필드 정확도 (8항목)
- Gateway 가 컨트롤러에 의해 **Accepted** 되었는지, HTTPRoute 의 **ResolvedRefs** 가 True 인지
- nodePort 30081 로 노출된 Service 존재
- **실제 외부 접속** — `curl http://<NodeIP>:30081` 이 nginx 응답을 받는지

> VirtualBox 환경에는 LoadBalancer 가 없으므로 NodePort 로 노출한다. NGINX Gateway Fabric 은 NodePort 배포판으로 설치되어 있고, Gateway 를 만들면 컨트롤러가 `shop` 네임스페이스에 Service 를 자동 생성한다. 그 Service 의 nodePort 를 30081 로 바꾸면 된다.
>
> Service 이름은 `<게이트웨이이름>-nginx` 형태로 만들어진다 (이 문제에서는 `shop-gw-nginx`). 이미 NodePort 타입이지만 포트가 랜덤 배정되므로 30081 로 바꾸면 된다. 채점 스크립트는 이름이 아니라 **nodePort 값 30081** 로 찾는다.
>
> **접속이 안 될 때**: 이 Service 는 `externalTrafficPolicy: Local` 인 경우가 있다. 그러면 게이트웨이 파드가 떠 있는 노드의 IP 로만 응답하고, 다른 노드 IP 로는 연결되지 않는다. `kubectl get pods -n shop -o wide` 로 파드가 있는 노드를 확인해서 그 IP 로 접속하거나, `externalTrafficPolicy` 를 `Cluster` 로 바꾼다. 채점 스크립트는 모든 노드 IP 를 순회하므로 어느 쪽이든 통과한다.

---

## 정답 명령어 (강사용)

```bash
# Q1
kubectl create deployment shop-web --image=nginx:1.24 --replicas=2 --port=80 -n shop
kubectl expose deployment shop-web --name=shop-svc --port=80 --target-port=80 --type=ClusterIP -n shop

# Q2 — PVC 생성
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shop-data
  namespace: shop
spec:
  storageClassName: exam-storage
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
EOF

# Q2 — Deployment 에 마운트 (kubectl edit deployment shop-web -n shop)
#   spec.template.spec.volumes:
#   - name: data
#     persistentVolumeClaim:
#       claimName: shop-data
#   containers[0].volumeMounts:
#   - name: data
#     mountPath: /data

# Q3 — Gateway + HTTPRoute
cat <<'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shop-gw
  namespace: shop
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shop-route
  namespace: shop
spec:
  parentRefs:
  - name: shop-gw
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: shop-svc
      port: 80
EOF

# Q3 — NodePort 30081 로 변경 (서비스 이름은 kubectl get svc -n shop 으로 확인)
kubectl patch svc <서비스이름> -n shop \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"targetPort":80,"nodePort":30081}]}}'

curl http://192.168.56.10:30081
```

## 채점 총점

| 문제 | 항목 수 |
|------|--------|
| Q1 Deployment + Service | 11 |
| Q2 StorageClass + PVC | 9 |
| Q3 Gateway API | 12 |
| **합계** | **32** |

Gateway API 설치가 실패한 환경에서는 Q3 가 자동으로 제외되어 **20항목**으로 채점되고, 건너뛴 항목 수가 함께 표시된다.

## 실습 후 정리

```bash
kubectl delete namespace shop
```

```bash
kubectl delete pv exam-pv-1 exam-pv-2 exam-pv-3 && kubectl delete sc exam-storage
```

NGINX Gateway Fabric 을 완전히 제거하려면 `kubectl delete namespace nginx-gateway` 후 CRD 를 지운다. 다음 시험에서 재사용할 것이라면 그대로 두어도 된다.

## 다른 실습 세트와의 관계

이 세트는 모든 리소스를 `shop` 네임스페이스와 `exam-` 접두사 안에 격리한다. `default` 네임스페이스를 쓰는 다른 실습 세트(`00-session-check`, `03-workloads`, `06-networking` 등)와 이름이 겹치지 않으므로, 다른 세트의 답안을 지우지 않는다.
