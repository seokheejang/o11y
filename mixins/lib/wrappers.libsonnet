// CR/ConfigMap wrapping helpers.
// Mixin들의 prometheusAlerts/Rules/grafanaDashboards 출력을 K8s 리소스 한 단계로 감싼다.

{
  wrapPrometheusRule(name, namespace='monitoring', groups=[]):: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: {
      name: name,
      namespace: namespace,
      labels: {
        'app.kubernetes.io/managed-by': 'o11y',
        prometheus: 'kube-prometheus',
        role: 'alert-rules',
      },
    },
    spec: { groups: groups },
  },

  wrapDashboardConfigMap(name, namespace='monitoring', dashboard={}):: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: 'grafana-dashboard-' + name,
      namespace: namespace,
      labels: {
        grafana_dashboard: '1',
        'app.kubernetes.io/managed-by': 'o11y',
      },
    },
    data: { [name + '.json']: std.manifestJsonEx(dashboard, '    ') },
  },
}
