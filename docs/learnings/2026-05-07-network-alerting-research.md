# 2026-05-07 — Workload + Network Alerting Research

> Best-practice 리서치 결과 박제. PR `feat/workload-network-alerts`의 의사결정 근거.

## Why this note exists

베이스라인 PR(2026-05-06)에서 의도적으로 미뤘던 영역 — 워크로드 헬스(개발자가 까먹은 무한 restart Pod, 이미지 못 불러옴, Job 실패 등) + 네트워크 헬스(트래픽 급증/감소, HTTP 4xx/5xx, DNS) — 을 잡기 위해 업계 표준 알림 패턴과 실무 장애 사례를 조사함.

## Frame

**Google SRE의 4 Golden Signals** — Latency / Traffic / Errors / Saturation — 가 업계 공통 출발점. 그 위에 K8s 특유 장애 패턴(conntrack, CoreDNS, ingress)을 도메인별로 보강.

| Golden Signal | K8s 장애 매핑 | 표준 PromQL |
|---|---|---|
| Traffic | spike/drop, DDoS | Z-score 또는 baseline ratio |
| Errors | HTTP 5xx, 4xx, SERVFAIL | rate(error) / rate(total) > threshold |
| Latency | DNS p99, ingress p95 | histogram_quantile + threshold |
| Saturation | conntrack full, IP 고갈, connection pool | current / max > 0.8 |

## 실무 빈도 기반 네트워크 장애 카테고리

[k8s.af](https://k8s.af/) failure stories + 트러블슈팅 가이드 종합 결과:

1. **Conntrack 고갈/race** — Preply 2020, loveholidays 2020 (직접 원인)
2. **CoreDNS 장애** — Zalando OOMKill, Alpine ndots:5 misconfig
3. **Ingress 5xx 급증** — 백엔드 다운, target group health check fail, 포트 mismatch
4. **Ingress 4xx 급증** — 배포 직후 인증/route 깨짐, client SDK 버그, bot 캠페인
5. **트래픽 spike/drop** — DDoS, 바이럴, 업스트림 장애
6. **NetworkPolicy 잘못 적용** — Egress가 kube-dns 차단 → 전 Pod DNS 실패
7. **CNI 플러그인 이슈** — Prezi (AWS CNI SNAT 지연), MindTickle packet loss
8. **IP 주소 고갈** — loveholidays GKE alias IP
9. **TLS 인증서 만료** — 정기적 사고
10. **kube-proxy/iptables 손상** — Service ClusterIP 라우팅 실패

## 업계 표준 임계값 (이 PR이 채택한 값)

| 알림 | 채택 값 | 출처 |
|---|---|---|
| HighIngress5xxRate | 5% / 10m | awesome-prometheus-alerts, Aviator, Sysdig 공통 |
| HighIngress4xxRate | 5% / 10m + 최소 1 req/s | awesome-prometheus-alerts (warning, outage 아님) |
| NodeConntrackNearLimit | 80% / 10m | k8s.af 사례 종합 |
| PodRestartingTooOften | 1h 내 5회+ / for 15m | KubePodCrashLooping 보완 — 횟수 기반 임계 |
| WorkloadRolloutStuck | for 30m | rolling update 자연 시간 고려 |

## 의도적으로 채택하지 **않은** 패턴

| 패턴 | 안 넣은 이유 |
|---|---|
| Z-score 트래픽 anomaly | 환경별 baseline 학습 1주+ 필요 — 템플릿이 강제로 켤 수 없음 |
| `PodNotHealthy` 자체 작성 | kubernetes-mixin `KubePodNotReady`로 신호 동일, 자체 작성 시 유지보수 부담 |
| HighIngress5xxRate critical | SRE 관점에서 5xx도 SLO 정책 영역 — warning 유지하고 SLO multi-burn-rate는 후속 PR |
| TrafficAnomalySpike | spike는 "사업 잘 됨"과 구분 못함, false positive 큼 |
| CNI 플러그인별 알림 | repo는 CNI 비특정 — fork 이후 사용자 영역 |

## 사용자 환경 의존 (이 PR 범위 밖)

cert-manager-mixin, kube-proxy ServiceMonitor, blackbox_exporter 등은 **사용자 클러스터에 추가 설치/설정 필요**. [user-environment-deps.md](../user-environment-deps.md)에서 추적.

## Sources

### 공식 / 표준
- [Prometheus — Alerting Best Practices](https://prometheus.io/docs/practices/alerting/)
- [Google SRE — Four Golden Signals](https://sre.google/sre-book/monitoring-distributed-systems/)
- [CoreDNS Monitoring Mixin](https://monitoring.mixins.dev/coredns/)

### 커뮤니티 / 사례
- [Kubernetes Failure Stories (k8s.af)](https://k8s.af/) — 다년간 누적 큐레이션
- [Awesome Prometheus Alerts — Nginx](https://samber.github.io/awesome-prometheus-alerts/rules/proxies-load-balancers-and-service-meshes/nginx/)
- [10 Common Kubernetes Network Errors (2026)](https://prodopshub.com/kubernetes-network-errors/)
- [How to Troubleshoot CoreDNS (oneuptime, 2026)](https://oneuptime.com/blog/post/2026-01-19-kubernetes-coredns-troubleshooting-guide/view)

### 통계 알림 (참고용, 이 PR 미적용)
- [Grafana — Anomaly Detection in Prometheus](https://grafana.com/blog/how-to-use-prometheus-to-efficiently-detect-anomalies-at-scale/)
- [Z-Score in PromQL — Omar Ghader](https://omarghader.github.io/prometheus-anomaly-detection-z-score-in-promql/)

### 벤더 블로그
- [Sysdig — Golden Signals for Kubernetes](https://www.sysdig.com/blog/golden-signals-kubernetes)
- [Aviator — Monitor NGINX Ingress](https://www.aviator.co/blog/how-to-monitor-and-alert-on-nginx-ingress-in-kubernetes/)
- [SRE School — Four Golden Signals](https://sreschool.com/blog/four-golden-signals/)
