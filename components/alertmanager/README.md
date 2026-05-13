# components/alertmanager

severity 기반 routing tree + receivers + inhibit_rules. `AlertmanagerConfig` CR로 렌더링되어 prometheus-operator가 alertmanager.yml로 컴파일한다.

## 파일

| 파일 | 역할 |
|---|---|
| `mixin.libsonnet` | entry point — `routing.libsonnet` 그대로 export. `alertmanagerConfig.{route, receivers, inhibitRules}` 객체 |
| `routing.libsonnet` | routing tree + 4 receivers (`null`/`pager`/`critical-chat`/`warning-chat`) + 2 inhibit rules |

## 라우팅 정합

| 라벨 | receiver | repeat_interval |
|---|---|---|
| `severity=critical` | `pager` + `critical-chat` (continue=true) | 1h |
| `severity=warning` | `warning-chat` | 12h |
| 그 외 | `null` (drop) | (default 4h) |

`group_by: [alertname, cluster, namespace]`, `group_wait: 30s`, `group_interval: 5m`.

## Receiver 와이어링 (현재)

- `pager`: placeholder — `pagerdutyConfigs` 미연결 → silent drop. PagerDuty 도입 시 receiver config만 채움.
- `critical-chat` / `warning-chat`: 같은 Slack webhook Secret 공유, severity 구분은 color/title prefix.
  Secret 컨벤션: `alertmanager-slack-webhook` (key `url`) — 환경 인프라가 monitoring ns에 생성.

상세 정합과 검증은 [docs/severity-policy.md](../../docs/severity-policy.md) "Alertmanager 라우팅 정합" 절.

## CR ↔ raw 변환

이 컴포넌트는 jsonnet 객체로 routing intent를 정의하고, `_lib/alertmanager.libsonnet`이 양쪽 형식으로 변환한다:

- **AlertmanagerConfig CR** (`manifests/alertmanager-config/baseline.yaml`) → 클러스터 sync 대상
- **raw alertmanager.yml** (`out/alertmanager-config-raw/baseline.yaml`) → amtool 검증 입력

같은 source-of-truth라 "routing 단언이 통과한 그 라우팅이 클러스터에 들어간다"가 보장된다.

## matcherStrategy 사전조건

이 라우팅이 cluster-wide alert(예: `KubePodNotReady@prod-app`)에 적용되려면 부모 `Alertmanager` CR의 `spec.alertmanagerConfigMatcherStrategy.type: None` 설정이 필요. 디폴트 `OnNamespace`는 routes에 `namespace="monitoring"`을 자동 prepend하여 monitoring ns alert만 통과시킨다. 자세한 근거: [docs/learnings/2026-05-13-alertmanager-matcher-strategy.md](../../docs/learnings/2026-05-13-alertmanager-matcher-strategy.md).
