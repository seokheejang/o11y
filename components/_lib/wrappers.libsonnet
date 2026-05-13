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

  // AlertmanagerConfig CR.
  // 주의: 이 CR의 spec은 raw alertmanager.yml과 필드명이 다르다 (camelCase + 라벨).
  //   raw                    | CR
  //   ----                   | ----
  //   group_by               | groupBy
  //   group_wait             | groupWait
  //   group_interval         | groupInterval
  //   repeat_interval        | repeatInterval
  //   match: {x: y}          | matchers: [{name:x, value:y, matchType:'='}]
  //   source_match           | sourceMatch (with matchers list)
  //   target_match           | targetMatch (with matchers list)
  // amtool은 raw 형식을 받으므로 빌드 시 두 산출물을 같은 routing 객체에서 만든다.
  wrapAlertmanagerConfig(name, namespace='monitoring', route={}, receivers=[], inhibitRules=[]):: {
    apiVersion: 'monitoring.coreos.com/v1alpha1',
    kind: 'AlertmanagerConfig',
    metadata: {
      name: name,
      namespace: namespace,
      labels: {
        'app.kubernetes.io/managed-by': 'o11y',
        // kube-prometheus-stack은 디폴트로 alertmanagerConfigSelector.matchLabels.alertmanagerConfig=baseline
        // 식 셀렉터를 강제하기도 한다. 환경별 fork에서 override.
        alertmanagerConfig: name,
      },
    },
    spec: {
      route: route,
      receivers: receivers,
      [if std.length(inhibitRules) > 0 then 'inhibitRules']: inhibitRules,
    },
  },
}
