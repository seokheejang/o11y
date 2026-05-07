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

  // Receiver는 환경별 fork에서 채우는 placeholder를 그대로 통과시킨다.
  // amtool config check가 통과하려면 최소한 name 필드만 있어도 충분 (실제 endpoint
  // 없는 receiver는 silently drop 되는 합법적 구성).
  toRawReceiver(r)::
    // CR field가 비어있으면 그대로 (name만), 채워져 있으면 raw 키로 매핑.
    // 현재 baseline은 name만 사용 — 실제 채워질 때 매핑 추가.
    r,

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
