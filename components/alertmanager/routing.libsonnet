// Baseline Alertmanager routing — severity 2단계 + 핵심 inhibit_rules.
//
// docs/severity-policy.md "Alertmanager 라우팅 정합" 절의 설계를 그대로 옮겼다.
//
// 이 파일은 **routing intent** (도메인 객체)만 정의한다.
// CR/raw alertmanager.yml 두 형식 변환은 mixins/lib/alertmanager.libsonnet 헬퍼가 한다.
//
// 단일 source-of-truth 원칙: receiver 이름/severity 매처/inhibit 키는 여기 한 곳만 수정.
//
// Receiver 와이어링:
//   - pager: placeholder 유지 (PagerDuty 도입 시 pagerdutyConfigs 채움). 현재 매처는 통과하지만
//     pagerduty_configs가 없어 silent drop — routing intent는 유지.
//   - critical-chat / warning-chat: Slack 단일 채널, 동일 webhook Secret. severity는 메시지
//     color/title prefix로 구분. 추후 채널 분리 시 webhook Secret만 갈아끼우면 됨.
//
// Slack Secret 컨벤션 (환경 인프라에서 생성):
//   - 이름: `alertmanager-slack-webhook` (monitoring ns)
//   - 키: `url` → Slack incoming webhook URL
//   - 자세한 가이드: docs/severity-policy.md "Receiver 와이어링 > Slack receiver Secret" 절

{
  // === Slack 메시지 템플릿 ===
  // alertmanager Go template 문법. critical/warning이 같은 webhook을 쓰므로 title prefix와
  // color로 시각적 구분.
  local slackTitle(severityLabel) =
    '[%s] {{ .GroupLabels.alertname }}' % severityLabel +
    '{{ if .GroupLabels.namespace }} ({{ .GroupLabels.namespace }}){{ end }}',

  local slackText = |||
    {{ range .Alerts -}}
    *Severity:* `{{ .Labels.severity }}`
    *Alert:* {{ .Labels.alertname }}{{ if .Labels.namespace }} | ns: `{{ .Labels.namespace }}`{{ end }}
    {{ if .Annotations.summary }}*Summary:* {{ .Annotations.summary }}
    {{ end -}}
    {{ if .Annotations.description }}*Description:* {{ .Annotations.description }}
    {{ end -}}
    {{ if .Annotations.runbook_url }}*Runbook:* {{ .Annotations.runbook_url }}
    {{ end -}}
    ---
    {{ end }}
  |||,

  // Slack webhook Secret 참조 (환경 인프라가 monitoring ns에 생성).
  local slackSecretRef = {
    name: 'alertmanager-slack-webhook',
    key: 'url',
  },

  // === Receiver 정의 ===
  // pager는 placeholder 유지 (endpoint 없으면 silent drop — Alertmanager 합법 패턴).
  local receivers = [
    { name: 'null' },  // catch-all drop
    { name: 'pager' },  // critical → PagerDuty (도입 시 pagerdutyConfigs 채움)
    {
      name: 'critical-chat',
      slackConfigs: [{
        apiURL: slackSecretRef,
        sendResolved: true,
        color: 'danger',  // Slack 표준 red
        title: slackTitle('CRITICAL'),
        text: slackText,
      }],
    },
    {
      name: 'warning-chat',
      slackConfigs: [{
        apiURL: slackSecretRef,
        sendResolved: true,
        color: 'warning',  // Slack 표준 yellow
        title: slackTitle('WARNING'),
        text: slackText,
      }],
    },
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
