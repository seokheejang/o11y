// Baseline mixin 진입점.
// kubernetes-mixin이 안 만드는 운영 필수 알림(메타/네트워크/DNS/워크로드)을 추가한다.
// docs/baseline-alerts.md 참고.

(import 'config.libsonnet') +
(import 'alerts.libsonnet') +
(import 'alertmanager.libsonnet')
