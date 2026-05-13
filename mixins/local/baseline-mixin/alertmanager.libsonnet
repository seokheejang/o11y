// Baseline Alertmanager routing — severity 2단계 + 핵심 inhibit_rules.
//
// docs/severity-policy.md "Alertmanager 라우팅 정합" 절의 설계를 그대로 옮겼다.
//
// 이 파일은 **routing intent** (도메인 객체)만 정의한다.
// CR/raw alertmanager.yml 두 형식 변환은 mixins/lib/alertmanager.libsonnet 헬퍼가 한다.
//
// 단일 source-of-truth 원칙: receiver 이름/severity 매처/inhibit 키는 여기 한 곳만 수정.
//
// receiver 이름은 placeholder. 실제 webhook/PagerDuty Secret 연결은 후속 PR에서 처리한다.
// 디폴트 receiver "null" — 매치되지 않은 알림은 silently drop (Alertmanager 컨벤션).

{
  // === Receiver 정의 ===
  // 실제 endpoint는 환경별 fork에서 webhookConfigs/slackConfigs/pagerdutyConfigs로 채운다.
  // 여기서는 "null receiver" + 빈 webhook placeholder만 둔다 — amtool config check가
  // 통과할 수 있는 최소 구조.
  local receivers = [
    { name: 'null' },                  // catch-all drop
    { name: 'pager' },                 // critical → PagerDuty/Opsgenie
    { name: 'critical-chat' },         // critical → Slack #alerts-critical
    { name: 'warning-chat' },          // warning → Slack #alerts-warning
  ],

  // === Routing tree ===
  // docs/severity-policy.md 정합:
  //   route:
  //     group_by: [alertname, cluster, namespace]
  //     group_wait: 30s, group_interval: 5m, repeat_interval: 4h
  //     receiver: null
  //     routes:
  //       - severity=critical, continue=true → pager (repeat 1h)
  //       - severity=critical               → critical-chat
  //       - severity=warning                → warning-chat (repeat 12h)
  //
  // 비어있지 않은 (severity, receiver) 매핑이 명시적이라는 게 정책의 핵심:
  // severity가 critical/warning이 아닌 알림은 null로 떨어진다 (drop).
  // PrometheusRule 빌드 시 severity 라벨을 강제하므로 이 분기는 사실상 unreachable이지만,
  // Alertmanager가 외부 소스(다른 클러스터, 외부 webhook)로부터 받는 알림에 대한 안전망.
  local rootRoute = {
    groupBy: ['alertname', 'cluster', 'namespace'],
    groupWait: '30s',
    groupInterval: '5m',
    repeatInterval: '4h',
    receiver: 'null',
    routes: [
      // critical → pager + chat (둘 다 발송, continue=true로 다음 매처도 평가)
      {
        matchers: [{ name: 'severity', value: 'critical', matchType: '=' }],
        receiver: 'pager',
        repeatInterval: '1h',
        continue: true,
      },
      {
        matchers: [{ name: 'severity', value: 'critical', matchType: '=' }],
        receiver: 'critical-chat',
      },
      // warning → chat only
      {
        matchers: [{ name: 'severity', value: 'warning', matchType: '=' }],
        receiver: 'warning-chat',
        repeatInterval: '12h',
      },
    ],
  },

  // === Inhibit rules ===
  // critical이 발화 중이면 같은 (alertname, cluster, namespace) 묶음의 warning은 묵음.
  // 이중 알림 회피의 표준 패턴 (Alertmanager 공식 예제).
  //
  // 두 번째 룰: KubeNodeNotReady 발화 시 그 노드의 모든 Pod-level 알림은 묵음.
  //   노드 다운 한 건이 KubePodNotReady/KubeContainerWaiting 등을 수십 개 trigger하는 폭주 차단.
  //   (kubernetes-mixin에서 KubeContainerWaiting을 disable했지만, 외부 mixin/수동 알림 보호용)
  local inhibitRules = [
    {
      sourceMatch: [{ name: 'severity', value: 'critical', matchType: '=' }],
      targetMatch: [{ name: 'severity', value: 'warning', matchType: '=' }],
      equal: ['alertname', 'cluster', 'namespace'],
    },
    {
      sourceMatch: [{ name: 'alertname', value: 'KubeNodeNotReady', matchType: '=' }],
      targetMatch: [{ name: 'severity', value: 'warning', matchType: '=' }],
      equal: ['cluster', 'node'],
    },
  ],

  // mixin 진입점이 읽는 키. main.libsonnet에서
  //   if std.objectHasAll(m, 'alertmanagerConfig') ... 로 detect.
  alertmanagerConfig+:: {
    route: rootRoute,
    receivers: receivers,
    inhibitRules: inhibitRules,
  },
}
