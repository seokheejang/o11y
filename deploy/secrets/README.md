# deploy/secrets — 알림 receiver 시크릿 패턴

`AlertmanagerConfig`가 참조하는 시크릿(예: Slack incoming webhook URL)을 환경에 주입하는 패턴들. 환경 인프라의 시크릿 관리 모델에 따라 3가지 중 선택:

| 디렉토리 | 패턴 | 적합 시나리오 |
|---|---|---|
| `sealed/` | SealedSecrets controller가 복호화 | GitOps 친화, 단순, 빠른 검증. multi-cluster 확장 약함 |
| `eso/` | External Secrets Operator(Vault/AWS SM/GCP SM 백엔드) | 운영 단계, multi-cluster, 자동 rotation. backend infra 전제 |
| `scripts/` | envsubst 기반 부트스트랩 스크립트 | local 테스트 / 첫 검증. 운영 단계엔 sealed/eso로 교체 |

세 패턴 모두 동일한 Secret 이름·키 컨벤션을 따른다:

| Secret 이름 | 네임스페이스 | 키 | 값 |
|---|---|---|---|
| `alertmanager-slack-webhook` | `monitoring` | `url` | Slack incoming webhook URL |

AlertmanagerConfig의 `slackConfigs[].apiURL`이 이 Secret을 참조하므로 이름/네임스페이스가 위와 일치해야 한다. 환경별로 webhook URL은 다르지만 Secret 이름은 동일하게 유지 — 라우팅 코드 변경 없이 환경 운영 가능.

## 어느 걸 골라야 하나

```
Vault/AWS SM/GCP SM 같은 backend 운영 중?
├─ Yes → eso/ (운영 표준)
└─ No  → 처음에는 sealed/ (또는 빠른 검증은 scripts/)
         이후 backend 도입 시 eso/로 마이그레이션
```

## 빠른 검증 (envsubst)

local kind 클러스터 또는 첫 검증 환경에 1회성으로 placeholder Secret 주입:

```bash
export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/XXX/YYY/ZZZ'
bash deploy/secrets/scripts/create-slack-secret-envsubst.sh
```

운영 환경에 그대로 쓰지 X (`kubectl create secret` 명령 history에 평문 URL 노출). sealed/ 또는 eso/로 가야 함.
