# components/grafana

자체 Grafana 대시보드 컴포넌트. **현재 비어 있음** (placeholder).

## 왜 비어 있나

kube-prometheus-stack chart가 디폴트로 kubernetes-mixin 출처의 대시보드를 자동 import하므로 중복 회피.

## 채워질 시점

자체 도메인 대시보드(예: `rpc`, `ingress`)는 그 도메인 컴포넌트의 `grafanaDashboards`로 만든다. 이 디렉토리는 도메인 공통의 grafonnet 헬퍼나 panel library가 필요해질 때 채운다.

## entry point 컨벤션

`mixin.libsonnet`이 `grafanaDashboards+:: { '<name>': {...} }`로 export 하면 `main.libsonnet`이 `manifests/grafana-dashboards/<name>.yaml` (Grafana sidecar가 watch 하는 ConfigMap)로 렌더한다.
