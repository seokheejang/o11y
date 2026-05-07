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

이 트리는 **실제로 빌드 산출물에 들어간다**. 소스: [`mixins/local/baseline-mixin/alertmanager.libsonnet`](../mixins/local/baseline-mixin/alertmanager.libsonnet).
검증: `make test`가 `amtool config routes test`로 아래 단언을 매 빌드마다 실행.

```yaml
route:
  group_by: [alertname, cluster, namespace]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h        # default
  receiver: "null"           # severity 누락/외부 소스 — silently drop
  routes:
    - matchers: [severity="critical"]
      receiver: pager           # 예: PagerDuty / Opsgenie
      repeat_interval: 1h
      continue: true            # ↓ critical-chat에도 보낸다
    - matchers: [severity="critical"]
      receiver: critical-chat   # 예: Slack #alerts-critical
    - matchers: [severity="warning"]
      receiver: warning-chat    # 예: Slack #alerts-warning
      repeat_interval: 12h
```

### Inhibit rules

```yaml
inhibit_rules:
  # 같은 (alertname, cluster, namespace) 묶음에서 critical 발화 중이면 warning 묵음.
  - source_matchers: [severity="critical"]
    target_matchers: [severity="warning"]
    equal: [alertname, cluster, namespace]
  # KubeNodeNotReady 발화 시 같은 (cluster, node)의 모든 warning 묵음.
  # 노드 다운 한 건이 Pod-level warning 수십 개를 trigger하는 폭주 차단.
  - source_matchers: [alertname="KubeNodeNotReady"]
    target_matchers: [severity="warning"]
    equal: [cluster, node]
```

### 라우팅 단언 (자동 검증되는 보장)

| 라벨셋 | 가는 receiver |
|---|---|
| `severity=critical, ...` | `pager` + `critical-chat` (둘 다) |
| `severity=warning, ...` | `warning-chat` |
| `severity=info` 또는 누락 | `null` (drop) |

receiver 이름(`pager`, `critical-chat`, `warning-chat`, `null`)은 placeholder다.
실제 endpoint(Slack webhook, PagerDuty integration key 등) 연결은 클러스터 sync PR에서.

## 변경 이력

- 2026-05-05 — 정책 초안
- 2026-05-07 — AlertmanagerConfig CR 렌더링 + amtool 단언 (라우팅 PR)

## 참고

- [Better Stack — Solving Alert Fatigue](https://betterstack.com/community/guides/monitoring/best-practices-alert-fatigue/)
- [VictoriaMetrics — Alerting Best Practices](https://victoriametrics.com/blog/alerting-best-practices/)
