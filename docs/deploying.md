# Deploying

이 repo를 **fork(코드 복사)**한 운영자가 환경에 적용할 때 따라야 할 체크리스트. OSS bootstrap → 회사 내부 git repo로 카피 → 운영 흐름의 핵심 단계.

> **본 repo의 사용 모델**: 코드 전체를 별도 repo로 복사. fork(git link)는 X. 카피본은 OSS와 독립 운영.

## 사전조건 (대상 클러스터)

각 환경 K8s 클러스터에 다음이 운영 중이어야 한다:

| 필수 | 설명 |
|---|---|
| Kubernetes 1.27+ | `kube-prometheus-stack` 85.0.2 호환 |
| Helm 3.x | chart 설치 |
| ArgoCD | GitOps sync (`deploy/argocd/appset-o11y.yaml` 적용 대상) |

선택 (Secret 패턴에 따라):

| 도구 | 어디서 쓰나 |
|---|---|
| SealedSecrets controller | `deploy/secrets/sealed/` 사용 시 |
| External Secrets Operator + backend(Vault/AWS SM/...) | `deploy/secrets/eso/` 사용 시 |
| 둘 다 안 쓰는 환경 | `deploy/secrets/scripts/` (envsubst — local/staging 한정) |

## 단계 — 첫 환경 셋업

### 1) 카피본 만들기

```bash
git clone <oss-bootstrap-repo>
cd o11y
# 별도 내부 repo로 코드 카피 (fork X)
git remote rename origin oss-bootstrap
git remote add origin <your-internal-repo-url>
```

### 2) 환경 디렉토리 만들기

```bash
cp -r deploy/envs/example-dev deploy/envs/<your-env-name>
```

`<your-env-name>`은 ArgoCD 식별자로 들어가니 DNS-1123 라벨 (lowercase + hyphen).

### 3) placeholder 치환

`deploy/envs/<your-env-name>/` 안의 5개 파일에서 토큰을 환경 값으로 치환. 상세는 [deploy/envs/example-dev/README.md](../deploy/envs/example-dev/README.md).

핵심 토큰:

| 토큰 | 의미 |
|---|---|
| `replace-env-name` | `<your-env-name>`과 동일 (K8s metadata.name 안) |
| `REPLACE_WITH_CLUSTER_NAME` | Prometheus `externalLabels.cluster` |
| `REPLACE_WITH_REPO_URL` | 카피본 git URL |
| `REPLACE_WITH_CLUSTER_SERVER_URL` (appset 안) | ArgoCD가 인지하는 cluster API URL |

### 4) Slack webhook Secret 생성

[deploy/secrets/README.md](../deploy/secrets/README.md)의 가이드에 따라 셋 중 하나:

- **빠른 검증**: `deploy/secrets/scripts/create-slack-secret-envsubst.sh` (local/staging만)
- **GitOps 단순**: `deploy/secrets/sealed/` (SealedSecrets, kubeseal)
- **운영 표준**: `deploy/secrets/eso/` (ExternalSecrets, Vault/AWS SM/...)

Secret 이름은 어느 패턴이든 **`alertmanager-slack-webhook`** (key `url`) 고정 — AlertmanagerConfig가 그 이름 참조.

### 5) ApplicationSet 적용

```bash
# ApplicationSet에 your-env-name을 elements에 추가 + REPLACE_WITH_REPO_URL 치환
vim deploy/argocd/appset-o11y.yaml

# mgmt cluster (ArgoCD 띄워진 곳)에 1회 apply
kubectl -n argocd apply -f deploy/argocd/appset-o11y.yaml

git commit + push
```

ApplicationSet controller가 `<your-env-name>-o11y` root Application + child Application들을 자동 생성 → ArgoCD가 sync.

### 6) 검증

```bash
# 모든 Application Healthy 확인
kubectl -n argocd get applications

# 우리 룰이 Prometheus에 픽업되었는지
kubectl -n monitoring get prometheusrule -l app.kubernetes.io/managed-by=o11y

# AlertmanagerConfig admit
kubectl -n monitoring get alertmanagerconfig baseline

# Slack Secret 존재 + Alertmanager가 마운트
kubectl -n monitoring get secret alertmanager-slack-webhook
```

Prometheus UI에서 `up{job="kube-state-metrics"}`가 1이고, AlertmanagerConfig route가 alertmanager.yml에 머지되었는지 (`kubectl get secret alertmanager-<name>-generated -o jsonpath='{.data.alertmanager\.yaml\.gz}' | base64 -d | gunzip`) 확인.

## 단계 — 환경 추가 (2번째부터)

```bash
cp -r deploy/envs/example-dev deploy/envs/<another-env>
# 토큰 치환 + Slack Secret 생성 (단계 3-4)

# appset-o11y.yaml의 elements에 새 env 한 줄 추가
vim deploy/argocd/appset-o11y.yaml

git commit + push
# ApplicationSet controller가 자동 처리
```

ApplicationSet 자체는 mgmt cluster에 이미 있으므로 추가 apply 불필요.

## 단계 — 환경 제거

```bash
# 1) appset-o11y.yaml의 elements에서 해당 env 줄 삭제
git commit + push
# ApplicationSet이 root Application 자동 prune
# (finalizer가 child + 실제 자원도 정리)

# 2) deploy/envs/<env>/ 디렉토리는 별도로 git rm
```

## 흔한 함정

### chart 디폴트 룰 35개와 우리 mixin 룰 중복

`deploy/envs/_base/values-base.yaml`이 `defaultRules.create: false`로 처리. 카피 후 이 설정을 끄지 X — 우리 mixin은 kubernetes-mixin import + `main.libsonnet`의 disabled list로 같은 영역을 더 정제된 형태로 제공.

### Prometheus ruleSelector가 우리 룰을 못 봄

chart 디폴트 `ruleSelector`는 `release=<helm-release-name>`만 매치. 우리 wrapper는 `app.kubernetes.io/managed-by: o11y` 라벨을 단다. `deploy/envs/_base/values-base.yaml`이 `ruleSelector`를 우리 라벨에 맞춰 override.

### AlertmanagerConfig가 monitoring ns alert만 라우팅

prometheus-operator의 디폴트 `OnNamespace` strategy가 routes에 `namespace="monitoring"` matcher를 자동 prepend. `values-base.yaml`이 `alertmanagerConfigMatcherStrategy.type: None`으로 끔. 근거: [learnings/2026-05-13-alertmanager-matcher-strategy.md](learnings/2026-05-13-alertmanager-matcher-strategy.md).

### externalLabels.cluster 빈 값 → inhibit 의도 깨짐

`equal: [alertname, cluster, namespace]` inhibit rule에서 `cluster`가 빈 값이면 "모든 alert가 같은 cluster"로 간주 → inhibit가 너무 광범위. 각 env의 `values.yaml`에서 `prometheus.prometheusSpec.externalLabels.cluster`를 env 이름으로 채울 것.

## 관련 docs

- [deploy/README.md](../deploy/README.md) — scaffold 전체 구조
- [deploy/envs/example-dev/README.md](../deploy/envs/example-dev/README.md) — env 카피 + 토큰 치환 절차
- [deploy/secrets/README.md](../deploy/secrets/README.md) — Sealed vs ESO vs envsubst 선택
- [deploy/argocd/README.md](../deploy/argocd/README.md) — ApplicationSet 흐름 + env 추가/제거
- [severity-policy.md](severity-policy.md) — 라우팅 정합 + Slack Secret 컨벤션
- [adding-a-component.md](adding-a-component.md) — 새 도메인 컴포넌트 추가
