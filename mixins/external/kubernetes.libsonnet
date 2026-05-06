// kubernetes-mixin import + 환경 셀렉터 override.
// kube-prometheus-stack 기본 라벨에 맞춰 selector를 정렬한다.

(import 'github.com/kubernetes-monitoring/kubernetes-mixin/mixin.libsonnet') +
{
  _config+:: {
    cadvisorSelector: 'job="kubelet", metrics_path="/metrics/cadvisor"',
    kubeletSelector: 'job="kubelet", metrics_path="/metrics"',
    kubeStateMetricsSelector: 'job="kube-state-metrics"',
    nodeExporterSelector: 'job="node-exporter"',
    kubeApiserverSelector: 'job="apiserver"',
    kubeControllerManagerSelector: 'job="kube-controller-manager"',
    kubeSchedulerSelector: 'job="kube-scheduler"',
    kubeProxySelector: 'job="kube-proxy"',
    grafanaK8s+:: {
      dashboardNamePrefix: 'Kubernetes / ',
      dashboardTags: ['kubernetes-mixin'],
    },
  },
}
