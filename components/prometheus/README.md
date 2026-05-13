# components/prometheus

자체 운영 필수 알림(메타/네트워크/DNS/워크로드)과 그 임계값/selectors를 정의하는 컴포넌트. kubernetes-mixin이 안 만드는 영역을 보강한다.

## 파일

| 파일 | 역할 |
|---|---|
| `mixin.libsonnet` | entry point — `config.libsonnet + alerts.libsonnet` 합성, `prometheusAlerts` + `_config` export |
| `config.libsonnet` | `_config+::` — job selectors, runbook base URL, thresholds (CoreDNS p99, ingress 5xx ratio, conntrack 80%, OOM rate 등) |
| `alerts.libsonnet` | `prometheusAlerts.groups` — 운영에 필요한 critical/warning 알림. severity 강제 + runbook_url annotation 필수 |

## 정책

- `severity`는 `critical` / `warning` 2단계만 ([docs/severity-policy.md](../../docs/severity-policy.md))
- `critical`은 반드시 `runbook_url` annotation 보유 (`_config.runbookBase` 기반)
- `for:` 평가 윈도우 ≥ 2분 (critical) / ≥ 5분 (warning)
- 정책 위반 시 빌드 실패 (`_lib/transform.libsonnet`의 strict 검증)

## 임계값 origin

[docs/baseline-alerts.md](../../docs/baseline-alerts.md) — 채택한 값 + 외부 사례 출처.
