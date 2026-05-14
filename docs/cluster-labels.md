# Cluster labels reference

ArgoCD cluster Secret에 박아야 하는 라벨 컨벤션. ApplicationSet([`deploy/argocd/appset-o11y.yaml`](../deploy/argocd/appset-o11y.yaml))이 이 라벨로 환경을 자동 picking + 디렉토리 path를 합성한다.

## 라벨 컨벤션

| Key | Value | 의미 |
|---|---|---|
| `argocd.argoproj.io/secret-type` | `cluster` | ArgoCD가 cluster Secret으로 인식 (필수) |
| `o11y/managed` | `"true"` | 본 ApplicationSet의 sync 대상 (필터) |
| `o11y/provider` | provider 분류 (예: `aws`, `gcp`, `on-prem`) | 인프라 provider |
| `o11y/stage` | `dev` \| `prod` | 배포 stage |
| `o11y/cluster` | `<role>` | 워크로드 role / 클러스터 정체성 |

ApplicationSet path 합성:
- `deploy/envs/{provider}-{stage}-{cluster}/apps`
- 예: `o11y/provider=aws, o11y/stage=prod, o11y/cluster=app` → `deploy/envs/aws-prod-app/apps`

## cluster Secret 만들기

### 외부 cluster 등록 (mgmt → target)

```bash
argocd cluster add <kubeconfig-context> \
  --label o11y/managed=true \
  --label o11y/provider=<provider> \
  --label o11y/stage=<dev|prod> \
  --label o11y/cluster=<role>
```

또는 manifest로 직접:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <cluster-name>
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    o11y/managed: "true"
    o11y/provider: aws
    o11y/stage: prod
    o11y/cluster: app
type: Opaque
stringData:
  name: <cluster-name>
  server: https://<api-server-url>
  config: |
    {
      "bearerToken": "<token>",
      "tlsClientConfig": {"insecure": false, "caData": "<base64-ca>"}
    }
```

### Self-managed cluster (in-cluster)

ArgoCD 디폴트 `in-cluster` entry는 cluster Secret이 아니라 본체 설정 항목 — Cluster Generator의 `selector`에 잡히지 않는다. 따라서 in-cluster도 명시적 Secret으로 등록해야 selector가 hit.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: in-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    o11y/managed: "true"
    o11y/provider: <provider>
    o11y/stage: <stage>
    o11y/cluster: <role>
type: Opaque
stringData:
  name: in-cluster
  server: https://kubernetes.default.svc
  config: |
    {"tlsClientConfig":{"insecure":false}}
```

> ⚠️ ArgoCD 디폴트 `in-cluster` 항목과 이름 충돌 가능 — `argocd-cm` ConfigMap의 `clusters` 항목 또는 ArgoCD 설치 옵션 확인.

## 변경 시 동작

| 변경 | 동작 |
|---|---|
| 새 cluster Secret + 라벨 박기 | ApplicationSet이 새 root App 자동 생성 |
| 라벨 변경 (예: `o11y/cluster` rename) | root App 이름·path 갱신 → 기존 prune + 새 sync |
| `o11y/managed: "true"` 제거 | ApplicationSet이 root App finalize → 자원 정리 |

## 검증 (read-only)

```bash
# o11y 대상 cluster 목록
kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster,o11y/managed=true

# provider별
kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster,o11y/provider=aws

# ApplicationSet이 generate한 root Application들
kubectl -n argocd get applications -l app.kubernetes.io/component=app-of-apps,app.kubernetes.io/part-of=o11y
```

## 참고

- 결정 배경: [`docs/learnings/2026-05-14-argocd-appset-cluster-generator.md`](learnings/2026-05-14-argocd-appset-cluster-generator.md)
- ApplicationSet 정의: [`deploy/argocd/appset-o11y.yaml`](../deploy/argocd/appset-o11y.yaml)
- ArgoCD 공식: [Cluster Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/)
