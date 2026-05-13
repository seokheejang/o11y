// Alert group 가공 헬퍼.
// kubernetes-mixin은 알림 비활성화의 표준 메커니즘이 없어 jsonnet 시점에 std.filter로 처리한다.
// (lablabs.io "How we solved our need to override Prometheus alerts" 패턴)
//
// API:
//   disableAlerts(groups, names)       — 이름 매치되는 alert만 제거. record는 유지.
//   requireSeverityIn(groups, ...)     — severity 라벨이 화이트리스트에 있는지 검증.
//   requireRunbookForCritical(groups)  — critical에는 annotations.runbook_url 필수.
//   collectViolations(groups, ...)     — strict=false 모드에서 위반 목록 수집.
//
// strict=true:  위반 시 std.error로 jsonnet 빌드 실패 (자체 mixin용).
// strict=false: 위반 무시하고 groups 반환 (외부 mixin용 — collectViolations와 함께 사용).

{
  disableAlerts(groups, names):: [
    g {
      rules: [
        r
        for r in g.rules
        if !std.objectHasAll(r, 'alert') || !std.member(names, r.alert)
      ],
    }
    for g in groups
  ],

  requireSeverityIn(groups, allowed=['critical', 'warning'], strict=true)::
    local violations = [
      {
        group: g.name,
        alert: r.alert,
        severity: if std.objectHasAll(r, 'labels') && std.objectHasAll(r.labels, 'severity')
                  then r.labels.severity
                  else '<missing>',
      }
      for g in groups
      for r in g.rules
      if std.objectHasAll(r, 'alert')
      if !(
        std.objectHasAll(r, 'labels')
        && std.objectHasAll(r.labels, 'severity')
        && std.member(allowed, r.labels.severity)
      )
    ];
    if strict && std.length(violations) > 0 then
      error 'severity policy violation (allowed=%s):\n%s' % [
        std.manifestJsonEx(allowed, ' '),
        std.manifestJsonEx(violations, '  '),
      ]
    else groups,

  requireRunbookForCritical(groups, strict=true)::
    local violations = [
      { group: g.name, alert: r.alert }
      for g in groups
      for r in g.rules
      if std.objectHasAll(r, 'alert')
      if std.objectHasAll(r, 'labels') && std.objectHasAll(r.labels, 'severity')
      if r.labels.severity == 'critical'
      if !(
        std.objectHasAll(r, 'annotations')
        && std.objectHasAll(r.annotations, 'runbook_url')
        && r.annotations.runbook_url != ''
      )
    ];
    if strict && std.length(violations) > 0 then
      error 'runbook_url required for critical alerts:\n%s' % std.manifestJsonEx(violations, '  ')
    else groups,

  // 외부 mixin용 — strict=false로 검증 후 위반 목록을 visibility로 export.
  collectViolations(groups, allowedSeverities=['critical', 'warning'])::
    {
      missingOrInvalidSeverity: [
        {
          group: g.name,
          alert: r.alert,
          severity: if std.objectHasAll(r, 'labels') && std.objectHasAll(r.labels, 'severity')
                    then r.labels.severity
                    else '<missing>',
        }
        for g in groups
        for r in g.rules
        if std.objectHasAll(r, 'alert')
        if !(
          std.objectHasAll(r, 'labels')
          && std.objectHasAll(r.labels, 'severity')
          && std.member(allowedSeverities, r.labels.severity)
        )
      ],
      criticalMissingRunbook: [
        { group: g.name, alert: r.alert }
        for g in groups
        for r in g.rules
        if std.objectHasAll(r, 'alert')
        if std.objectHasAll(r, 'labels') && std.objectHasAll(r.labels, 'severity')
        if r.labels.severity == 'critical'
        if !(
          std.objectHasAll(r, 'annotations')
          && std.objectHasAll(r.annotations, 'runbook_url')
          && r.annotations.runbook_url != ''
        )
      ],
    },
}
