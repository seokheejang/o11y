# Deploying

이 repo를 **fork(코드 복사)** 한 운영자가 환경에 적용할 때 따라야 할 체크리스트. OSS bootstrap → 자기 내부 git repo로 카피 → 운영 흐름의 핵심 단계.

> **본 repo의 사용 모델**: 코드 전체를 별도 repo로 복사. fork(git link)는 X. 카피본은 OSS와 독립 운영.

## 사전조건 (대상 클러스터)

각 환경 K8s 클러스터에 다음이 운영 중이어야 한다:

| 필수 | 설명 |
|---|---|
| Kubernetes 1.27+ | `kube-prometheus-stack` 호환 |
| Helm 3.x | chart 설치 |
| ArgoCD | GitOps sync (`deploy/argocd/appset-o11y.yaml` 적용 대상) |

선택 (Secret 패턴에 따라):

| 도구 | 어디서 쓰나 |
|---|---|
| SealedSecrets controller | `deploy/secrets/sealed/` 사용 시 |
| ESO + backend (Vault / AWS SM / ...) | `deploy/secrets/eso/` 사용 시 |
| 환경 임시 | `deploy/secrets/scripts/` (envsubst — local/staging 한정) |

## 단계 — 첫 환경 셋업

### 1) 카피본 만들기

```bash
git clone <oss-bootstrap-repo>
cd o11y
# 별도 내부 repo로 코드 카피 (fork X)
git remote rename origin oss-bootstrap
git remote add origin <your-internal-repo-url>
```

### 2) ApplicationSet repoURL 갱신

```bash
vim deploy/argocd/appset-o11y.yaml
# spec.template.spec.source.repoURL: REPLACE_WITH_REPO_URL → 자기 카피본 git URL
```

### 3) ArgoCD ApplicationSet apply

mgmt cluster(ArgoCD가 떠 있는 곳) 의 `argocd` namespace에 한 번만:

```bash
kubectl -n argocd apply -f deploy/argocd/appset-o11y.yaml
```

### 4) cluster Secret 라벨링

각 대상 cluster를 ArgoCD에 cluster Secret으로 등록 + `o11y/*` 라벨 박기. 상세는 [`docs/cluster-labels.md`](cluster-labels.md).

```yaml
metadata:
  labels:
    argocd.argoproj.io/secret-type: cluster
    o11y/managed: "true"
    o11y/provider: <provider>
    o11y/stage: <dev|prod>
    o11y/cluster: <role>
```

### 5) env 디렉토리

라벨에 매칭되는 디렉토리가 `deploy/envs/<provider>-<stage>-<cluster>/`에 있어야 한다. `deploy/envs/example-dev/`을 카피해서 시작:

```bash
cp -r deploy/envs/example-dev deploy/envs/<provider>-<stage>-<cluster>
```

디렉토리 안 파일들에서 토큰을 환경 값으로 치환. 상세는 [`deploy/envs/example-dev/README.md`](../deploy/envs/example-dev/README.md).

핵심 토큰:

| 토큰 | 의미 |
|---|---|
| `REPLACE_WITH_CLUSTER_NAME` | Prometheus `externalLabels.cluster` (보통 env 디렉토리명) |
| `REPLACE_WITH_REPO_URL` | 카피본 git URL |
| `replace-env-name` | env 디렉토리명 (K8s metadata.name 안) |

### 6) Slack webhook Secret 생성

각 대상 cluster의 `monitoring` 네임스페이스에 `alertmanager-slack-webhook` Secret. 셋 중 하나:

- **빠른 검증**: `deploy/secrets/scripts/create-slack-secret-envsubst.sh` (local/staging만)
- **GitOps 단순**: `deploy/secrets/sealed/` (SealedSecrets, kubeseal)
- **운영 표준**: `deploy/secrets/eso/` (ExternalSecrets, Vault / AWS SM / ...)

Secret 이름은 어느 패턴이든 **`alertmanager-slack-webhook`** (key `url`) 고정 — AlertmanagerConfig가 그 이름 참조.

### 7) 검증

```bash
# ApplicationSet generate 결과
kubectl -n argocd get applications -l app.kubernetes.io/part-of=o11y

# 우리 룰이 Prometheus pickup
kubectl --context <target> -n monitoring get prometheusrule -l app.kubernetes.io/managed-by=o11y

# AlertmanagerConfig admit
kubectl --context <target> -n monitoring get alertmanagerconfig baseline

# Slack Secret
kubectl --context <target> -n monitoring get secret alertmanager-slack-webhook
```

## 단계 — 환경 추가 (2번째부터)

```bash
# 1) 기존 env 디렉토리 카피 (또는 example-dev/ 출발)
cp -r deploy/envs/<existing-env> deploy/envs/<provider>-<stage>-<cluster>

# 2) 디렉토리 안 파일들 토큰 갱신 (env 이름, externalLabels.cluster, repoURL)

# 3) cluster Secret 라벨링 (docs/cluster-labels.md)

# 4) commit + push → ApplicationSet 자동 generate (추가 apply 불필요)
```

## 단계 — 환경 제거

```bash
# 1) cluster Secret에서 o11y/managed 라벨 제거 (또는 Secret 삭제)
#    → ApplicationSet이 root App finalize → child + 자원 정리

# 2) deploy/envs/<env>/ 디렉토리 git rm
```

## 흔한 함정

### chart 디폴트 룰 35개와 우리 mixin 룰 중복

`deploy/envs/_base/values-base.yaml`이 `defaultRules.create: false`로 처리. 카피 후 이 설정을 끄지 X — 우리 mixin은 kubernetes-mixin import + `main.libsonnet`의 disabled list로 더 정제된 형태로 제공.

### Prometheus ruleSelector가 우리 룰을 못 봄

chart 디폴트 `ruleSelector`는 `release=<helm-release-name>`만 매치. 우리 wrapper는 `app.kubernetes.io/managed-by: o11y` 라벨. `values-base.yaml`이 우리 라벨로 override.

### AlertmanagerConfig가 monitoring ns alert만 라우팅

prometheus-operator 디폴트 `OnNamespace` strategy. `values-base.yaml`이 `alertmanagerConfigMatcherStrategy.type: None`으로 끔. 근거: [learnings/2026-05-13-alertmanager-matcher-strategy.md](learnings/2026-05-13-alertmanager-matcher-strategy.md).

### externalLabels.cluster 빈 값 → inhibit 의도 깨짐

`equal: [alertname, cluster, namespace]` inhibit rule에서 `cluster`가 빈 값이면 inhibit가 너무 광범위. 각 env의 `values.yaml`에서 `prometheus.prometheusSpec.externalLabels.cluster`를 env 디렉토리명으로 채울 것.

### in-cluster cluster Secret 명시 등록 필요

ArgoCD 디폴트 `in-cluster`는 Cluster Generator selector에 안 잡힘. self-managed cluster도 cluster Secret으로 명시 등록 + 라벨링 필요. [`docs/cluster-labels.md`](cluster-labels.md) 참조.

## 관련 docs

- [docs/cluster-labels.md](cluster-labels.md) — cluster Secret 라벨 컨벤션
- [deploy/argocd/README.md](../deploy/argocd/README.md) — ApplicationSet 흐름
- [deploy/envs/example-dev/README.md](../deploy/envs/example-dev/README.md) — env 카피 + 토큰 치환
- [deploy/secrets/README.md](../deploy/secrets/README.md) — Sealed vs ESO vs envsubst 선택
- [severity-policy.md](severity-policy.md) — 라우팅 정합 + Slack Secret 컨벤션
- [adding-a-component.md](adding-a-component.md) — 새 도메인 컴포넌트 추가
- [learnings/2026-05-14-argocd-appset-cluster-generator.md](learnings/2026-05-14-argocd-appset-cluster-generator.md) — generator 선택 best-practice
