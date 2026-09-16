# NetworkPolicy 예제 YAML

설명은 [../NETWORKPOLICY.md](../NETWORKPOLICY.md) 참고. 전부 `prod` 네임스페이스 기준.

| 파일 | 내용 |
|---|---|
| `01-default-deny-ingress.yaml` | 네임스페이스 전체 Ingress 차단 (기본 거부) |
| `02-default-deny-all.yaml` | Ingress + Egress 전부 차단 |
| `03-allow-from-pod.yaml` | 같은 ns 의 특정 파드에서만 허용 (podSelector) |
| `04-allow-from-namespace.yaml` | 특정 네임스페이스에서 허용 (namespaceSelector) |
| `05-allow-namespace-and-pod.yaml` | 특정 ns 의 특정 파드만 — AND 조건 |
| `06-egress-allow-dns-and-db.yaml` | Egress 제한 + DNS 허용 패턴 |
| `07-ipblock.yaml` | CIDR 대역 허용, 일부 IP 제외 |
| `08-allow-all-ingress.yaml` | 특정 파드만 전부 허용 (`- {}`) |
| `09-three-tier.yaml` | frontend → backend → db 3계층 격리 (정책 3개 묶음) |

```bash
kubectl create namespace prod
kubectl apply -f 01-default-deny-ingress.yaml
kubectl apply -f 03-allow-from-pod.yaml
kubectl describe networkpolicy -n prod
```

정리:

```bash
kubectl delete networkpolicy --all -n prod
```
