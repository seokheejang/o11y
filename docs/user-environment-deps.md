# User Environment Dependencies

> 이 repo는 **콘텐츠 레이어 템플릿**이다. 알림이 정상 동작하려면 사용자 클러스터에 추가 설치/설정이 필요한 항목들을 모아둔 트래커.
> 새 알림이 외부 컴포넌트나 ServiceMonitor에 의존하면 이 문서에 항목을 추가한다.

## How to read this

| 컬럼 | 의미 |
|---|---|
| **Component** | 사용자가 설치/설정해야 하는 것 |
| **Why** | 어떤 알림/대시보드가 의존하는가 |
| **Status in repo** | 현재 repo가 이걸 켜고 있는가 |
| **How to enable in fork** | fork 사용자가 어떻게 활성화하는가 |

## Tracker

### cert-manager + ServiceMonitor

| 항목 | 값 |
|---|---|
| Component | cert-manager controller + ServiceMonitor (포트 9402 스크랩) |
| Why | `mixins/external/cert-manager.libsonnet` mixin 활성화 시 — `CertManagerCertExpirySoon` (30d/7d), `CertManagerCertNotReady` 등 |
| Status in repo | ❌ wrap stub만 있음, 디폴트 OFF |
| How to enable in fork | (1) cert-manager 설치 (Helm), (2) cert-manager Service에 `prometheus.io/scrape: "true"` annotation 또는 ServiceMonitor 직접 생성, (3) `mixins/main.libsonnet`의 `certManagerEnabled: false` → `true`, (4) `jb install github.com/imusmanmalik/cert-manager-mixin@master`, (5) `make all` |

### kube-proxy ServiceMonitor (재활성화 후보)

| 항목 | 값 |
|---|---|
| Component | kube-proxy ServiceMonitor (kube-prometheus-stack values에서 활성화) |
| Why | kubernetes-mixin `KubeProxyDown` 알림 재활성화 |
| Status in repo | ❌ disable됨 ([kube-prometheus#1602](https://github.com/prometheus-operator/kube-prometheus/issues/1602) — PodMonitor OFF, always firing) |
| How to enable in fork | kube-prometheus-stack values에서 `kubeProxy.enabled: true` + kube-proxy의 metrics bind address 0.0.0.0 변경. 그 후 `mixins/main.libsonnet`의 `k8sDisabledAlerts`에서 `KubeProxyDown` 줄 삭제. |

### CoreDNS 임계값 mixin 표준 적용

| 항목 | 값 |
|---|---|
| Component | 환경별 트래픽 baseline 검증 후 임계값 조정 |
| Why | 현재 `CoreDNSLatencyHigh: p99 > 1s`, `CoreDNSErrorsHigh: ratio > 5%`. CoreDNS mixin 표준은 4s / 3%. |
| Status in repo | ⚠️ 자체값(빡빡함) 적용 중 — dev/staging에서 노이즈 가능성 |
| How to enable in fork | 환경에서 1주 메트릭 수집 후 p99/error ratio 분포 확인, `mixins/local/baseline-mixin/config.libsonnet` thresholds 조정 |

### Ingress NGINX metrics

| 항목 | 값 |
|---|---|
| Component | ingress-nginx controller `--enable-metrics=true` (디폴트) + ServiceMonitor |
| Why | `HighIngress5xxRate`, `HighIngress4xxRate` |
| Status in repo | ✅ selector는 standard 라벨 가정 (`job=~"ingress-nginx-controller-metrics\|nginx-ingress.*"`) |
| How to enable in fork | ingress controller가 다른 차트면 `mixins/local/baseline-mixin/config.libsonnet`의 `ingressControllerSelector` override |

### node-exporter (conntrack / NIC 메트릭)

| 항목 | 값 |
|---|---|
| Component | node-exporter `--collector.netdev`, `--collector.conntrack` (디폴트 ON) |
| Why | `NodeConntrackNearLimit`, `NodeNetworkErrorsHigh` |
| Status in repo | ✅ kube-prometheus-stack 디폴트 가정 |
| How to enable in fork | 별도 작업 없음. `nodeExporterSelector`만 환경에 맞게 override (`config.libsonnet`) |

### kube-state-metrics (워크로드 메트릭)

| 항목 | 값 |
|---|---|
| Component | kube-state-metrics |
| Why | `PodRestartingTooOften`, `WorkloadRolloutStuck`, `JobFailedNonCron`, `ServiceEndpointsEmpty` |
| Status in repo | ✅ kube-prometheus-stack 디폴트 |
| How to enable in fork | `kubeStateMetricsSelector` override |

### blackbox_exporter (선택, 외부 의존성 모니터링)

| 항목 | 값 |
|---|---|
| Component | blackbox_exporter |
| Why | 외부 API timeout/5xx, TLS 만료 (cert-manager 미사용 시 대체) |
| Status in repo | ❌ 없음 |
| How to enable in fork | 별도 PR 필요 — 현재 베이스라인 범위 밖 |

### NodeLocal DNSCache (conntrack 완화)

| 항목 | 값 |
|---|---|
| Component | NodeLocal DNSCache DaemonSet |
| Why | `NodeConntrackNearLimit` 발화 시 완화책 (UDP DNS race 회피) — 알림이 아니라 mitigation |
| Status in repo | N/A (런북 권장 사항) |
| How to enable in fork | [공식 가이드](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/) — 알림과 무관, 인프라 영역 |

## 추가 정책

신규 알림 PR을 올릴 때 **새 외부 컴포넌트 의존성이 생기면 반드시 이 표에 한 줄 추가**한다. fork 사용자가 활성화 절차를 한 곳에서 찾을 수 있도록 한다.
