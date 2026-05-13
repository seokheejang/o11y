# Baseline Alerts — 운영 필수 알림

> "할 일 없으면 알림 만들지 마라" ([alerting-philosophy.md](alerting-philosophy.md)) 원칙 위에서, **K8s 클러스터를 24/7 운용하기 위해 반드시 받아야 할 베이스라인** — `components/_external/kubernetes.libsonnet`이 가져오는 `kubernetes-mixin` 위에서 실무 합의를 반영해 정리.

**적용 정책**: severity는 `critical` / `warning` 2단계만 ([severity-policy.md](severity-policy.md)). critical은 페이저 + on-call ack 15분, warning은 영업시간 대응.

작성일: 2026-05-06

---

## 1. 반드시 critical (페이저 / 야간 호출)

| 알림 | 표현식 패턴 | for | 왜 필수 | 출처 |
|---|---|---|---|---|
| **KubeAPIDown** | `absent(up{job="apiserver"} == 1)` | 15m | API 서버 부재 = 클러스터 control plane 자체 불가. 거의 모든 운영 동작 정지. | kubernetes-mixin |
| **KubeNodeNotReady** | `kube_node_status_condition{condition="Ready",status="true"} == 0` | 15m | 노드 1개가 빠지면 그 노드의 모든 워크로드 영향. 자동 evict 트리거. | kubernetes-mixin |
| **KubeletDown** | `absent(up{job="kubelet"} == 1)` | 15m | kubelet 다운 = 그 노드의 Pod 라이프사이클 관리 정지. 새 Pod 안 뜨고 health 확인 안 됨. | kubernetes-mixin |
| **KubePersistentVolumeFillingUp (3% 이하)** | `kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes < 0.03 and predict_linear(...[6h], 4*24*3600) < 0` | 1h | DB/StatefulSet 볼륨이 가득 차면 쓰기 실패 → 데이터 손실. 4일 내 가득 찬다는 예측이면 critical. | kubernetes-mixin |
| **KubePersistentVolumeErrors** | `kube_persistentvolume_status_phase{phase=~"Failed\|Pending"} > 0` | 5m | PV가 Failed면 그 PV에 의존하는 워크로드가 시작 못 함. | kubernetes-mixin |
| **etcdMembersDown** | `count by (job, cluster) (etcd_members{job=~".*etcd.*"}) - sum by (job, cluster) (up{job=~".*etcd.*"} == bool 1) > 0` | 3m | etcd 멤버 1개 다운 = quorum 위험. 2개 빠지면 클러스터 read-only. | etcd-mixin |
| **etcdHighNumberOfFailedGRPCRequests** | `100 * rate(grpc_server_handled_total{grpc_code=~"Unknown\|FailedPrecondition\|...",job="etcd"}[5m]) / rate(grpc_server_handled_total{job="etcd"}[5m]) > 1` | 10m | etcd 응답 실패 1% 초과 → API 서버 지연으로 전파. | etcd-mixin |
| **CertificateExpiry (7일 이내)** | `(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 7` | 1h | TLS 만료는 정확한 시점에 사용자 영향 발생. 7일이면 갱신 실패 시 대응 시간 충분치 않음. | cert-manager docs |
| **KubeClientCertificateExpiration (24시간 이내)** | `apiserver_client_certificate_expiration_seconds_count > 0 and on(job) histogram_quantile(0.01, ...) < 86400` | - | API 서버 client cert 만료 = control plane 인증 깨짐. | kubernetes-mixin |
| **HighRateOfOOMKill** | `rate(container_oom_events_total[5m]) > 0` | 5m | 반복 OOM = 메모리 한도 잘못 잡힘 또는 메모리 누수. 사용자 영향 직접. | (추가 권장) |

> ⚠️ **반드시 검토 후 결정**: 아래는 kubernetes-mixin 디폴트 critical이지만 환경에 따라 noise로 평가됨. 우리 환경에 맞춰 켜거나 warning으로 다운그레이드.

| 알림 | 이슈 | 권장 |
|---|---|---|
| **KubeAPIErrorBudgetBurn** | 정상 동작 중에는 5xx 메트릭 자체가 없어 알림이 갈 길이 없는 metric definition 결함 ([kube-prometheus#1480](https://github.com/prometheus-operator/kube-prometheus/issues/1480)). 67.x 업그레이드 후 false positive 사례 보고 ([helm-charts#5114](https://github.com/prometheus-community/helm-charts/issues/5114)). | **warning으로 다운그레이드**. 또는 SLO multi-burn-rate를 우리 mixin에서 직접 정의. |
| **CPUThrottlingHigh** | CPU limit 미달임에도 발화하는 false positive 빈번 ([kubernetes-mixin#108](https://github.com/kubernetes-monitoring/kubernetes-mixin/issues/108)). | **disable** — 또는 임계값을 75% → 90%로 상향. |

---

## 2. warning (영업일 대응)

| 알림 | 표현식 패턴 | for | 왜 필수 |
|---|---|---|---|
| **KubePodCrashLooping** | `max_over_time(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}[5m]) >= 1` | 15m | Pod 재시작 반복은 배포 결함 신호. critical 아님 (다른 replica가 트래픽 받음). |
| **KubePodNotReady** | `sum by(namespace, pod)(kube_pod_status_phase{phase=~"Pending\|Unknown"}) > 0` | 15m | 새 Pod이 15분 넘게 Pending = scheduling/이미지/PV 문제. |
| **KubeDeploymentReplicasMismatch** | `kube_deployment_spec_replicas != kube_deployment_status_replicas_available` | 15m | desired ≠ available. rolling update 중에는 잠시 정상이라 for 길게. |
| **KubeStatefulSetReplicasMismatch** | (위와 동일 패턴, sts) | 15m | StatefulSet 1개 빠지면 데이터 분산 영향 가능 — 그러나 즉각 critical은 과함. |
| **KubeMemoryOvercommit** | `sum(kube_pod_container_resource_requests{resource="memory"}) > sum(kube_node_status_allocatable{resource="memory"}) * 0.95` | 5m | 노드 1개 잃으면 Pod re-schedule 못 함. 용량 계획 신호. |
| **KubeCPUOvercommit** | (위와 동일, cpu) | 5m | 위와 같은 capacity planning. |
| **KubePersistentVolumeFillingUp (15% 이하, 4일 예측)** | `... < 0.15 and predict_linear(...[6h], 4*24*3600) < 0` | 1h | 4일 여유 있으면 영업시간 대응. (3% 이하면 critical) |
| **KubeCertificateExpiry (21일 이내)** | `(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 21` | 1h | ACME 자동갱신은 30일 전 시작. 21일 남은 거면 갱신 안 되고 있다는 신호. ([cert-manager 권장](https://cert-manager.io/docs/devops-tips/prometheus-metrics/)) |
| **HighImagePullErrorRate** | `rate(kubelet_image_pull_errors_total[15m]) > 0.1` | 15m | 레지스트리 인증 만료, 네트워크 등. 새 배포 영향. |
| **HighOOMKillFrequency (단일 Pod)** | `sum by(namespace,pod)(rate(container_oom_events_total[1h])) > 1` | 30m | 위의 critical과 다르게 단발성 OOM (전역 빈도가 아닌 특정 Pod). |

---

## 3. 꺼야 하는 알림 (alert fatigue 원인)

업계에서 noise로 합의된 것 / 환경 의존성이 커서 디폴트 끄고 필요 시 직접 작성:

| 알림 | 이유 | 권장 |
|---|---|---|
| **CPUThrottlingHigh** | limit 미달인데도 발화하는 케이스가 흔함. throttling 자체는 정보일 뿐 사용자 영향 직결 X. ([kubernetes-mixin#108](https://github.com/kubernetes-monitoring/kubernetes-mixin/issues/108)) | **disable** |
| **KubeHpaMaxedOut** | minReplicas == maxReplicas로 일부러 핀하는 케이스에 false positive ([kubernetes-mixin#1193](https://github.com/kubernetes-monitoring/kubernetes-mixin/issues/1193)) | **disable** 또는 minReplicas != maxReplicas 조건 추가 |
| **KubeAPIErrorBudgetBurn (default)** | metric 정의 결함 + 67.x 업그레이드 false positive | **disable**, SLO 자체는 우리가 직접 작성 (multi-burn-rate) |
| **KubeJobFailed** (default) | CronJob retry로 일시 fail은 정상 — 노이즈 큼 | **유지하되 for 길게(30m)** 또는 도메인별 Job만 watch |
| **KubeContainerWaiting** (전역) | startup 중 잠깐 waiting은 정상 | **disable** — KubePodNotReady가 더 정확한 신호 |
| **KubePodNotScheduled** | KubePodNotReady와 신호 중복 | **disable** (KubePodNotReady가 cover) |

---

## 4. 추가로 넣어야 할 베이스라인 알림 (kubernetes-mixin 외)

차트/mixin이 안 만들지만 운영팀이 표준으로 추가하는 것:

### Certificate / TLS
- **CertManagerCertNotReady** — `certmanager_certificate_ready_status{condition="False"} == 1` for 10m → critical. [cert-manager-mixin](https://monitoring.mixins.dev/cert-manager/)
- **CertExpiringSoon** — 21일 warning, 7일 critical (위 표 참고)

### DNS
- **CoreDNSLatencyHigh** — `histogram_quantile(0.99, rate(coredns_dns_request_duration_seconds_bucket[5m])) > 1` for 10m → critical. DNS 지연은 모든 service discovery 지연.
- **CoreDNSErrorsHigh** — `rate(coredns_dns_responses_total{rcode=~"SERVFAIL|REFUSED"}[5m]) > 0.05` for 10m → warning.

### Ingress / Network
- **IngressControllerDown** — `absent(up{job=~"ingress.*"} == 1)` for 5m → critical (ingress가 외부 트래픽 진입점).
- **HighIngress5xxRate** — `rate(nginx_ingress_controller_requests{status=~"5.."}[5m]) > 0.05` for 10m → critical.

### Image registry
- **HighImagePullBackOff** — `kube_pod_container_status_waiting_reason{reason="ImagePullBackOff"} > 0` for 15m → warning. 새 배포 진입 차단 신호.

### Storage / Disk I/O
- **HighDiskSaturation** — `rate(node_disk_io_time_seconds_total[5m]) > 0.9` for 15m → warning (kubernetes-mixin이 안 다루는 영역).
- **HighInodeUsage** — `node_filesystem_files_free / node_filesystem_files < 0.10` for 1h → warning.

### Workload-level
- **HighPodRestartRate** — `rate(kube_pod_container_status_restarts_total[1h]) > 1` for 15m → warning. CrashLooping 직전 신호.

### Operator / Controller
- **PrometheusRuleFailures** — `prometheus_rule_evaluation_failures_total > 0` → critical (룰 평가 자체가 실패하면 알림이 안 옴 → 알림의 알림). [Wiki](https://github.com/prometheus-operator/kube-prometheus/wiki/prometheusrulefailures)
- **AlertmanagerConfigInconsistent** — `count by(service) (alertmanager_config_hash) > 1` → critical (HA 설정 불일치).

> 우리 repo 적용: 이 항목들은 `components/_external/`(외부 mixin import)와 `components/prometheus/` (자체 알림 룰) + `components/alertmanager/` (라우팅)로 나눠 관리.

---

## 5. Alertmanager 라우팅 정책

업계 표준 패턴 — `severity` + `team`/`area` 라벨 조합:

```yaml
route:
  group_by: [alertname, cluster, namespace]
  group_wait: 30s            # 동일 그룹 알림 묶기 위한 대기
  group_interval: 5m         # 새 알림 추가될 때 알림 간격
  repeat_interval: 4h        # 같은 알림 반복 알림 간격 (default)
  receiver: default-slack    # 매치 안 되면 여기로

  routes:
    # critical → 페이저 + Slack 둘 다
    - matchers: [severity="critical"]
      receiver: pager           # PagerDuty / Opsgenie
      repeat_interval: 1h
      continue: true            # ← 핵심: 다음 라우트도 매치하도록
    - matchers: [severity="critical"]
      receiver: critical-slack  # #alerts-critical

    # warning → Slack만
    - matchers: [severity="warning"]
      receiver: warning-slack   # #alerts-warning
      repeat_interval: 12h

    # 도메인별 분기 (선택)
    - matchers: [team="platform"]
      receiver: platform-slack
    - matchers: [team="data"]
      receiver: data-slack

inhibit_rules:
  # 1. critical이 발화 중이면 같은 alertname의 warning 억제
  - source_matchers: [severity="critical"]
    target_matchers: [severity="warning"]
    equal: [alertname, cluster, namespace]

  # 2. NodeNotReady 시 그 노드의 모든 Pod 알림 억제 (스톰 방지)
  - source_matchers: [alertname="KubeNodeNotReady"]
    target_matchers: [alertname=~"KubePodCrashLooping|KubePodNotReady"]
    equal: [node]

  # 3. APIDown 시 다른 K8s 알림 억제 (메트릭 자체가 부정확할 수 있음)
  - source_matchers: [alertname="KubeAPIDown"]
    target_matchers: [alertname=~"Kube.*"]
    equal: [cluster]
```

**핵심 결정 사항:**
- `continue: true`: critical 1건 → PagerDuty + Slack 동시 발송
- `inhibit_rules`: 큰 사고 시 스톰 방지 (NodeDown 1건이 Pod 알림 50건 만들지 않게)
- `group_by`: `cluster` 라벨 포함해서 multi-cluster 환경에서도 분리

출처: [DataOps.tech 라우팅 가이드](https://medium.com/dataops-tech/routing-alerts-in-slack-pagerduty-by-severity-so-noise-doesnt-kill-you-874060ef2996), [Prometheus 공식 — Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)

---

## 6. 소규모 팀 vs 대규모 팀

### Solo SRE / 5명 이하 팀 — Minimal Viable Alerting Set

**페이저는 7개만**. 나머지는 모두 Slack로:

1. KubeAPIDown
2. KubeNodeNotReady
3. KubePersistentVolumeFillingUp (3% 이하)
4. etcdMembersDown
5. CertificateExpiry (7일 이내)
6. PrometheusRuleFailures (메타 알림)
7. 도메인별 1-2개 (이 repo의 rpc-mixin 같은 것)

**근거**: Google SRE Workbook의 "Alerting on SLOs"와 Prometheus 공식 alerting practices가 공통적으로 강조하는 것 — *"한 사람이 처리할 수 있는 양이 곧 알림의 가치 상한"*. 페이저 알림 8개를 넘기면 fatigue로 신호와 noise를 구분 못 함.

소규모 팀은:
- multi-burn-rate SLO 알림 **나중에** (먼저는 단순 임계값)
- warning 채널을 별도 슬랙 채널로 분리해서 멘션 안 되게 (`#alerts-warn-mute`)
- on-call rotation 자동화 (PagerDuty의 schedule)보다 **알림 줄이기**가 우선

### 대규모 팀 — 도메인별 라우팅

- `team` 라벨로 PagerDuty escalation 분리 (`platform-team`, `data-team`)
- SLO multi-burn-rate (5m+1h, 30m+6h, 2h+1d, 6h+3d 4단계)
- 알림 → Linear/Jira 자동 티켓 생성
- 알림 트렌드 분석 대시보드 (어떤 알림이 가장 자주 발화하는지)

출처: [Last9 — Kubernetes Alerting That Won't Burn You Out](https://last9.io/blog/kubernetes-alerting/), [HeyOnCall — Minimalistic Monitoring](https://heyoncall.com/guides/minimalistic-monitoring-and-alerting-for-your-kubernetes-cluster-with-prometheus-and-alertmanager), [Google SRE Workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)

---

## 적용 결과 (baseline-alerts PR에서 반영)

### 비활성화된 알림 (kubernetes-mixin)
`main.libsonnet`의 `k8sDisabledAlerts`에서 `transform.disableAlerts`로 제거.

| Alert | 근거 | Issue |
|---|---|---|
| `CPUThrottlingHigh` | false positive 빈번 | [kubernetes-mixin#108](https://github.com/kubernetes-monitoring/kubernetes-mixin/issues/108) |
| `KubeHpaMaxedOut` | minReplicas==maxReplicas FP | [kubernetes-mixin#1193](https://github.com/kubernetes-monitoring/kubernetes-mixin/issues/1193) |
| `KubeAPIErrorBudgetBurn` | metric 정의 결함 | [kube-prometheus#1480](https://github.com/prometheus-operator/kube-prometheus/issues/1480) |
| `KubeProxyDown` | PodMonitor 디폴트 OFF, always firing | [kube-prometheus#1602](https://github.com/prometheus-operator/kube-prometheus/issues/1602) |
| `KubeJobFailed` | CronJob retry 노이즈 | — |
| `KubeContainerWaiting` | Pod startup 잠시 waiting은 정상 | — |
| `KubePodNotScheduled` | KubePodNotReady와 신호 중복 | — |

운영 환경 fork에서 `KubeProxyDown`을 다시 켜야 하는 경우(PodMonitor를 ON 한 환경) — `main.libsonnet`의 disable 리스트에서 한 줄 삭제.

### 추가된 자체 알림 (`components/prometheus/alerts.libsonnet`)

**1차 (베이스라인 PR)**: critical 5 + warning 5
**2차 (워크로드+네트워크 보강 PR, 2026-05-07)**: critical 1 + warning 6 추가

자세한 표현식은 [alerts.libsonnet](../components/prometheus/alerts.libsonnet).

| Alert | Severity | 룬북 | PR |
|---|---|---|---|
| `PrometheusRuleFailures` | critical | [📖](runbooks/PrometheusRuleFailures.md) | 1차 |
| `AlertmanagerConfigInconsistent` | critical | [📖](runbooks/AlertmanagerConfigInconsistent.md) | 1차 |
| `IngressControllerDown` | critical | [📖](runbooks/IngressControllerDown.md) | 1차 |
| `CoreDNSDown` | critical | [📖](runbooks/CoreDNSDown.md) | 1차 |
| `HighOOMKillRate` | critical | [📖](runbooks/HighOOMKillRate.md) | 1차 |
| `NodeConntrackNearLimit` | critical | [📖](runbooks/NodeConntrackNearLimit.md) | **2차** |
| `HighIngress5xxRate` | warning | — | 1차 |
| `CoreDNSLatencyHigh` | warning | — | 1차 |
| `CoreDNSErrorsHigh` | warning | — | 1차 |
| `HighDiskSaturation` | warning | — | 1차 |
| `HighImagePullBackOff` | warning | — | 1차 |
| `HighIngress4xxRate` | warning | — | **2차** |
| `PodRestartingTooOften` | warning | — | **2차** |
| `WorkloadRolloutStuck` | warning | — | **2차** |
| `JobFailedNonCron` | warning | — | **2차** |
| `ServiceEndpointsEmpty` | warning | — | **2차** |
| `NodeNetworkErrorsHigh` | warning | — | **2차** |

### 2차 PR — 워크로드 + 네트워크 보강 의사결정 (2026-05-07)

**원칙**: "포괄성 우선" — 한 알림이 여러 원인을 한 번에 잡는다. 원인별로 알림 쪼개지 않는다.

| 결정 | 선택 | 근거 |
|---|---|---|
| `KubePodNotReady` 대체 알림 자체 작성? | ❌ 안 함 | kubernetes-mixin 표준 그대로 사용. 신호 동일, 유지보수 외주화. |
| Z-score 통계 알림 (TrafficAnomaly) | ❌ 이번 PR 미포함 | 환경별 baseline 학습 필요 — 템플릿이 강제로 켜기 부적절. 후속 PR에서 docs 가이드만. |
| cert-manager-mixin 활성화 | ❌ 이번 PR 미포함 | 사용자 환경에 cert-manager + ServiceMonitor 설치 필요. [user-environment-deps.md](user-environment-deps.md)로 추적. |
| CoreDNS 임계값 조정 (1s→4s, 5%→3%) | ❌ 이번 PR 미포함 | mixin 표준값과 노이즈 트레이드오프 — 사용자 환경별 검증 후 별도 PR. |

**2차 PR 신규 알림 도메인 매핑**

| 도메인 | 알림 | 잡는 것 |
|---|---|---|
| 워크로드 헬스 | `PodRestartingTooOften` | CrashLoopBackOff 진입 전 단계 (KubePodCrashLooping 보완) |
| 워크로드 헬스 | `WorkloadRolloutStuck` | 잘못된 이미지 배포 후 방치 (KubeDeploymentReplicasMismatch 보완) |
| 워크로드 헬스 | `JobFailedNonCron` | 1회성 Job 실패 (KubeJobFailed disable의 빈자리) |
| 워크로드 헬스 | `ServiceEndpointsEmpty` | selector 미스 / Pod 없음 / readiness 실패 통합 |
| 네트워크 — 노드 | `NodeConntrackNearLimit` | conntrack 고갈 — Preply/loveholidays 직접 원인 |
| 네트워크 — 노드 | `NodeNetworkErrorsHigh` | NIC 에러/드롭 — 드라이버/하드웨어/스위치 통합 |
| 네트워크 — ingress | `HighIngress4xxRate` | 4xx 급증 — 배포 직후 인증/route 깨짐 |

### 정책 강제 (`components/_lib/transform.libsonnet`)
- 자체 mixin: severity ∈ {critical, warning} 위반 시 jsonnet 빌드 실패. critical은 runbook_url 필수.
- 외부 mixin: 위반 목록을 `manifests/prometheus-rules-meta/external-policy-report.yaml` ConfigMap에 export (visibility만).

### 보완 의무
- `KubeAPIErrorBudgetBurn` 비활성화 → API server SLO 시그널 사라짐. 4차 PR(Alertmanager) 또는 그 이후 자체 multi-burn-rate SLO 알림 필요.
- 자체 mixin의 selector(`corednsSelector`, `ingressControllerSelector` 등)는 kube-prometheus-stack 디폴트 라벨 가정. fork 환경이 다른 차트면 `config.libsonnet`에서 override.
- 시나리오 e2e(실제 클러스터에서 알림 발화 단언)는 후속 PR에서 추가.

---

## 우리 repo에 어떻게 적용할까

### 단기 (다음 PR 또는 베이스라인 PR)
1. `components/prometheus/` 신규 — 위 #4의 추가 베이스라인 알림(certs, DNS, ingress, OOMKill, PrometheusRuleFailures)
2. `components/_external/kubernetes.libsonnet`에서 위 #3의 noisy 알림 disable + downgrade
3. `docs/runbooks/` — 위 critical 7-10개에 대한 룬북 stub

### 중기 (4차 PR — Alertmanager 라우팅)
4. `main.libsonnet`에 AlertmanagerConfig CR 출력 추가
5. 위 #5의 inhibit_rules + severity 라우팅 그대로 코드화
6. `amtool config routes test`로 critical 알림이 정확히 PagerDuty로 가는지 단위 검증

### 장기 (그 이후)
7. SLO 기반 multi-burn-rate (apiserver availability, custom service SLO)
8. 알림 발화 통계 → Grafana 대시보드 (어떤 알림이 too noisy인지 데이터로 판단)

---

## 출처

### 공식 / 표준
1. [Prometheus — Alerting Best Practices](https://prometheus.io/docs/practices/alerting/)
2. [Google SRE Workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
3. [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
4. [kubernetes-mixin runbooks](https://github.com/kubernetes-monitoring/kubernetes-mixin/blob/master/runbook.md)
5. [kube-prometheus runbooks](https://runbooks.prometheus-operator.dev/)
6. [cert-manager Prometheus metrics](https://cert-manager.io/docs/devops-tips/prometheus-metrics/)
7. [monitoring.mixins.dev](https://monitoring.mixins.dev/) — mixin 허브

### 이슈 / 토론 (실무 합의)
8. [kube-prometheus #1480 — KubeAPIErrorBudgetBurn metric definition flaw](https://github.com/prometheus-operator/kube-prometheus/issues/1480)
9. [helm-charts #5114 — KubeAPIErrorBudgetBurn false positive after 67.x](https://github.com/prometheus-community/helm-charts/issues/5114)
10. [helm-charts #2704 — disabling KubeAPIErrorBudgetBurn](https://github.com/prometheus-community/helm-charts/issues/2704)
11. [kubernetes-mixin #108 — CPUThrottlingHigh false positives](https://github.com/kubernetes-monitoring/kubernetes-mixin/issues/108)
12. [kubernetes-mixin #1193 — KubeHpaMaxedOut false positives](https://github.com/kubernetes-monitoring/kubernetes-mixin/issues/1193)
13. [kubernetes-mixin #464 — KubeAPIErrorBudgetBurn 이해](https://github.com/kubernetes-monitoring/kubernetes-mixin/issues/464)
14. [kube-prometheus PrometheusRuleFailures runbook](https://github.com/prometheus-operator/kube-prometheus/wiki/prometheusrulefailures)

### 가이드 / 사례
15. [Last9 — Kubernetes Alerting That Won't Burn You Out](https://last9.io/blog/kubernetes-alerting/)
16. [HeyOnCall — Minimalistic Monitoring and Alerting](https://heyoncall.com/guides/minimalistic-monitoring-and-alerting-for-your-kubernetes-cluster-with-prometheus-and-alertmanager)
17. [Grafana Labs — Kubernetes Monitoring backend 2.2 (2025-07)](https://grafana.com/blog/2025/07/15/kubernetes-monitoring-backend-2.2-better-cluster-observability-through-new-alert-and-recording-rules/)
18. [Better Stack — Solving Alert Fatigue](https://betterstack.com/community/guides/monitoring/best-practices-alert-fatigue/)
19. [Awesome Prometheus Alerts](https://samber.github.io/awesome-prometheus-alerts/) — 940+ 룰 모음
20. [DataOps.tech — Routing alerts by severity](https://medium.com/dataops-tech/routing-alerts-in-slack-pagerduty-by-severity-so-noise-doesnt-kill-you-874060ef2996)
21. [Mux — When Good Certificates Go Bad](https://www.mux.com/blog/when-good-certificates-go-bad-monitoring-for-expired-tls-certificates)
