// Prometheus 컴포넌트 진입점.
//
// `_config`와 자체 alert 룰을 합쳐 export 한다.
//   - config.libsonnet → `_config+::` (job selectors, thresholds, runbook base)
//   - alerts.libsonnet → `prometheusAlerts.groups` (자체 운영 필수 알림)
//
// main.libsonnet이 이 컴포넌트와 alertmanager 컴포넌트를 합쳐
// 'baseline' 단위로 mixin 출력을 만든다 (변이 없음 — kube-prometheus jsonnet 컨벤션).

(import 'config.libsonnet') +
(import 'alerts.libsonnet')
