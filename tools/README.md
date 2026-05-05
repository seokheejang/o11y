# tools/

빌드·검증 헬퍼 스크립트가 들어갈 자리.

다음 PR에서 추가 예정:
- `gen-configmap.sh` — Grafana 대시보드 JSON을 `kube-prometheus-stack` Grafana sidecar용 ConfigMap(`grafana_dashboard: "1"` 라벨)으로 변환
- `render-rules.sh` — jsonnet 빌드 산출물을 `PrometheusRule` CR로 감싸 `manifests/prometheus-rules/`에 배치
- `validate.sh` — `promtool test rules` + `kubeconform` 일괄 실행

지금은 placeholder.
