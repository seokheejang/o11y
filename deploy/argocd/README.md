# deploy/argocd — ArgoCD ApplicationSet (multi-cluster GitOps 진입점)

이 디렉토리의 ApplicationSet 1개를 ArgoCD에 apply하면 모든 환경의 o11y 스택이 자동 sync 된다.

## 패턴

```
ApplicationSet (이 디렉토리)
    ↓ generate
env별 App-of-Apps root Application (envs/<env>/app-of-apps.yaml 기반)
    ↓ sync
env별 child Applications (envs/<env>/apps/*.yaml)
    ↓ sync
실제 K8s 자원 (helm chart + 자체 mixin manifests + ...)
```

[`Discussion #11892`](https://github.com/argoproj/argo-cd/discussions/11892)의 메인테이너 권장 조합 — ApplicationSet (top, multi-env generate) + App-of-Apps (mid, env-specific bootstrap).

## 적용 절차 (카피본 운영자)

```bash
# 1) deploy/envs/example-dev를 카피해서 자기 환경 디렉토리 만들기
cp -r deploy/envs/example-dev deploy/envs/dev1
# (REPLACE_* 토큰 치환 — values.yaml, app-of-apps.yaml, apps/*.yaml)

# 2) appset-o11y.yaml의 generators.list.elements에 dev1 추가 + REPLACE_WITH_REPO_URL 갱신

# 3) ArgoCD가 띄워진 클러스터(mgmt cluster)에 ApplicationSet 1회 apply
kubectl -n argocd apply -f deploy/argocd/appset-o11y.yaml

# 4) ArgoCD UI에서 dev1-o11y root Application + child Applications 생성 확인
#    ArgoCD가 자동으로 child가 가리키는 chart/manifests를 sync
```

## 새 환경 추가

```bash
# 1) 환경 디렉토리 카피
cp -r deploy/envs/example-dev deploy/envs/<new-env>
# (REPLACE_* 토큰 치환)

# 2) appset-o11y.yaml의 elements에 한 줄 추가:
#    - name: <new-env>
#      cluster: https://api.<new-env>.example.com

# 3) commit + push → ApplicationSet controller가 자동으로 <new-env>-o11y root App 생성
```

## 환경 제거

```bash
# elements에서 해당 env 줄 삭제 → ApplicationSet이 root Application 자동 prune
# (root Application의 finalizer가 child + 클러스터 자원도 정리)

# envs/<env>/ 디렉토리는 git에서 별도 정리.
```

## sync wave / ordering

stack 컴포넌트 간 순서가 필요하면 (예: chart 먼저, 그다음 우리 룰):

```yaml
# envs/<env>/apps/o11y-rules.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # 기본 0보다 늦게
```

ApplicationSet 자체엔 sync-wave 기능이 제한적이라 child Application 수준에서 처리.

## 보안 / 격리

- `project: default` — fork 받은 운영자가 자기 `AppProject`로 교체 권장. 클러스터 destination/repoURL 제한.
- `automated.prune=true` + `selfHeal=true` — drift 자동 복구. 운영 정책에 따라 비활성 가능.
- `ServerSideApply=true` — kube-prometheus-stack은 CRD가 많아 SSA 권장.
