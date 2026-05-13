# envs/example-dev — 예시 환경 (카피용 placeholder)

이 디렉토리는 **fork 받은 운영자가 카피해서 자기 환경을 만드는 출발점**. 실제 적용은 하지 X — `REPLACE_*` 토큰이 들어있어 helm/ArgoCD가 거절한다.

## 카피 절차

```bash
cp -r deploy/envs/example-dev deploy/envs/<your-env-name>
```

그 후 새 디렉토리에서 다음 토큰을 치환:

| 토큰 | 의미 | 예시 |
|---|---|---|
| `replace-env-name` (metadata.name 안) | 디렉토리명과 동일 (ApplicationSet generator 파라미터) | `dev-us-east-1` |
| `REPLACE_WITH_CLUSTER_NAME` (label value) | Prometheus `externalLabels.cluster` 값 | `dev-us-east-1` (보통 env-name과 동일) |
| `REPLACE_WITH_REPO_URL` | 카피본 git URL | `git@github.internal:<org>/o11y.git` |
| `replace-with-alertmanager-cr-name` | 부모 Alertmanager CR 이름 (patches/ 적용 시) | `kube-prometheus-stack-alertmanager` |
| `replace-with-store-name` (ESO) | SecretStore metadata.name | `vault-monitoring` |
| `REPLACE_WITH_VAULT_URL/ROLE` (ESO) | Vault server URL + Kubernetes auth role | `https://vault.internal` / `alertmanager-reader` |

> placeholder가 두 형태(`REPLACE_*` uppercase vs `replace-*` lowercase-hyphen)인 이유: K8s metadata.name은 DNS-1123 label(lowercase + hyphen) 강제, label value/annotation/string은 자유. lowercase-hyphen은 K8s 자원 이름에만 사용.

치환 후 commit + push → ApplicationSet(`deploy/argocd/appset-o11y.yaml`)이 새 env를 자동 발견 → ArgoCD가 sync.

## 파일 구성 (Sub-B 패턴 = App-of-Apps per env)

| 파일 | 역할 |
|---|---|
| `values.yaml` | env-specific chart override (cluster label, ingress, retention, ...) |
| `app-of-apps.yaml` | env의 root Application (ApplicationSet이 generate; 참조용으로 같이 둠) |
| `apps/kube-prometheus-stack.yaml` | helm chart sync (multi-source: chart + 카피본 values overlay) |
| `apps/o11y-rules.yaml` | 자체 mixin 빌드 산출물(`manifests/`) sync |

stack 컴포넌트가 늘면(예: loki, tempo, alloy) `apps/` 안에 child Application 추가.

## env values 머지 순서

ArgoCD multi-source가 두 values 파일을 순서대로 적용:

1. `deploy/envs/_base/values-base.yaml` — 환경 공통 (`defaultRules.create=false`, `ruleSelector`, `matcherStrategy: None`)
2. `deploy/envs/<env>/values.yaml` — env-specific (`externalLabels.cluster`, ingress, resources)

뒤가 앞을 override.

## Secret 사전조건

이 env가 정상 동작하려면 다음 Secret이 `monitoring` 네임스페이스에 사전 생성되어야 함:

| Secret | 키 | 용도 |
|---|---|---|
| `alertmanager-slack-webhook` | `url` | Slack incoming webhook URL (critical-chat / warning-chat receiver) |

생성 방법은 환경 인프라에 따라 다름 — `deploy/secrets/` 참조 (Sealed / ESO / 빠른 검증용 envsubst 스크립트).
