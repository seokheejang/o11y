// Grafana 컴포넌트 진입점 (placeholder).
//
// 자체 대시보드는 `grafanaDashboards`로 export 한다 (kube-prometheus jsonnet 컨벤션).
// 현재 비어 있음 — kube-prometheus-stack chart가 디폴트로 import 하는
// kubernetes-mixin 대시보드를 그대로 쓰기 위함. 도메인별 대시보드(rpc, ingress 등)는
// 후속에 추가.

{
  grafanaDashboards+:: {},
}
