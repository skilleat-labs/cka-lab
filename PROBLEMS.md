# 실습 문제 전체 목록

> 이 저장소에 들어 있는 모든 실습 세트와 문제를 한눈에 보는 색인.
> **19개 세트 전부** 한 문제씩 풀고 채점하는 `exam.sh` 를 쓴다 — `bash exam.sh start` / `check`.
> 지문은 실제 시험처럼 **영어가 기본**, 막히면 `bash exam.sh lang ko` (웹 패널은 EN/KO 버튼).
> 브라우저로 풀려면 `python3 web/server.py` — 문제·채점·터미널이 한 화면에 있다.
> 예전 방식(`bash exam-start.sh` 출제 → `bash verify.sh` 일괄 채점)도 그대로 남아 있다.
> 마지막 갱신: 2026-09-22

## 요약

| 폴더 | 성격 | 문제 수 | 채점 항목 | 주제 |
|------|------|--------|----------|------|
| `session-1-check` | 세션 점검 | 3 | 24 | Pod · Deployment · Service(ClusterIP) |
| `session-2` | 세션 시험 | 3 | 30 | 네임스페이스 · NodePort · ConfigMap · 롤아웃/롤백 |
| `session-3` | 세션 시험 | 3 | 32 | Deployment+Service · StorageClass/PVC · Gateway API |
| `session-4` | 세션 시험 | 3 | 33 | PVC→Deployment YAML · Requests/Limits · Probe |
| `13-cluster-setup` | 강의 실습 | 2 | 7 | kubeadm join · crictl |
| `06-workloads` | 강의 실습 | 4 | 26 | Deployment · ConfigMap · CronJob · DaemonSet |
| `07-scheduling` | 강의 실습 | 4 | 24 | Requests/Limits · Affinity · Taint · HPA |
| `08-storage` | 강의 실습 | 4 | 31 | PV/PVC · StorageClass · StatefulSet · emptyDir |
| `09-networking` | 강의 실습 | 4 | 30 | ClusterIP · NodePort · NetworkPolicy · DNS |
| `11-ingress` | 강의 실습 | 4 | 33 | Ingress · 호스트 기반 · TLS · NetworkPolicy |
| `14-rbac` | 강의 실습 | 4 | 26 | ServiceAccount · Role · ClusterRole · 권한 검증 |
| `15-maintenance` | 강의 실습 | 4 | 18 | drain/uncordon · etcd 백업 · 업그레이드 · 인증서 |
| `17-helm` | 강의 실습 | 4 | 18 | Helm 설치/업그레이드/롤백 · Kustomize |
| `19-troubleshooting` | 강의 실습 | 4 | 19 | CrashLoopBackOff · ImagePullBackOff · Endpoints · 노드 |
| `mock-1` | 모의고사 | 7 | 100점 | 전 범위 (목표 40분) |
| `mock-1-1` | 모의고사 변형 | 7 | 100점 | mock-1 과 같은 유형·다른 값 (retail ns) |
| `mock-2-2` | 30분 속도 점검 | 6 | 100점 | Pod·Deploy/NodePort·Secret/CM·롤백·PV/PVC·NetworkPolicy (store ns) |
| `mock-2` | 모의고사 | 7 | 100점 | 전 범위 (목표 45분) |
| `mock-3` | 모의고사 | 7 | 100점 | 전 범위 (목표 50분) |

> 채점 항목 수는 `exam.sh` 가 검사하는 개별 체크 개수다. 모의고사만 100점 배점제를 쓴다.
> 강의 실습 10개는 2026-09-22 에 `exam.sh` 순차 진행형으로 전환하면서 채점을 더 촘촘하게 고쳤다
> (실제 통신 검증·권한 검증·값 일치 검사 추가).

---

## session-1-check — 1세션 점검 (24항목)

명령어(imperative)만으로 기본 리소스 3종을 만들 수 있는지 확인한다.

| 문제 | 내용 |
|------|------|
| S1 | `kubectl run` 으로 `web-pod` 생성 (nginx:1.24 / port 80 / APP_ENV=prod) 후 `kubectl label` 로 `tier=frontend`, `env=production` 부착 |
| S2 | `kubectl create deployment` 으로 `web-app` 생성 (nginx:1.24 / replicas 3 / port 80) 후 `kubectl scale` 로 4로 변경 |
| S3 | `kubectl expose` 로 `web-svc` ClusterIP 생성 (80→80), Endpoints 4개 확인 |

**특징**: `run=web-pod` 기본 레이블로 명령어 생성 여부를 판정한다. 마지막에 임시 파드를 띄워 `wget` 으로 실제 통신을 검증한다.

## session-2 — 2세션 시험 (30항목)

네임스페이스를 지정해 만들 수 있는지, 설정 주입과 롤아웃을 다룰 수 있는지 본다.

| 문제 | 내용 |
|------|------|
| E1 | `ops` 네임스페이스 생성 → `cache-app` Deployment (nginx:1.24 / replicas 2 / port 80) → `cache-svc` NodePort **30090** |
| E2 | `app` 네임스페이스 생성 → ConfigMap `app-config` (APP_ENV, LOG_LEVEL) → `config-pod` 에 envFrom **+** 볼륨 마운트 `/etc/app-config` |
| E3 | `frontend` Deployment 생성 → replicas 4 스케일 → nginx:1.25 롤링 업데이트 → 이전 리비전으로 롤백 |

**특징**: `default` 네임스페이스에 잘못 만들었는지 검사한다. ConfigMap 은 `kubectl exec` 로 파드 내부 환경변수·파일을 실제 확인한다. E3 는 revision 과 ReplicaSet 이력으로 세 단계를 실제로 거쳤는지 판정한다.

---

## session-3 — 3세션 시험 (32항목)

환경(네임스페이스 · StorageClass · PV · Gateway API 컨트롤러)은 `exam-start.sh` 가 전부 준비한다.

| 문제 | 내용 |
|------|------|
| Q1 | `shop` 네임스페이스에 `shop-web` Deployment (nginx:1.24 / replicas 2 / port 80) + `shop-svc` ClusterIP 연결 |
| Q2 | 주어진 StorageClass `exam-storage` 로 `shop-data` PVC(1Gi/RWO) 생성 후 Deployment 에 `/data` 마운트 |
| Q3 | Gateway `shop-gw` + HTTPRoute `shop-route` 작성 후 nodePort **30081** 로 외부 노출 |

**특징**: hostPath 기반 StorageClass 와 NGINX Gateway Fabric(NodePort 배포판)을 스크립트가 자동 설치한다.
Gateway API 설치가 안 된 환경에서는 Q3 가 자동으로 제외되고 20항목으로 채점된다.
모든 리소스가 `shop` 네임스페이스에 격리되어 다른 세트의 답안을 지우지 않는다.

---

## session-4 — 4세션 시험 (33항목)

환경(네임스페이스 · StorageClass · PV · Q2용 Deployment)은 `exam-start.sh` 가 준비한다. 외부 설치가 없어 오프라인에서도 동작한다.

| 문제 | 내용 |
|------|------|
| Q1 | `api-storage` 로 PVC `api-data` 생성 후 Deployment `api-server` YAML 에 **처음부터** 볼륨 포함해 생성 (`/var/www/data`) |
| Q2 | 미리 만들어진 `api-worker` Deployment 에 requests(100m/128Mi) · limits(200m/256Mi) 추가 |
| Q3 | Pod `health-pod` 에 조건대로 livenessProbe · readinessProbe 작성 |

**특징**: Q1 은 Deployment revision 이 1 인지 확인해 "만든 뒤 수정"을 오답 처리한다. Q2 는 실행 중인 파드에 반영됐는지와 QoS 클래스(Burstable)를 본다. Q3 는 파드가 Ready 이고 재시작 0 인지로 probe 가 실제로 통과 중인지 본다.

---

## 13-cluster-setup — 클러스터 구축 (5항목)

| 문제 | 내용 |
|------|------|
| P1 | worker-2(192.168.56.12) 노드를 클러스터에 join |
| P2 | control-plane 에서 `crictl` 로 컨테이너 확인 및 로그 출력 |

## 06-workloads — 워크로드 (20항목)

| 문제 | 내용 |
|------|------|
| P1 | Deployment 생성 후 Scale · Rolling Update · Rollback |
| P2 | ConfigMap 생성 후 파드에 환경변수 주입 |
| P3 | 매 분 `date` 를 출력하는 CronJob |
| P4 | `monitoring` 네임스페이스에 DaemonSet (hostNetwork/hostPID) |

## 07-scheduling — 스케줄링 (21항목)

| 문제 | 내용 |
|------|------|
| P1 | Resource Requests/Limits 설정된 파드 |
| P2 | Node Affinity 로 worker-1(disktype=ssd)에 배치 |
| P3 | worker-2 의 Taint(dedicated=gpu:NoSchedule) 허용하는 Toleration |
| P4 | HPA 생성 |

## 08-storage — 스토리지 (23항목)

| 문제 | 내용 |
|------|------|
| P1 | PersistentVolume + PVC 생성 및 바인딩 |
| P2 | StorageClass + PVC |
| P3 | StatefulSet + volumeClaimTemplates |
| P4 | emptyDir 공유 볼륨 파드 |

## 09-networking — 서비스와 네트워킹 (27항목)

| 문제 | 내용 |
|------|------|
| P1 | ClusterIP 서비스 (web / replicas 3) |
| P2 | NodePort 서비스 (api / nodePort 30080) |
| P3 | NetworkPolicy — frontend 에서만 backend 인그레스 허용 |
| P4 | DNS 검증 (busybox 파드에서 nslookup) |

## 11-ingress — 외부 트래픽 (23항목)

| 문제 | 내용 |
|------|------|
| P1 | 기본 Ingress 생성 |
| P2 | 호스트 기반 라우팅 Ingress |
| P3 | TLS Ingress |
| P4 | NetworkPolicy 로 production 네임스페이스 격리 |

## 14-rbac — 권한과 인증 (26항목)

| 문제 | 내용 |
|------|------|
| P1 | ServiceAccount 생성 후 파드에 적용 |
| P2 | Role + RoleBinding |
| P3 | ClusterRole + ClusterRoleBinding |
| P4 | `kubectl auth can-i` 로 권한 검증 |

## 15-maintenance — 클러스터 유지보수 (9항목)

| 문제 | 내용 |
|------|------|
| P1 | worker-2 drain 후 작업 완료 시 uncordon |
| P2 | etcd 스냅샷을 `/tmp/etcd-backup.db` 에 저장 |
| P3 | `kubeadm upgrade plan` 으로 업그레이드 가능 버전 확인 |
| P4 | `kubeadm certs check-expiration` 으로 인증서 만료 확인 |

## 17-helm — 패키징 도구 (11항목)

| 문제 | 내용 |
|------|------|
| P1 | bitnami repo 추가 후 nginx 를 `my-nginx` 로 설치 |
| P2 | `replicaCount=3` 으로 업그레이드 |
| P3 | revision 1 로 롤백 |
| P4 | Kustomize 디렉토리 구성 후 `kubectl apply -k` |

## 19-troubleshooting — 트러블슈팅 (8항목)

| 문제 | 내용 |
|------|------|
| P1 | `broken-pod` CrashLoopBackOff 원인 진단 및 수정 |
| P2 | `pull-fail` ImagePullBackOff 수정 |
| P3 | `target-svc` Endpoints 가 비어 있는 원인 수정 |
| P4 | 클러스터 노드 상태 점검 |

---

## 모의고사 (각 7문항 · 100점)

### mock-1 — 목표 40분

| 문제 | 내용 | 도메인 | 배점 |
|------|------|--------|------|
| Q1 | Deployment 생성 | Workloads | 15 |
| Q2 | Service 생성 | Networking | 10 |
| Q3 | ConfigMap + Pod | Workloads | 10 |
| Q4 | PersistentVolume + PVC | Storage | 15 |
| Q5 | RBAC | Architecture | 15 |
| Q6 | 노드 drain | Architecture | 10 |
| Q7 | Pod 트러블슈팅 | Troubleshooting | 25 |

### mock-1-1 — mock-1 변형판 (목표 40분)

같은 7유형이지만 `retail` 네임스페이스에서 이름·값·조건이 전부 다르다. mock-1 답을 붙여넣으면 틀린다.

| 문제 | 내용 | 도메인 | 배점 |
|------|------|--------|------|
| Q1 | Deployment `store-front` (nginx:1.25, replicas 4, port 80) | Workloads | 15 |
| Q2 | Service `store-svc` ClusterIP **8080 → 80** | Networking | 10 |
| Q3 | ConfigMap `store-config` → `store-cfg` envFrom | Workloads | 10 |
| Q4 | PV `report-pv` **1Gi RWX** sc `local-manual` → PVC | Storage | 15 |
| Q5 | RBAC — `deploy-reader` **deployments** get/list/watch, pods 는 불가 | Architecture | 15 |
| Q6 | **worker-2** drain / uncordon | Architecture | 10 |
| Q7 | `web-broken`(`nginz:1.24` 오타) → **nginx:1.24** 로 수정 | Troubleshooting | 25 |

### mock-2-2 — 30분 속도 점검 (목표 30분)

예상 출제 15선에서 기초~중급 6개를 골라 `store` 네임스페이스에서 순차 진행. **문제별 소요 시간**이 핵심 데이터.

| 문제 | 내용 | 도메인 | 배점 |
|------|------|--------|------|
| Q1 | `edge-cache` Pod — 이미지·포트·env·레이블 조건 | W&S | 15 |
| Q2 | `catalog` Deployment + `catalog-svc` NodePort 30095 | NET | 15 |
| Q3 | Secret → env(secretKeyRef) + ConfigMap → 볼륨 | W&S | 15 |
| Q4 | `orders` 스케일 → 롤링 업데이트 → 롤백 | W&S | 15 |
| Q5 | PV `logs-pv` 직접 생성 → PVC Bound → 파드 마운트 | STORAGE | 20 |
| Q6 | deny-all + allow-cache-to-catalog — **실제 통신으로 허용/차단 검증** | NET | 20 |

### mock-2 — 목표 45분

| 문제 | 내용 | 도메인 | 배점 |
|------|------|--------|------|
| Q1 | Node Affinity Pod | Workloads | 15 |
| Q2 | Taint + Toleration | Workloads | 15 |
| Q3 | NetworkPolicy | Networking | 20 |
| Q4 | Ingress 생성 | Networking | 15 |
| Q5 | StatefulSet | Workloads | 15 |
| Q6 | etcd 백업 | Architecture | 10 |
| Q7 | Node NotReady 복구 | Troubleshooting | 10 |

### mock-3 — 목표 50분

| 문제 | 내용 | 도메인 | 배점 |
|------|------|--------|------|
| Q1 | HPA 설정 | Workloads | 10 |
| Q2 | StorageClass + PVC | Storage | 15 |
| Q3 | RBAC ClusterRole | Architecture | 20 |
| Q4 | DaemonSet 생성 | Workloads | 15 |
| Q5 | Service Endpoint 수정 | Troubleshooting | 20 |
| Q6 | CrashLoopBackOff 수정 | Troubleshooting | 10 |
| Q7 | 클러스터 업그레이드 계획 | Architecture | 10 |

---

## 알아둘 점

- **폴더 번호는 실습 세트 번호이며 강의 회차와 일대일 대응이 아니다.** 담당 강사의 안내를 따른다.
- `13-cluster-setup` 은 worker 노드 IP 가 `192.168.56.12` 로 고정되어 있다. 다른 IP 라면 스크립트를 수정한다.
- `15-maintenance`, `17-helm`, `19-troubleshooting` 은 채점 항목 수가 상대적으로 적다. 통과했다고 해서 완전히 익혔다고 보기 어려우니 반복 연습이 필요하다.
- `exam-start.sh --hints` 는 정답 명령어까지 출력한다. 시험용으로 쓸 때는 사용하지 않는다.
