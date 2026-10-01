# Final Test — 출제 주제 5유형 30분 점검 (강사용)

> **문제만 보려면 `QUESTIONS.txt`.** 이 파일에는 정답이 들어 있다.
>
> **한 문제씩 풀기:** `bash exam.sh start` → 풀고 → `bash exam.sh check`. 끝나면 `bash exam.sh clean`.

## 목적

2026 합격 후기에서 확인된 **출제 주제 13선**(`고객발송/CKA_출제주제13선_풀이`)을 다섯 유형으로 묶고,
유형마다 한 문제 이상씩 **6문제를 30분 안에** 푸는지 본다. 문제당 5분 — 실제 시험(문제당 평균 7분)보다 빠듯하다.

mock-6 이 13선 중 01·02·08·09·10 을 다뤘으므로, finaltest 는 **나머지 주제(04·05·06·11·12)** 와 09 의 Egress 변형으로 채웠다. 두 세트를 다 풀면 13선 중 11개를 손으로 한 번씩 해 본 셈이다.

## 5개 유형

| 유형 | 묶은 주제 (13선 번호) | 핵심 동작 | finaltest |
|------|----------------------|-----------|-----------|
| ① 워크로드 고치기 | PriorityClass(01) · HPA(04) · 사이드카(08) | 기존 Deployment 를 지우지 않고 `spec.template.spec` 을 고친다 | Q1 |
| ② 트래픽 열고 막기 | NodePort(06) · NetworkPolicy(09) · Gateway(13) | 포트·셀렉터를 맞추고, 실제로 닿는지/막히는지 확인한다 | Q2 · Q3 |
| ③ 스토리지 붙이기 | StorageClass(10) · PV/PVC(12) | 클래스·접근 모드·용량 세 가지를 맞춰 Bound 를 만든다 | Q4 |
| ④ 클러스터 운영 | Helm(02) · 패키지(03) · etcd(05) · CNI(07) | kubectl 밖의 도구(helm · etcdctl · dpkg · systemctl)를 쓴다 | Q5 |
| ⑤ 조회해서 파일로 | Pod 리스트 저장(11) | 필터·정렬·출력 형식을 지문대로 맞춘다 | Q6 |

뺀 주제와 이유: 패키지 설치(03, `.deb` 없음) · CNI 설치(07, 클러스터를 망가뜨려야 함) · Gateway 전환(13, 컨트롤러 설치에 3분 이상) · etcd **복원**(05, 되돌릴 수 없음 — 백업만 낸다).

| 문항 | 유형 | 13선 | 주제 | 배점 | 함정 |
|------|------|------|------|------|------|
| Q1 | ① | 04 | HPA + scaleDown 안정화 | 15 | `behavior` 는 `kubectl autoscale` 옵션이 없다 → edit. cpu request 가 없으면 HPA 가 못 잰다 |
| Q2 | ② | 06 | NodePort 고정 번호 | 15 | port 80 / targetPort **8080** / nodePort 30180 — 세 포트를 섞는다 |
| Q3 | ② | 09 | NetworkPolicy Egress | 20 | **DNS(53) 를 안 열면** 이름으로 db 에 못 간다 |
| Q4 | ③ | 12 | Pending PVC 에 맞는 PV + Pod | 20 | PVC 의 storageClassName `archive-manual` 을 읽어 PV 에 맞춘다 |
| Q5 | ④ | 05 | etcd 스냅샷 | 15 | `sudo` 누락 · `--ca-cert` 오타 |
| Q6 | ⑤ | 11 | 조건별 Pod 목록 파일 | 15 | `-o name` 은 `pod/` 가 붙는다. 헤더 제거 |

## 환경

`exam.sh start` 가 준비하는 것:

| 문항 | 네임스페이스 | 미리 만드는 것 |
|------|--------------|----------------|
| Q1 | `scaling` | Deployment `api-server` (nginx, resources 없음) |
| Q2 | `storefront` | Deployment `catalog` (http-echo, 8080 에서 `catalog-ok`) · 파드 `client` |
| Q3 | `vault` | 파드 `worker` · `db`(+Service) · `web`(+Service) |
| Q4 | `records` | PVC `archive-claim` (archive-manual · RWO · 500Mi, Pending) |
| Q5 | — | `/tmp/finaltest` 디렉터리, etcdctl 유무 안내 |
| Q6 | `fleet` | 파드 5개: `web-a` `web-b` `web-c`(이미지 오류) `api-a` `batch-a`(이미지 오류) |

- 제한시간 30분. `EXAM_LIMIT_MIN=0 bash exam.sh start` 로 풀면 무제한 연습.
- **컨트롤 플레인 노드에서** 실행한다 (Q5 가 `/etc/kubernetes/pki` 와 `/tmp/finaltest` 를 쓴다).
- Q3 는 CNI 가 NetworkPolicy 를 지원해야 한다 (Cilium 이면 된다).
- Q6 의 기대값은 **채점 시점에 클러스터에서 계산**한다. 이미지 오류 파드는 Pending 이라 (b) 의 답은 `batch-a` · `web-c`.
- `clean` 은 네임스페이스 5개 · PV `pv-archive` · `/tmp/finaltest` 를 지운다.

## 정답

```bash
# Q1
kubectl -n scaling set resources deployment api-server --requests=cpu=100m
kubectl -n scaling autoscale deployment api-server --cpu-percent=60 --min=2 --max=6
kubectl -n scaling patch hpa api-server --type=merge \
  -p '{"spec":{"behavior":{"scaleDown":{"stabilizationWindowSeconds":45}}}}'

# Q2
kubectl -n storefront expose deployment catalog --name=catalog-svc \
  --type=NodePort --port=80 --target-port=8080 --dry-run=client -o yaml > svc.yaml
#   spec.ports[0].nodePort: 30180 추가
kubectl apply -f svc.yaml
kubectl -n storefront exec client -- wget -qO- -T 3 http://catalog-svc      # catalog-ok

# Q3
cat <<'YAML' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: worker-egress, namespace: vault }
spec:
  podSelector: { matchLabels: { app: worker } }
  policyTypes: [Egress]
  egress:
    - to: [ { podSelector: { matchLabels: { app: db } } } ]
      ports: [ { protocol: TCP, port: 80 } ]
    - ports: [ { protocol: UDP, port: 53 }, { protocol: TCP, port: 53 } ]
YAML

# Q4
kubectl -n records get pvc archive-claim -o yaml | grep -E 'storageClassName|accessModes|storage:' -A1
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-archive }
spec:
  capacity: { storage: 1Gi }
  accessModes: [ReadWriteOnce]
  storageClassName: archive-manual
  hostPath: { path: /mnt/archive, type: DirectoryOrCreate }
---
apiVersion: v1
kind: Pod
metadata: { name: archive-reader, namespace: records }
spec:
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts: [ { name: archive, mountPath: /data } ]
  volumes:
    - name: archive
      persistentVolumeClaim: { claimName: archive-claim }
YAML

# Q5
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/finaltest/etcd.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Q6
kubectl -n fleet get pods -l tier=web --no-headers -o custom-columns=:metadata.name > /tmp/finaltest/web-pods.txt
kubectl -n fleet get pods --field-selector=status.phase!=Running \
  --no-headers -o custom-columns=:metadata.name > /tmp/finaltest/not-running.txt
```

## 자주 틀리는 곳

| 문항 | 실수 | 채점에서 보이는 것 |
|------|------|-------------------|
| Q1 | cpu request 를 안 줌 | request 100m 3점 FAIL (HPA TARGETS 가 `<unknown>`) |
| Q1 | `spec.behavior` 대신 `spec.scaleDown` 처럼 잘못된 위치 | apply 가 거부되거나 안정화 3점 FAIL |
| Q2 | `--port=8080` 또는 `--target-port=80` | port / targetPort 항목 FAIL, client 응답 없음 |
| Q3 | DNS 규칙 없이 db 만 허용 | DNS 4점 · db 응답 4점 · web 차단 4점 모두 FAIL (이름을 못 풀어 판정 불가) |
| Q3 | `policyTypes` 에 Ingress 도 넣음 | worker 로 들어오는 것까지 막힌다 — policyTypes 2점 FAIL |
| Q4 | PV 에 storageClassName 을 안 씀 | PVC 가 Pending 그대로 — Bound · volumeName · Pod Running 줄줄이 FAIL |
| Q4 | PVC 를 지우고 내 마음대로 다시 만듦 | "PVC 를 바꾸지 않았다" FAIL |
| Q5 | `sudo` 없이 실행 | 인증서를 못 읽어 파일 없음 — 15점 전부 FAIL |
| Q6 | `-o name` 사용 | `pod/web-a` 형태라 FAIL |
| Q6 | (b) 에서 STATUS 열을 눈으로 보고 손으로 씀 | 맞으면 통과하지만 시간이 든다 — field-selector 가 빠르다 |

## 검증 상태

- 문법(`bash -n`)과 배점 합계(15+15+20+20+15+15 = 100)는 확인했다. `bash exam.sh meta` 정상 출력.
- **VM 클러스터에서 start → 풀이 → check → clean 전체 흐름은 아직 돌려 보지 않았다.** 특히 확인할 것:
  - Q2 `hashicorp/http-echo:1.0` 이미지 pull · 30180 포트 충돌 여부
  - Q3 Cilium 에서 Egress 차단 시 `wget -T 3` 이 3초 안에 끝나는지
  - Q4 hostPath `DirectoryOrCreate` 로 Pod 가 어느 노드에 떠도 Running 인지
  - Q5 root 소유 스냅샷 파일을 `sudo -n` 없이 크기·상태 판정할 수 있는지
