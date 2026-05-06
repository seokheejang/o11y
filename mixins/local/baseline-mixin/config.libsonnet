// kube-prometheus-stack 디폴트 라벨에 맞춘 셀렉터.
// 환경별 fork에서는 main.libsonnet의 baseline 합성 시점에 _config+:: 로 override.

{
  _config+:: {
    // job 라벨 — kube-prometheus-stack ServiceMonitor가 만드는 디폴트 값
    prometheusOperatorSelector: 'job=~"kps-kube-prometheus-stack-operator|prometheus-operator"',
    alertmanagerSelector: 'job=~"alertmanager-main|kps-kube-prometheus-stack-alertmanager"',
    corednsSelector: 'job=~"kube-dns|coredns"',
    ingressControllerSelector: 'job=~"ingress-nginx-controller-metrics|nginx-ingress.*"',
    nodeExporterSelector: 'job="node-exporter"',
    kubeStateMetricsSelector: 'job="kube-state-metrics"',

    // runbook URL prefix — github.com:owner/repo의 runbooks 경로
    runbookBase: 'https://github.com/seokheejang/o11y/blob/main/docs/runbooks',

    // 임계값
    thresholds: {
      coreDNSp99LatencySeconds: 1,
      coreDNSErrorRatio: 0.05,
      ingress5xxRatio: 0.05,
      diskSaturationRatio: 0.9,
      oomKillRate5m: 3,  // 5분 동안 OOM 3건 이상이면 critical
    },
  },
}
