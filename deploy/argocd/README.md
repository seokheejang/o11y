# deploy/argocd — ArgoCD ApplicationSet (multi-cluster GitOps 진입점)

ApplicationSet 1개를 ArgoCD에 apply하면 cluster Secret 라벨에 매칭되는 모든 환경의 o11y 스택이 자동 sync 된다.

## 패턴

```
ApplicationSet (이 디렉토리)
    ↓ Cluster Generator + o11y/managed=true selector
env별 App-of-Apps root Application (path: deploy/envs/<provider>-<stage>-<cluster>/apps)
    ↓ sync
env별 child Applications (apps/*.yaml)
    ↓ sync
실제 K8s 자원 (helm chart + 자체 mixin manifests + ...)
```

[`Discussion #11892`](https://github.com/argoproj/argo-cd/discussions/11892)의 메인테이너 권장 조합 — ApplicationSet (top, multi-cluster generate) + App-of-Apps (mid, env-specific bootstrap).

## 핵심: cluster Secret 라벨

cluster Secret에 박는 라벨이 모든 디렉토리 매핑의 기준. 컨벤션은 [`docs/cluster-labels.md`](../../docs/cluster-labels.md).

| Key | 역할 |
|---|---|
| `o11y/managed` | `"true"`면 본 ApplicationSet의 sync 대상 |
| `o11y/provider` | provider 분류 (예: `aws`, `gcp`, `on-prem`, ...) |
| `o11y/stage` | 배포 stage (`dev` / `prod`) |
| `o11y/cluster` | 워크로드 role / cluster 정체성 |

→ git path: `deploy/envs/{provider}-{stage}-{cluster}/apps`

## 적용 절차 (카피본 운영자)

```bash
# 1) ApplicationSet에서 REPLACE_WITH_REPO_URL을 자기 카피본 git URL로 치환
vim deploy/argocd/appset-o11y.yaml

# 2) ArgoCD가 떠 있는 cluster의 argocd ns에 1회 apply
kubectl -n argocd apply -f deploy/argocd/appset-o11y.yaml

# 3) cluster Secret 라벨링 (docs/cluster-labels.md 참조)

# 4) 환경 디렉토리 추가 (deploy/envs/example-dev/ 출발)
```

자세한 절차는 [`docs/deploying.md`](../../docs/deploying.md).

## 새 환경 추가

cluster Secret + 디렉토리 — 두 가지로 끝:

```bash
# 1) 환경 디렉토리
cp -r deploy/envs/example-dev deploy/envs/<provider>-<stage>-<cluster>
# 토큰 갱신: env 이름, externalLabels.cluster, repoURL

# 2) cluster Secret 라벨링
#    o11y/managed=true, o11y/provider=..., o11y/stage=..., o11y/cluster=...

# 3) commit → ApplicationSet 자동 generate (추가 apply 불필요)
```

## 환경 제거

cluster Secret 라벨 제거 (또는 Secret 삭제) → ApplicationSet이 root App finalize → 자원 정리 → `deploy/envs/<env>/` 디렉토리 git rm.

## sync wave / ordering

stack 컴포넌트 간 순서 필요 (예: chart 먼저, 그다음 우리 룰):

```yaml
# envs/<env>/apps/o11y-rules.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # 기본 0보다 늦게
```

ApplicationSet 자체엔 sync-wave 제한적이라 child Application 수준에서 처리.

## 보안 / 격리

- `project: default` — fork 받은 운영자가 자기 `AppProject`로 교체 권장. cluster destination / repoURL 제한.
- `automated.prune=true` + `selfHeal=true` — drift 자동 복구. 운영 정책에 따라 비활성 가능.
- `ServerSideApply=true` — kube-prometheus-stack은 CRD가 많아 SSA 권장.

## 결정 배경

- [`docs/learnings/2026-05-14-argocd-appset-cluster-generator.md`](../../docs/learnings/2026-05-14-argocd-appset-cluster-generator.md) — Cluster Generator 패턴 best-practice 박제
