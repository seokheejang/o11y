// AlertmanagerConfig CR ↔ raw alertmanager.yml 변환.
//
// 왜 이게 필요한가:
//   AlertmanagerConfig CR(monitoring.coreos.com/v1alpha1)의 spec은 raw alertmanager.yml과
//   필드명이 다르다. operator가 watch해서 alertmanager.yml로 컴파일해주는 구조.
//   amtool은 raw 형식만 받으므로 라우팅을 amtool로 검증하려면 같은 데이터로 raw도 만들어야 한다.
//
// API:
//   toRawRoute(crRoute)        — CR Route → raw route (recursive on .routes)
//   toRawInhibitRule(crRule)   — CR InhibitRule → raw inhibit_rule
//   toRawReceiver(crRcv)       — CR Receiver → raw receiver (slack/pagerduty/webhook 필드 매핑)
//   toRawConfig(crSpec, opts)  — 전체 spec → raw alertmanager 설정 객체
//
// raw 형식 매핑 (CR → raw):
//   matchers[{name,value,matchType}] → matchers["name<op>value", ...]  (alertmanager v0.22+ 통합 문법)
//   groupBy → group_by
//   groupWait → group_wait
//   groupInterval → group_interval
//   repeatInterval → repeat_interval
//   muteTimeIntervals → mute_time_intervals
//   activeTimeIntervals → active_time_intervals
//   sourceMatch → source_matchers (matcher 문자열 배열)
//   targetMatch → target_matchers
//   slackConfigs → slack_configs (apiURL SecretKeySelector → api_url placeholder URL)
//   pagerdutyConfigs → pagerduty_configs (routingKey SecretKeySelector → routing_key placeholder)
//   webhookConfigs → webhook_configs (urlSecret SecretKeySelector → url placeholder URL)
//
// raw placeholder URL/key:
//   amtool check-config는 api_url/url을 syntax(URL 형식)만 검증한다. CR의 SecretKeySelector를
//   amtool에 전달할 수는 없으므로 raw 변환 시 placeholder를 박는다. AlertmanagerConfig CR 쪽엔
//   SecretKeySelector가 그대로 살아 있으므로 클러스터 동작에는 영향 없음.

local matcherOp(matchType) =
  if matchType == '=' then '='
  else if matchType == '!=' then '!='
  else if matchType == '=~' then '=~'
  else if matchType == '!~' then '!~'
  else error 'unknown matchType: %s' % matchType;

local matcherToString(m) =
  '%s%s"%s"' % [m.name, matcherOp(m.matchType), m.value];

local matchersToStrings(ms) = [matcherToString(m) for m in ms];

{
  toRawRoute(r):: std.prune({
    receiver: if std.objectHasAll(r, 'receiver') then r.receiver else null,
    matchers: if std.objectHasAll(r, 'matchers') then matchersToStrings(r.matchers) else null,
    group_by: if std.objectHasAll(r, 'groupBy') then r.groupBy else null,
    group_wait: if std.objectHasAll(r, 'groupWait') then r.groupWait else null,
    group_interval: if std.objectHasAll(r, 'groupInterval') then r.groupInterval else null,
    repeat_interval: if std.objectHasAll(r, 'repeatInterval') then r.repeatInterval else null,
    mute_time_intervals: if std.objectHasAll(r, 'muteTimeIntervals') then r.muteTimeIntervals else null,
    active_time_intervals: if std.objectHasAll(r, 'activeTimeIntervals') then r.activeTimeIntervals else null,
    'continue': if std.objectHasAll(r, 'continue') then r['continue'] else null,
    routes: if std.objectHasAll(r, 'routes') then [$.toRawRoute(child) for child in r.routes] else null,
  }),

  toRawInhibitRule(rule):: {
    source_matchers: matchersToStrings(rule.sourceMatch),
    target_matchers: matchersToStrings(rule.targetMatch),
    equal: rule.equal,
  },

  // raw 검증용 placeholder. SecretKeySelector를 amtool에 전달할 수 없으므로
  // 도메인 형식만 맞춘 가짜 URL/key를 박는다. CR(클러스터에 sync되는 것) 쪽엔 영향 없음.
  local placeholderSlackURL = 'https://hooks.slack.com/services/PLACEHOLDER/PLACEHOLDER/PLACEHOLDER',
  local placeholderWebhookURL = 'https://example.com/webhook-placeholder',
  local placeholderRoutingKey = 'PLACEHOLDER_ROUTING_KEY',

  toRawSlackConfig(sc):: std.prune({
    // apiURL은 CR에서 SecretKeySelector이므로 raw에 그대로 못 넣는다 → placeholder.
    api_url: placeholderSlackURL,
    send_resolved: if std.objectHasAll(sc, 'sendResolved') then sc.sendResolved else null,
    channel: if std.objectHasAll(sc, 'channel') then sc.channel else null,
    username: if std.objectHasAll(sc, 'username') then sc.username else null,
    color: if std.objectHasAll(sc, 'color') then sc.color else null,
    title: if std.objectHasAll(sc, 'title') then sc.title else null,
    text: if std.objectHasAll(sc, 'text') then sc.text else null,
    icon_emoji: if std.objectHasAll(sc, 'iconEmoji') then sc.iconEmoji else null,
    icon_url: if std.objectHasAll(sc, 'iconURL') then sc.iconURL else null,
    short_fields: if std.objectHasAll(sc, 'shortFields') then sc.shortFields else null,
    footer: if std.objectHasAll(sc, 'footer') then sc.footer else null,
    link_names: if std.objectHasAll(sc, 'linkNames') then sc.linkNames else null,
    mrkdwn_in: if std.objectHasAll(sc, 'mrkdwnIn') then sc.mrkdwnIn else null,
  }),

  toRawPagerdutyConfig(pc):: std.prune({
    send_resolved: if std.objectHasAll(pc, 'sendResolved') then pc.sendResolved else null,
    // routingKey/serviceKey 둘 다 SecretKeySelector → placeholder.
    routing_key:
      if std.objectHasAll(pc, 'routingKey') then placeholderRoutingKey
      else null,
    service_key:
      if std.objectHasAll(pc, 'serviceKey') then placeholderRoutingKey
      else null,
    url: if std.objectHasAll(pc, 'url') then pc.url else null,
    client: if std.objectHasAll(pc, 'client') then pc.client else null,
    client_url: if std.objectHasAll(pc, 'clientURL') then pc.clientURL else null,
    description: if std.objectHasAll(pc, 'description') then pc.description else null,
    severity: if std.objectHasAll(pc, 'severity') then pc.severity else null,
  }),

  toRawWebhookConfig(wc):: std.prune({
    send_resolved: if std.objectHasAll(wc, 'sendResolved') then wc.sendResolved else null,
    // url은 CR에선 string, urlSecret은 SecretKeySelector. urlSecret만 있으면 placeholder.
    url:
      if std.objectHasAll(wc, 'url') then wc.url
      else if std.objectHasAll(wc, 'urlSecret') then placeholderWebhookURL
      else placeholderWebhookURL,
    max_alerts: if std.objectHasAll(wc, 'maxAlerts') then wc.maxAlerts else null,
  }),

  // Receiver를 raw로 변환. 채워진 *Configs 필드만 매핑하고, 비어있으면 누락.
  // name만 있는 placeholder receiver (예: 'null', 'pager')는 그대로 통과 — amtool check-config는
  // 정의된 receiver를 routing에서 참조만 하면 통과한다 (endpoint 없어도 합법).
  toRawReceiver(r):: std.prune({
    name: r.name,
    slack_configs:
      if std.objectHasAll(r, 'slackConfigs') && std.length(r.slackConfigs) > 0
      then [$.toRawSlackConfig(sc) for sc in r.slackConfigs] else null,
    pagerduty_configs:
      if std.objectHasAll(r, 'pagerdutyConfigs') && std.length(r.pagerdutyConfigs) > 0
      then [$.toRawPagerdutyConfig(pc) for pc in r.pagerdutyConfigs] else null,
    webhook_configs:
      if std.objectHasAll(r, 'webhookConfigs') && std.length(r.webhookConfigs) > 0
      then [$.toRawWebhookConfig(wc) for wc in r.webhookConfigs] else null,
  }),

  // 전체 spec을 raw 설정으로. global은 placeholder (resolve_timeout만).
  toRawConfig(spec, opts={}):: {
    global: {
      resolve_timeout: '5m',
    } + (if std.objectHasAll(opts, 'global') then opts.global else {}),
    route: $.toRawRoute(spec.route),
    receivers: [$.toRawReceiver(r) for r in spec.receivers],
    [if std.objectHasAll(spec, 'inhibitRules') && std.length(spec.inhibitRules) > 0 then 'inhibit_rules']:
      [$.toRawInhibitRule(rule) for rule in spec.inhibitRules],
  },
}
