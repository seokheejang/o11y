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

### Receiver 와이어링

| Receiver | 매처 | endpoint 상태 | 비고 |
|---|---|---|---|
| `null` | catch-all | 없음 (drop) | Alertmanager 컨벤션 |
| `pager` | `severity=critical` (`continue=true`) | **placeholder** — `pagerdutyConfigs` 미연결 | 매처는 통과하지만 dispatch 시점에 silent drop. PagerDuty 도입 시 receiver config만 채우면 됨 |
| `critical-chat` | `severity=critical` | **Slack** (`slackConfigs` 와이어링됨) | color: `danger`, title prefix: `[CRITICAL]` |
| `warning-chat` | `severity=warning` | **Slack** (`slackConfigs` 와이어링됨) | color: `warning`, title prefix: `[WARNING]` |

#### Slack receiver Secret

`critical-chat` / `warning-chat`이 같은 Slack incoming webhook을 공유한다 (단일 채널). severity 구분은 메시지의 color와 title prefix로 한다 — 추후 채널을 분리할 때는 webhook Secret 또는 receiver별 SecretKeySelector만 바꾸면 됨.

환경 인프라가 `monitoring` 네임스페이스에 다음 Secret을 생성해야 한다:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-slack-webhook
  namespace: monitoring
type: Opaque
stringData:
  url: https://hooks.slack.com/services/XXX/XXX/XXX   # 실제 webhook URL
```

생성 방법은 클러스터별로 다름 (SealedSecret, ExternalSecrets, GitOps secret store 등) — 이 repo는 Secret 자체를 만들지 않는다.

E2E 클러스터(`make e2e-up`)는 placeholder URL(`https://hooks.slack.com/services/PLACEHOLDER/...`)로 동일한 이름의 Secret을 자동 생성한다 — admission/operator reload만 검증하면 충분하므로 실 Slack에 dispatch되지 않는다.

#### Namespace 스코프 (matcherStrategy)

위 라우팅이 cluster-wide alert(예: `KubePodNotReady@prod-app`)에 적용되려면 부모 Alertmanager CR이 `spec.alertmanagerConfigMatcherStrategy.type: None` 으로 설정되어야 한다. 디폴트 `OnNamespace`는 operator가 routes에 `namespace="<AMC ns>"` 매처를 자동 prepend하여 monitoring ns alert만 통과시킨다. 자세한 근거: [learnings/2026-05-13-alertmanager-matcher-strategy.md](learnings/2026-05-13-alertmanager-matcher-strategy.md).

## 변경 이력

- 2026-05-05 — 정책 초안
- 2026-05-07 — AlertmanagerConfig CR 렌더링 + amtool 단언 (라우팅 PR)
- 2026-05-13 — Slack receiver 와이어링 (critical-chat/warning-chat). pager는 placeholder 유지.

## 참고

- [Better Stack — Solving Alert Fatigue](https://betterstack.com/community/guides/monitoring/best-practices-alert-fatigue/)
- [VictoriaMetrics — Alerting Best Practices](https://victoriametrics.com/blog/alerting-best-practices/)
