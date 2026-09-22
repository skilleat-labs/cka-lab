# Mock Exam 2-2 — 30분 속도 점검 (강사용)

> **문제만 보려면 `QUESTIONS.txt`.** 이 파일에는 정답이 들어 있다.
>
> **한 문제씩 풀기:** `bash exam.sh start` → 풀고 → `bash exam.sh check`. 끝나면 `bash exam.sh clean`.

## 목적

기초~중급 유형 6개를 **30분 안에** 푸는지 본다. 점수보다 최종 리포트의 **문제별 소요 시간**이 핵심 데이터다.
CKA 는 문제당 6~8분이 한계이므로, 어느 문제에 8분 넘게 걸리면 그 유형이 약점이다.

예상 출제 15선에서 고른 6개: #1 Pod 생성 · #2 Deployment+Service · #3 Secret/ConfigMap · #5 롤아웃/롤백 · #7 PV/PVC · #9 NetworkPolicy.

## 환경

`exam.sh start` 가 `store` 네임스페이스만 만든다. 나머지는 전부 학생이 만든다.
문제가 이어지므로 순서대로 푼다 — Q6 는 Q1 의 `edge-cache` 와 Q2 의 `catalog-svc` 로 실제 통신을 검증한다.

## 정답

```bash
# Q1
kubectl run edge-cache -n store --image=nginx:1.25 --port=80 --env=CACHE_MODE=lru --labels=app=edge,tier=cache

# Q2
kubectl create deployment catalog --image=nginx:1.24 --replicas=3 --port=80 -n store
kubectl expose deployment catalog --name=catalog-svc --port=80 --target-port=80 --type=NodePort -n store
kubectl patch svc catalog-svc -n store -p '{"spec":{"ports":[{"port":80,"targetPort":80,"nodePort":30095}]}}'

# Q3
kubectl create secret generic db-cred -n store --from-literal=user=admin --from-literal=pass=s3cret
kubectl create configmap app-cfg -n store --from-literal=config.properties=mode=prod
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: worker, namespace: store }
spec:
  containers:
  - name: worker
    image: busybox:1.36
    command: ["sleep", "3600"]
    env:
    - name: DB_USER
      valueFrom: { secretKeyRef: { name: db-cred, key: user } }
    volumeMounts:
    - { name: cfg, mountPath: /etc/app }
  volumes:
  - name: cfg
    configMap: { name: app-cfg }
YAML

# Q4
kubectl create deployment orders --image=nginx:1.24 --replicas=2 -n store
kubectl scale deployment orders --replicas=3 -n store
kubectl set image deployment/orders nginx=nginx:1.25 -n store && kubectl rollout status deployment/orders -n store
kubectl rollout undo deployment/orders -n store && kubectl rollout status deployment/orders -n store

# Q5
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata: { name: logs-pv }
spec:
  capacity: { storage: 1Gi }
  accessModes: [ReadWriteOnce]
  storageClassName: local-logs
  hostPath: { path: /mnt/logs }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: logs-pvc, namespace: store }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-logs
  resources: { requests: { storage: 500Mi } }
---
apiVersion: v1
kind: Pod
metadata: { name: log-writer, namespace: store }
spec:
  containers:
  - name: w
    image: busybox:1.36
    command: ["sleep", "3600"]
    volumeMounts: [ { name: logs, mountPath: /var/log/app } ]
  volumes:
  - name: logs
    persistentVolumeClaim: { claimName: logs-pvc }
YAML

# Q6
cat <<'YAML' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all, namespace: store }
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-cache-to-catalog, namespace: store }
spec:
  podSelector: { matchLabels: { app: catalog } }
  policyTypes: [Ingress]
  ingress:
  - from: [ { podSelector: { matchLabels: { tier: cache } } } ]
    ports: [ { protocol: TCP, port: 80 } ]
YAML
```

## 채점 포인트 (100점)

| 문제 | 배점 | 실제 검증 |
|------|------|-----------|
| Q1 | 15 | exec 로 환경변수 확인 |
| Q2 | 15 | Endpoints 3개 |
| Q3 | 15 | secretKeyRef 로 주입했는지 + exec 로 env·파일 확인 |
| Q4 | 15 | nginx:1.25 RS 이력 + revision ≥ 3 |
| Q5 | 20 | PVC 가 logs-pv 에 Bound + 파드 안 실제 쓰기 |
| Q6 | 20 | **tier=cache 파드 → 응답 / 레이블 없는 파드 → timeout** 둘 다 실제 통신 |

Q6 통신 검증은 CNI 가 NetworkPolicy 를 지원해야 한다 (이 클러스터의 Cilium OK, Flannel 은 항상 FAIL).

## 정리

```bash
bash exam.sh clean      # store 네임스페이스 + logs-pv 삭제
```
