# 2026-05-21 — GitOps 안전화: stateful chart App과 PVC 3중방어

**Category**: operations
**Related**: [`deploy/envs/example-dev/apps/kube-prometheus-stack.yaml`](../../deploy/envs/example-dev/apps/kube-prometheus-stack.yaml), [`deploy/envs/example-dev/values.yaml`](../../deploy/envs/example-dev/values.yaml), [`docs/deploying.md`](../deploying.md)

## Why this note exists

`o11y-rules` Application은 mixin 빌드 산출물(PrometheusRule + AlertmanagerConfig)만 sync하므로 잘못 prune되어도 `make build`로 재생성된다. 반면 `kube-prometheus-stack` chart Application은 보통 기존 helm release(Prometheus/Grafana 본체 + 운영 데이터 PVC)를 adopt한 stateful App이다. ArgoCD가 ownership을 가진 상태에서 selfHeal/prune이 잘못 트리거되면 운영 데이터(시계열, 대시보드, datasource 설정)가 손실될 위험이 있다. 이 노트는 두 App을 risk 기반으로 차등 운영하는 패턴과, PVC를 세 layer로 보호하는 설계를 박제한다.

## Frame — 두 Application의 위험 비대칭

| App | 관리 대상 | 재생성 비용 | sync 정책 |
|---|---|---|---|
| `o11y-rules` | PrometheusRule, AlertmanagerConfig, Grafana dashboard ConfigMap | `make build`로 재생성 가능 (코드만) | **auto + selfHeal + prune** |
| `kube-prometheus-stack` | Prometheus/AlertManager StatefulSet, Grafana Deployment, **PVC** | 데이터 손실 시 복구 불가 (시계열·대시보드·datasource) | **manual sync** |

`ApplicationSet` 한 template이 모든 child에 같은 `syncPolicy`를 강제하지는 않는다 — child app yaml 자체에서 `syncPolicy.automated`를 누락시키면 그 child만 수동 모드가 된다. 운영자가 fork에서 명시적으로 선택할 수 있는 분기점.

## 선택 — chart App만 수동 sync

`deploy/envs/<env>/apps/kube-prometheus-stack.yaml`에서 `automated` 블록을 제거:

```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    - RespectIgnoreDifferences=true
# automated 블록 의도적 제거 → 수동 sync (안전 디폴트)
```

`apps/o11y-rules.yaml`은 `automated: { prune: true, selfHeal: true }` 그대로 유지.

운영 흐름:
1. `values.yaml` / `values-base.yaml` 변경을 git에 push
2. ArgoCD UI에서 chart App diff 확인
3. 사람이 검토 후 `Sync` 버튼 (또는 `argocd app sync <name>`)

### 빈 클러스터에 신규 배포라면

stateful 자원이 없으므로 위험이 낮다. fork에서 `automated` 블록을 다시 추가해도 무방. 이 디폴트는 **운영 중 클러스터에 adopt하는 fork를 위한 안전 baseline**이다.

## PVC 3중방어

PVC를 세 다른 layer에서 보호 — 각 layer가 막는 attack surface가 다르다.

| Layer | 어디 | 수단 | 막는 시나리오 |
|---|---|---|---|
| L1 | `apps/kube-prometheus-stack.yaml` | `syncPolicy.automated` 제거 (수동 sync) | 검토 없는 자동 chart upgrade가 PVC를 prune |
| L2 | `values.yaml` (annotation으로 PVC에 박힘) | `argocd.argoproj.io/sync-options: Prune=false,Delete=false` | ArgoCD가 git에서 PVC 정의가 사라져도 / App cascade 삭제 시에도 PVC 보존 |
| L3 | 클러스터 StorageClass | `reclaimPolicy: Retain` (repo 외부 설정) | 사람이 직접 `kubectl delete pvc` 실수해도 underlying PV(데이터 본체) 보존 |

### Layer별 시나리오 매핑

| 시나리오 | L1 | L2 | L3 | 결과 |
|---|---|---|---|---|
| git에서 PVC 정의 누락 | ✅ 수동 sync diff에서 발견 | ✅ sync해도 prune X | — | PVC + PV + 서비스 가용 |
| `kubectl delete pvc` 사람 실수 | 무관 | 무관 | ✅ PV 데이터 보존 | 서비스 다운, 데이터는 PV에 있어 수동 rebind로 복구 |
| chart upgrade가 ruleSelector 오변경 | ✅ 수동 sync diff에서 발견 | 무관 | 무관 | L1 없으면 알람 갭 발생 |

**Retain 단일 layer는 만능이 아니다.** 데이터 본체는 보존되지만 PVC가 삭제된 시점에 mount가 끊겨 서비스는 다운. L2가 있어야 PVC 자체가 prune되지 않아 무중단 유지. L1은 stateful과 무관한 변경(예: ruleSelector)도 게이트한다.

### Grafana PVC vs Prometheus PVC

| PVC | Layer 2 annotation 적용 | 비고 |
|---|---|---|
| Grafana (`grafana.persistence.annotations`) | ✅ chart values에서 직접 PVC에 박힘 | 패턴 그대로 활용 |
| Prometheus (`prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.metadata.annotations`) | ⚠️ 기존 PVC에는 박히지 않을 수 있음 — StatefulSet `volumeClaimTemplates` immutable + chart App `ignoreDifferences`에 포함된 경우 | ArgoCD 미관리 PVC + L3 Retain 조합으로 보호되면 무해 |

신규 배포(빈 클러스터)에서는 L2도 정상 적용. adopt한 환경에서 기존 Prometheus PVC에 annotation이 안 박혔다면 storageClass의 `reclaimPolicy: Retain`이 단독 backstop으로 동작해야 한다.

## 함정

1. **`syncPolicy.automated`를 라이브에서 patch — ApplicationSet이 revert.**
   `ApplicationSet` template이 child의 truth source. `kubectl patch app ... syncPolicy.automated=null` 명령은 성공 출력이 나오지만 즉시 revert된다. 정공법은 **git의 child app yaml에서 `automated`를 제거하고 push** — root app-of-apps가 git을 desired로 보고 child spec을 그대로 적용한다.

2. **`ignoreDifferences`와 chart values 충돌.**
   `alertmanagerConfigMatcherStrategy` 같은 필드를 `ignoreDifferences`에 박은 상태에서 같은 필드를 chart values로 관리하면, ArgoCD가 그 필드를 영원히 ignore하여 cluster CR에 반영되지 않는다. chart values를 single source of truth로 쓸 거면 `ignoreDifferences`에서 빼야 한다. 비상시에만 `patches/` 디렉토리로 manual 적용.

3. **`Prune=false` 어노테이션이 신규 PVC에만 적용.**
   StatefulSet의 `volumeClaimTemplates`는 생성 후 immutable. 기존 PVC에는 chart values 변경이 반영되지 않는다. adopt한 환경에서는 별도로 `kubectl annotate pvc` 또는 reclaimPolicy 의존.

## 트레이드오프

| 측면 | 수동 sync의 비용 | 안 했을 때 비용 |
|---|---|---|
| 운영 부담 | chart values 변경 시 ArgoCD UI에서 1회 클릭 (혹은 `argocd app sync`) | 0 |
| 변경 가시성 | diff 검토 강제 → 잘못된 변경 차단 가능 | selfHeal이 즉시 적용, 사고 시 reactive |
| 사고 blast radius | small (사람 게이트가 첫 방어선) | large (자동화 사고가 운영 데이터까지) |

운영 데이터가 있는 stateful App에서는 수동 sync의 비용이 사고 비용을 압도적으로 정당화한다.
