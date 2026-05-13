# 2026-05-13 — Alertmanager `alertmanagerConfigMatcherStrategy` 선택

> PR-B 의사결정 박제. AlertmanagerConfig가 자동으로 받는 `namespace=<CR_ns>` matcher를 끌지 말지 — `OnNamespace` vs `None` 선택의 근거.

## Why this note exists

prometheus-operator는 AlertmanagerConfig CR을 alertmanager.yml에 머지할 때, 그 CR의 모든 route matchers에 `namespace="<CR이 있는 namespace>"`를 **자동으로 prepend**한다 (디폴트 `alertmanagerConfigMatcherStrategy.type: OnNamespace`). 이 자동 주입은 multi-tenant 격리를 위한 설계지만, single-tenant 운영팀이 cluster-wide alert를 받으려는 시나리오에서는 정확히 함정이 된다. 베이스라인 PR(#5)이 receiver wiring 전 단계에서 이 결정을 분리한 이유.

## Frame — alert가 라우팅 안 되는 메커니즘

```
[1] kubelet/kube-state-metrics → /metrics 노출
        kube_pod_status_ready{namespace="prod-app", pod="api-...", condition="false"} 1

[2] Prometheus가 scrape → TSDB 저장 (metric의 namespace label = 워크로드 ns)

[3] PrometheusRule이 어디에 있든 expression 평가:
        sum by (namespace, pod) (kube_pod_status_ready{condition="false"}) > 0
    → alert.labels = { alertname=KubePodNotReady, namespace=prod-app, severity=warning, ... }
    (alert의 ns label은 metric에서 옴 — PrometheusRule의 ns 아님)

[4] Prometheus → Alertmanager POST
    operator가 OnNamespace 디폴트로 우리 AMC routes에 namespace="monitoring" matcher 자동 prepend
    → alert.namespace="prod-app" ≠ "monitoring" → 매처 fail → root catch-all "null"로 drop ❌
```

→ "Alertmanager는 monitoring ns 안에서만 동작하나?" 라는 흔한 오해의 정답:
**Alertmanager 서버 자체는 monitoring ns의 Pod 1개. 그러나 alert는 모든 ns 워크로드 발화 결과**. ns "안에서만 동작"하는 건 AMC CR의 격리 정책일 뿐, 데이터 흐름은 클러스터 전역.

## 4가지 운영 패턴 비교

| 패턴 | 구성 | 적합 시나리오 | 트레이드오프 |
|---|---|---|---|
| A. **OnNamespace + Selector** (chart 기본) | `alertmanagerConfigSelector` + `matcherStrategy.type: OnNamespace` | Multi-tenant: 팀마다 자기 ns에서 자기 AMC 관리 | ✅ 자동 격리, 충돌 없음 / ❌ cluster-wide alert 못 받음 |
| B. **None + Selector** | `alertmanagerConfigSelector` + `matcherStrategy.type: None` | **Single-tenant ops team, cluster-wide alerts** | ✅ 모든 ns alert 라우팅 / ⚠️ 다른 ns의 AMC가 라우팅에 끼면 충돌 가능 → AMC 단일 작성자 정책 필요 |
| C. **Global via `alertmanagerConfiguration`** (단수) | `spec.alertmanagerConfiguration: <name>` | 단일 글로벌 CR로 전체 라우팅 | ✅ ns 매처 자동 비활성 / ❌ CR 1개만 참조, 여러 CR 합칠 수 없음 (mixin + env override 구조에 부적합) |
| D. **Raw Secret** (pre-CRD) | `alertmanager.yaml` Secret 직접 작성 | 완전 수동 관리 | ✅ 100% 제어 / ❌ GitOps 친화도 낮음, CR 이점 포기 |

## 선택 — 패턴 B (`type: None`)

이 프로젝트가 채택한 모델은:
- 단일 운영팀이 monitoring ns에서 라우팅 운영
- cluster-wide alert(KubePodNotReady, KubeNodeNotReady, PVC fillup 등 워크로드 ns가 prod/kube-system) 수신이 목표
- baseline mixin이 base AMC를 만들고, 향후 env override CR 합칠 가능성 → 단수 필드 패턴 C 부적합

→ Alertmanager CR(operator가 만든 CR, 즉 chart values 또는 환경 인프라 레이어에서 관리)의 spec에 다음 patch:

```yaml
spec:
  alertmanagerConfigMatcherStrategy:
    type: None
```

**이 patch는 이 repo의 mixin 코드 변경 사항이 아니다.** baseline mixin이 만드는 건 AlertmanagerConfig CR이고, matcherStrategy는 그 부모인 Alertmanager CR의 필드. 즉 환경 인프라(helm values 등)에서 적용. repo가 만드는 AMC 자체는 변경 없음.

## 함정 — 자주 빠지는 곳

1. **"selector 없으니 모든 ns alert 들어오겠지" 오해** — 안 들어온다. `OnNamespace`는 `alertmanagerConfigSelector`/`alertmanagerConfigNamespaceSelector`와 별개로, **CR 머지 시 routes/inhibit_rules 안에 `namespace=<CR ns>` matcher를 자동 prepend**한다. kube-prometheus-stack issue [#4999](https://github.com/prometheus-community/helm-charts/issues/4999) (2024-11)에서 정확히 같은 함정 보고됨.

2. **`None`으로 바꾸면 격리 사라짐** — 같은 Alertmanager가 watch 하는 모든 ns의 AMC가 ns matcher 없이 머지됨. 정책: AMC를 단일 ns(monitoring)에서만 작성하고 `alertmanagerConfigSelector`로 그 ns/label만 선택. 다른 팀이 AMC를 임의로 못 만들도록 RBAC 또는 ValidatingAdmissionPolicy로 추가 방어 가능.

3. **`alertmanagerConfiguration` (단수) vs `alertmanagerConfigSelector` (복수) 헷갈림** — 단수 필드 사용 시에도 ns matcher 자동 비활성되지만, CR 1개만 받음. mixin + env override 구조엔 부적합.

4. **PrometheusRule엔 ns matcher 안 붙음** — `PrometheusRule` CR은 어디 있든 ruleSelector로 선택되며, alert의 ns label은 metric의 ns(워크로드 ns). 정상 동작. AMC만 다른 정책.

5. **amtool routes test의 한계** — `amtool routes test`는 routing tree만 평가하고 **inhibit_rules는 평가 안 한다**. inhibit는 `amtool check-config`로 syntax/equal-label까지만 검증. 의도와 다르게 좁아진 inhibit가 routing test에서 안 잡힘.

## 의도적으로 채택하지 **않은** 패턴

| 패턴 | 안 쓴 이유 |
|---|---|
| OnNamespace 유지 + AMC를 모든 워크로드 ns에 복제 | 알람 종류마다 ns 매처 매핑 관리 부담, GitOps 무한 복제 |
| AMC를 workload ns(예: kube-system)에 두기 | kube-system 안에 라우팅 정책 두는 게 운영 책임 경계와 안 맞음 |
| `alertmanagerConfiguration` (단수 필드) | 단일 CR 제약 — mixin이 기본 라우팅 정의 + env가 override 하는 구조 막힘 |
| ClusterAlertmanagerConfig (cluster-scoped CR) | 아직 미구현 (커뮤니티 RFC 단계, 2026-05 기준). 향후 도입되면 마이그레이션 검토 |

## 설계 배경 (1차 출처)

**디폴트가 `OnNamespace`인 이유** — maintainer `brancz` ([Discussion #3733](https://github.com/prometheus-operator/prometheus-operator/discussions/3733)):
> "That's kind of the point of the feature, otherwise it's possible that alertmanager configs in different namespaces conflict and Alertmanager won't be able to start."

즉 디폴트는 "여러 팀이 각자 ns에 자기 AMC를 두는 multi-tenant" 가정. 충돌 방지 목적.

**`None` 옵션이 추가된 배경** — [Issue #3737](https://github.com/prometheus-operator/prometheus-operator/issues/3737) (2020-12, 사용자 `bshifter`), [Issue #3750](https://github.com/prometheus-operator/prometheus-operator/issues/3750):
- aggregated metrics에 ns label 없음 (예: Kafka lag)
- cluster-wide K8s alerts — 어떤 ns에서든 발화 가능
- external alerts — non-K8s 소스

[PR #5084](https://github.com/prometheus-operator/prometheus-operator/pull/5084) (2022-11-17 머지, maintainer `simonpasquier` 승인)에서 enum 패턴으로 확장 가능하게 추가. 즉 패턴 B는 메인테이너가 **정확히 이 use case를 위해** 설계한 경로.

## Sources

**1차 (공식 GitHub / 메인테이너 발언)**:
- [Issue #3737 — Make AlertmanagerConfig namespace label matching optional](https://github.com/prometheus-operator/prometheus-operator/issues/3737)
- [Issue #3750 — Alerts should not be required to match an AMC's namespace](https://github.com/prometheus-operator/prometheus-operator/issues/3750)
- [Discussion #3733 — Why does AMC automatically add a namespace matcher](https://github.com/prometheus-operator/prometheus-operator/discussions/3733)
- [PR #5084 — add alertmanagerConfigMatcherStrategy toggle](https://github.com/prometheus-operator/prometheus-operator/pull/5084)

**1차 (공식 문서 / CRD)**:
- [Prometheus Operator — Alerting Routes](https://prometheus-operator.dev/docs/developer/alerting/)
- [prometheus-operator monitoring/v1 Go package reference](https://pkg.go.dev/github.com/prometheus-operator/prometheus-operator/pkg/apis/monitoring/v1)

**커뮤니티 실제 사례**:
- [kube-prometheus-stack Issue #4999 — AMC only receives from a specific namespace](https://github.com/prometheus-community/helm-charts/issues/4999) (2024-11)
- [helm-charts Issue #3260 — Alertmanager auto override label with current k8s namespace](https://github.com/prometheus-community/helm-charts/issues/3260)
