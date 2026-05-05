# Severity Policy

본 repo는 **`critical`과 `warning` 2단계만** 사용한다. `info`는 알림으로 만들지 않고 대시보드/로그로 처리한다.

## 정책 표

아래 채널/도구명은 **예시**다. fork 시 자기 환경(PagerDuty/Opsgenie/Slack/Teams 등)에 맞게 교체한다.

| Severity | 의미 | 채널 (예시) | 응답 기대 | repeat_interval |
|----------|------|-------------|-----------|-----------------|
| `critical` | 사용자 영향 발생 중 또는 즉박. 즉시 대응 필요 | `<pager>` + `<critical-channel>` | **15분 이내 ack**, 1시간 이내 mitigation | `1h` |
| `warning` | 사용자 영향 없음, 그러나 방치 시 critical로 진행 가능 | `<warning-channel>`만 | **다음 영업일** 안에 확인 | `12h` |

## 어떤 severity를 쓸지 판단 기준

```
사용자가 지금 아픈가?
├─ Yes  → critical
└─ No   → 며칠 안에 critical로 갈까?
          ├─ Yes  → warning
          └─ No   → 알림 만들지 마라 (대시보드/로그)
```

## critical 알림 작성 규칙

- 반드시 `runbook_url` annotation 포함
- `for:` 평가 윈도우 ≥ 2분 (일시 스파이크 차단)
- `summary`에 영향받는 인스턴스/서비스를 라벨로 노출
- 페이징되는 것이므로 새벽 3시 기준으로 검토

## warning 알림 작성 규칙

- `runbook_url` 권장 (필수 아님)
- `for:` 평가 윈도우 ≥ 5분
- 임계값에 hysteresis(이력 현상) 적용 — 예: 90% 발화 / 85% 해제

## Alertmanager 라우팅 정합

```yaml
route:
  group_by: [alertname, cluster, namespace]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h        # default
  receiver: default-slack
  routes:
    - matchers: [severity="critical"]
      receiver: pager           # 예: PagerDuty / Opsgenie
      repeat_interval: 1h
      continue: true
    - matchers: [severity="critical"]
      receiver: critical-chat   # 예: Slack #alerts-critical
    - matchers: [severity="warning"]
      receiver: warning-chat    # 예: Slack #alerts-warning
      repeat_interval: 12h
```

## 변경 이력

- 2026-05-05 — 정책 초안

## 참고

- [Better Stack — Solving Alert Fatigue](https://betterstack.com/community/guides/monitoring/best-practices-alert-fatigue/)
- [VictoriaMetrics — Alerting Best Practices](https://victoriametrics.com/blog/alerting-best-practices/)
