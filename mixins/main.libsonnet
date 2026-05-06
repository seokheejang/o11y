// 빌드 진입점. tools/build.sh가 jsonnet -m으로 호출.
// top-level object의 키 이름이 곧 manifests/ 아래 산출 경로가 된다.
//   ['prometheus-rules/<name>']      -> manifests/prometheus-rules/<name>.yaml
//   ['prometheus-rules-meta/<name>'] -> manifests/prometheus-rules-meta/<name>.yaml  (정책 위반 가시화 ConfigMap)
//   ['grafana-dashboards/<name>']    -> manifests/grafana-dashboards/<name>.yaml
//
// 외부 mixin은 **rules만** 가져온다. 대시보드는 kube-prometheus-stack 차트가
// 디폴트로 같은 mixin 출처의 ConfigMap을 만들어주므로 중복 회피.
// 자체 mixin(mixins/local/*-mixin/)은 rules + dashboards를 모두 가져온다.

local wrappers = import 'lib/wrappers.libsonnet';
local transform = import 'lib/transform.libsonnet';

// === 외부 mixin: kubernetes-mixin (rules only) ===
local k8s = import 'external/kubernetes.libsonnet';

// docs/baseline-alerts.md #3 합의에 따라 비활성화하는 알림.
// 각 항목 옆 GitHub issue 링크가 disable 근거.
local k8sDisabledAlerts = [
  'CPUThrottlingHigh',          // false positive 빈번 (kubernetes-mixin#108)
  'KubeHpaMaxedOut',            // minReplicas==maxReplicas FP (kubernetes-mixin#1193)
  'KubeAPIErrorBudgetBurn',     // metric 정의 결함 (kube-prometheus#1480), 67.x FP (helm-charts#5114)
  'KubeProxyDown',              // PodMonitor 디폴트 OFF, always firing (kube-prometheus#1602)
  'KubeJobFailed',              // CronJob retry 노이즈
  'KubeContainerWaiting',       // Pod startup 잠시 waiting은 정상 — KubePodNotReady가 더 정확
  'KubePodNotScheduled',        // KubePodNotReady와 신호 중복
];

local k8sRawGroups =
  (if std.objectHasAll(k8s, 'prometheusAlerts') && std.objectHasAll(k8s.prometheusAlerts, 'groups')
   then k8s.prometheusAlerts.groups else []) +
  (if std.objectHasAll(k8s, 'prometheusRules') && std.objectHasAll(k8s.prometheusRules, 'groups')
   then k8s.prometheusRules.groups else []);

local k8sFilteredGroups = transform.disableAlerts(k8sRawGroups, k8sDisabledAlerts);

// 외부 mixin은 정책 위반 시 strict=false — 위반 목록만 visibility로 export.
local k8sViolations = transform.collectViolations(k8sFilteredGroups);

// === 외부 mixin: cert-manager (선택적, 디폴트 OFF) ===
// 활성화 절차:
//   1) jb install github.com/imusmanmalik/cert-manager-mixin@master
//   2) 아래 false → true 변경
local certManagerEnabled = false;
local cmGroups =
  if certManagerEnabled then
    local cm = import 'external/cert-manager.libsonnet';
    if std.objectHasAll(cm, 'prometheusAlerts') && std.objectHasAll(cm.prometheusAlerts, 'groups')
    then cm.prometheusAlerts.groups
    else []
  else [];

// === 자체 mixin (rules + dashboards) ===
local baseline = import 'local/baseline-mixin/mixin.libsonnet';
local localMixins = [
  { name: 'baseline', m: baseline },
];

local ruleGroupsOf(m) =
  (if std.objectHasAll(m, 'prometheusAlerts') && std.objectHasAll(m.prometheusAlerts, 'groups')
   then m.prometheusAlerts.groups else []) +
  (if std.objectHasAll(m, 'prometheusRules') && std.objectHasAll(m.prometheusRules, 'groups')
   then m.prometheusRules.groups else []);

// 자체 mixin은 strict=true — 정책 위반 시 jsonnet 빌드 실패.
local lintLocal(groups) =
  transform.requireRunbookForCritical(
    transform.requireSeverityIn(groups, allowed=['critical', 'warning'], strict=true),
    strict=true,
  );

{
  // 외부 mixin → 단일 PrometheusRule 'kubernetes'
  ['prometheus-rules/kubernetes']: wrappers.wrapPrometheusRule(
    name='kubernetes',
    groups=k8sFilteredGroups + cmGroups,
  ),
}
+ {
  // 자체 mixin → 도메인별 PrometheusRule
  ['prometheus-rules/' + entry.name]: wrappers.wrapPrometheusRule(
    name=entry.name,
    groups=lintLocal(ruleGroupsOf(entry.m)),
  )
  for entry in localMixins
  if std.length(ruleGroupsOf(entry.m)) > 0
}
+ {
  // 외부 mixin 정책 위반은 ConfigMap으로 visibility (kubeconform 호환을 위해 별도 디렉토리).
  ['prometheus-rules-meta/external-policy-report']: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: 'o11y-external-policy-report',
      namespace: 'monitoring',
      labels: {
        'app.kubernetes.io/managed-by': 'o11y',
        'app.kubernetes.io/component': 'policy-report',
      },
    },
    data: { 'violations.json': std.manifestJsonEx(k8sViolations, '  ') },
  },
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
