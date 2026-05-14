# 2026-05-14 — ApplicationSet generator 선택과 envs 디렉토리 구조

**Category**: architecture
**Related**: [`deploy/envs/`](../../deploy/envs/), [`deploy/argocd/appset-o11y.yaml`](../../deploy/argocd/appset-o11y.yaml), [`docs/cluster-labels.md`](../cluster-labels.md)

## 컨텍스트

multi-cluster GitOps 구조를 잡으면서 `deploy/envs/` 트리와 ApplicationSet generator를 결정. 차원이 3개:

- provider (예: `aws`, `gcp`, `on-prem`)
- stage (`dev` / `prod`)
- cluster role

모든 조합이 dense하지 않음 (sparse — 일부 cluster는 특정 provider+stage 조합만 존재).

## 선택: Cluster Generator + cluster Secret labels

`deploy/envs/<provider>-<stage>-<cluster>/` 평탄 트리 + ArgoCD **Cluster Generator** + cluster Secret labels.

ArgoCD cluster Secret에 라벨 박음:

```yaml
metadata:
  labels:
    argocd.argoproj.io/secret-type: cluster
    o11y/managed: "true"
    o11y/provider: aws    # 예시
    o11y/stage: prod
    o11y/cluster: app
```

ApplicationSet은 Cluster Generator로 자동 fan-out:

```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          o11y/managed: "true"
template:
  spec:
    source:
      path: 'deploy/envs/{{index .metadata.labels "o11y/provider"}}-{{index .metadata.labels "o11y/stage"}}-{{index .metadata.labels "o11y/cluster"}}/apps'
```

## 버린 옵션과 이유

| 옵션 | 이유 |
|---|---|
| `service → provider → stage` 3-tier (git directories) | 디렉토리 폭발 + Matrix Generator 2-child 한계로 결국 list로 펼쳐야 함 |
| `provider → stage → service` 3-tier | service 보기 어려움 (흩어짐). cluster boundary 직접성 약함 |
| flat composite + list generator | cluster Secret 라벨 활용 못 함. 신규 cluster 추가 시 git 변경 필요 |

## 왜 중요한가

1. **차원을 디렉토리가 아닌 cluster Secret labels에 박으면**:
   - 신규 cluster 추가 = Secret 라벨 갱신 (git 변경 X)
   - 차원 보기 = `kubectl get secrets -l o11y/provider=aws -n argocd`
   - sparse 자연스러움 (빈 디렉토리 X)

2. **Matrix Generator 2-child 한계** (공식): 3차원 직접 매트릭스 불가. 다른 옵션은 결국 list나 git-files로 펼쳐야 함 → cluster generator의 native 차원 표현이 훨씬 깔끔.

3. **Anti-patterns** (Codefresh, Cloudogu):
   - 환경별 git 브랜치 분리 → drift 보장
   - 모든 환경 동시 sync 자동화 → promotion 단계화 필요 (PR/manual)
   - 단일 ApplicationSet에 promotion 로직 → 별도 분리
   - 깊은 디렉토리 nesting (Autopilot 류) → 유지보수 비용↑
   - stable 브랜치/latest 태그 참조 → upgrade surprise + DR 악몽

4. **Conway's Law 정합** (Red Hat): cluster Secret 권한 = cluster ownership boundary. 디렉토리가 아니라 RBAC으로 boundary 표현 → 자연스러움.

5. **"snowflake cluster 피하기"** (monday.com): 평탄 + 라벨 기반 컨벤션이 클러스터 동질성 강제.

## 출처

| 출처 | 유형 | 비고 |
|---|---|---|
| [ApplicationSet Use Cases](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Use-Cases/) | 공식 | generator 종류별 use-case |
| [Cluster Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/) | 공식 | label selector 패턴, manifest 예시 |
| [Matrix Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Matrix/) | 공식 | 2-child 한계 |
| [Red Hat — GitOps directory structure](https://developers.redhat.com/articles/2022/09/07/how-set-your-gitops-directory-structure) | 블로그(2022) | Conway's Law, monorepo vs polyrepo |
| [Cloudogu GitOps Patterns Part 6](https://platform.cloudogu.com/en/blog/gitops-repository-patterns-part-6-examples/) | 블로그 | anti-patterns |
| [Codefresh ArgoCD anti-patterns](https://codefresh.io/blog/argo-cd-anti-patterns-for-gitops/) | 블로그(Argo 진영) | promotion anti-pattern |
| [Akuity GitOps best practices](https://akuity.io/blog/gitops-best-practices-whitepaper) | 블로그(Argo 메인테이너 회사) | monorepo+overlay 표준 |
| [monday.com — multi-cluster engineering](https://engineering.monday.com/building-a-resilient-and-scalable-infrastructure-with-kubernetes-multi-cluster/) | 엔지니어링 블로그 | snowflake / blast-radius lessons |

⚠️ **제외(AI 의심)**: `oneuptime.com/blog/2026-02-*` 류 다수 — 1차 출처 부재, 동일 패턴 글이 짧은 기간에 여러 개. 보조 참고로도 X.
