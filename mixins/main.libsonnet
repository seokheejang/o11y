// 빌드 진입점. tools/build.sh가 jsonnet -m으로 호출.
// top-level object의 키 이름이 곧 manifests/ 아래 산출 경로가 된다.
//   ['prometheus-rules/<name>']  -> manifests/prometheus-rules/<name>.yaml
//   ['grafana-dashboards/<name>']-> manifests/grafana-dashboards/<name>.yaml

local wrappers = import 'lib/wrappers.libsonnet';
local k8s = import 'external/kubernetes.libsonnet';

local mixin = k8s;

local ruleGroups =
  (if std.objectHasAll(mixin, 'prometheusAlerts') && std.objectHasAll(mixin.prometheusAlerts, 'groups')
   then mixin.prometheusAlerts.groups else []) +
  (if std.objectHasAll(mixin, 'prometheusRules') && std.objectHasAll(mixin.prometheusRules, 'groups')
   then mixin.prometheusRules.groups else []);

{
  ['prometheus-rules/kubernetes']: wrappers.wrapPrometheusRule(
    name='kubernetes',
    groups=ruleGroups,
  ),
} + {
  ['grafana-dashboards/' + std.strReplace(name, '.json', '')]:
    wrappers.wrapDashboardConfigMap(
      name=std.strReplace(name, '.json', ''),
      dashboard=mixin.grafanaDashboards[name],
    )
  for name in (
    if std.objectHasAll(mixin, 'grafanaDashboards')
    then std.objectFields(mixin.grafanaDashboards)
    else []
  )
}
