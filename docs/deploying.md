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

## 환경별 선택적 튜닝

기본 scaffold만으로 대부분 환경이 동작하지만, 클러스터 특성에 따라 fork에서 추가 결정이 필요한 항목.

### chart Application의 sync 모드

`deploy/envs/example-dev/apps/kube-prometheus-stack.yaml`은 디폴트로 `automated` 블록을 **제거**(수동 sync) 상태로 제공한다. 운영 중인 helm release를 adopt하는 stateful App이라 selfHeal/prune의 blast radius가 크기 때문 — `o11y-rules` App은 auto + selfHeal + prune 유지(재생성 가능).

빈 클러스터에 신규 배포라 위험이 낮다면 fork에서 `automated` 블록을 다시 추가해도 된다. 자세한 결정 근거: [learnings/2026-05-21-gitops-safety-stateful-charts.md](learnings/2026-05-21-gitops-safety-stateful-charts.md).

### PVC 보호 패턴

운영 데이터(시계열, Grafana 대시보드/datasource 설정)를 담은 PVC는 세 layer에서 보호한다:

1. **chart App 수동 sync** (위 항목 — L1)
2. **PVC `sync-options` 어노테이션**: `argocd.argoproj.io/sync-options: Prune=false,Delete=false`
   - `example-dev/values.yaml`에 주석으로 패턴 가이드 있음 — Prometheus storageSpec + Grafana persistence 각각
3. **StorageClass `reclaimPolicy: Retain`**: 클러스터 인프라 레벨, repo 외부

Layer 1·2·3이 각각 다른 attack surface(자동화 사고 / git 변경 / 사람 직접 명령)를 막는다. 시나리오별 매핑은 [learnings/2026-05-21-gitops-safety-stateful-charts.md](learnings/2026-05-21-gitops-safety-stateful-charts.md) 표 참조.

### ingress controller 미사용 클러스터

Gateway API, traefik, 또는 ingress 자체를 안 쓰는 클러스터에서는 `baseline-network` alert group(`IngressControllerDown` / `HighIngress5xxRate` / `HighIngress4xxRate`)이 영구 firing 또는 dormant 상태로 남는다. fork의 `main.libsonnet`에서 `_config` override로 group 자체를 비활성:

```jsonnet
local prometheus = (import 'prometheus/mixin.libsonnet') + {
  _config+:: { ingressControllerEnabled: false },
};
```

빌드 후 `manifests/prometheus-rules/baseline.yaml`에서 group이 빠진 것을 확인. 자세한 근거: [learnings/2026-05-21-ingress-controller-flag.md](learnings/2026-05-21-ingress-controller-flag.md).

### `runbookBase` URL

`components/prometheus/config.libsonnet`의 `runbookBase`는 OSS 디폴트로 이 repo(`seokheejang/o11y`)를 가리킨다. 카피본은 자신의 git 호스트로 가리키도록 fork에서 override 권장 — 알람 메시지의 runbook 링크가 운영자가 접근 가능한 위치를 향하게.

## 관련 docs

- [docs/cluster-labels.md](cluster-labels.md) — cluster Secret 라벨 컨벤션
- [deploy/argocd/README.md](../deploy/argocd/README.md) — ApplicationSet 흐름
- [deploy/envs/example-dev/README.md](../deploy/envs/example-dev/README.md) — env 카피 + 토큰 치환
- [deploy/secrets/README.md](../deploy/secrets/README.md) — Sealed vs ESO vs envsubst 선택
- [severity-policy.md](severity-policy.md) — 라우팅 정합 + Slack Secret 컨벤션
- [adding-a-component.md](adding-a-component.md) — 새 도메인 컴포넌트 추가
- [learnings/2026-05-14-argocd-appset-cluster-generator.md](learnings/2026-05-14-argocd-appset-cluster-generator.md) — generator 선택 best-practice
