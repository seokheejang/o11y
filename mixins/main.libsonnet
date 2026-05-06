// 빌드 진입점. tools/build.sh가 jsonnet -m으로 호출.
// top-level object의 키 이름이 곧 manifests/ 아래 산출 경로가 된다.
//   ['prometheus-rules/<name>']  -> manifests/prometheus-rules/<name>.yaml
//   ['grafana-dashboards/<name>']-> manifests/grafana-dashboards/<name>.yaml
//
// 외부 mixin은 **rules만** 가져온다. 대시보드는 kube-prometheus-stack 차트가
// 디폴트로 같은 mixin 출처의 ConfigMap을 만들어주므로 중복 회피.
// 자체 mixin(mixins/local/*-mixin/)은 rules + dashboards를 모두 가져온다.

local wrappers = import 'lib/wrappers.libsonnet';

// === 외부 mixin (rules only) ===
local k8s = import 'external/kubernetes.libsonnet';

local externalRuleGroups =
  (if std.objectHasAll(k8s, 'prometheusAlerts') && std.objectHasAll(k8s.prometheusAlerts, 'groups')
   then k8s.prometheusAlerts.groups else []) +
  (if std.objectHasAll(k8s, 'prometheusRules') && std.objectHasAll(k8s.prometheusRules, 'groups')
   then k8s.prometheusRules.groups else []);

// === 자체 mixin (rules + dashboards) ===
// 3차 PR에서 mixins/local/rpc-mixin/ 등을 추가하면 여기 import 후 합성.
//   local rpc = import 'local/rpc-mixin/mixin.libsonnet';
//   local localMixins = [{ name: 'rpc', m: rpc }, ...];
local localMixins = [];

local ruleGroupsOf(m) =
  (if std.objectHasAll(m, 'prometheusAlerts') && std.objectHasAll(m.prometheusAlerts, 'groups')
   then m.prometheusAlerts.groups else []) +
  (if std.objectHasAll(m, 'prometheusRules') && std.objectHasAll(m.prometheusRules, 'groups')
   then m.prometheusRules.groups else []);

{
  // 외부 mixin → 단일 PrometheusRule 'kubernetes'
  ['prometheus-rules/kubernetes']: wrappers.wrapPrometheusRule(
    name='kubernetes',
    groups=externalRuleGroups,
  ),
}
+ {
  // 자체 mixin → 도메인별 PrometheusRule
  ['prometheus-rules/' + entry.name]: wrappers.wrapPrometheusRule(
    name=entry.name,
    groups=ruleGroupsOf(entry.m),
  )
  for entry in localMixins
  if std.length(ruleGroupsOf(entry.m)) > 0
}
+ {
  // 자체 mixin → 도메인별 Grafana 대시보드 ConfigMap
  ['grafana-dashboards/' + std.strReplace(name, '.json', '')]:
    wrappers.wrapDashboardConfigMap(
      name=std.strReplace(name, '.json', ''),
      dashboard=entry.m.grafanaDashboards[name],
    )
  for entry in localMixins
  if std.objectHasAll(entry.m, 'grafanaDashboards')
  for name in std.objectFields(entry.m.grafanaDashboards)
}
