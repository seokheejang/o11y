# 2026-05-21 — `ingressControllerEnabled` flag와 alert group 조건부 비활성

**Category**: architecture
**Related**: [`components/prometheus/config.libsonnet`](../../components/prometheus/config.libsonnet), [`components/prometheus/alerts.libsonnet`](../../components/prometheus/alerts.libsonnet), [`docs/runbooks/IngressControllerDown.md`](../runbooks/IngressControllerDown.md)

## Why this note exists

`baseline-network` alert group(IngressControllerDown / HighIngress5xxRate / HighIngress4xxRate)은 `nginx_ingress_controller_*` 시리즈와 `up{ingressControllerSelector}` 시리즈에 의존한다. 클러스터가 ingress-nginx를 운영하지 않는 경우 — 예: Gateway API, traefik, 또는 ingress 자체를 사용하지 않는 internal-only 클러스터 — 이 alert들은 두 가지 noise를 만든다.

1. **`IngressControllerDown` 영구 firing**: `absent(up{...} == 1)`이 항상 참 → critical alert이 영구 발화 → AlertManager에서 영구 silenced 처리로 전환 → silence 만료/누락 시 알림 폭주 위험.
2. **Dormant 룰 누적**: 메트릭이 존재하지 않는 환경에서도 `rules.yaml`에 정의는 남아 evaluation cost를 소모하고, 운영자가 "왜 안 떠?"를 디버깅하는 false signal을 만든다.

silence나 disable list로 alert를 하나씩 처리할 수도 있지만, 같은 카테고리의 룰이 묶여있다면 **group 단위로 통째로 비활성**하는 편이 명시적이고 유지보수가 쉽다.

## 선택 — `_config` flag로 group 자체를 jsonnet 빌드 시점에 제외

`components/prometheus/config.libsonnet`에 flag 추가 (디폴트 true):

```jsonnet
{
  _config+:: {
    ingressControllerSelector: 'job=~"ingress-nginx-controller-metrics|nginx-ingress.*"',
    ingressControllerEnabled: true,
    // ...
  },
}
```

`components/prometheus/alerts.libsonnet`에서 group을 조건부 합성:

```jsonnet
{
  prometheusAlerts+:: {
    groups+: [
      { name: 'baseline-meta', rules: [ /* ... */ ] },
    ] + (if $._config.ingressControllerEnabled then [
      { name: 'baseline-network', rules: [ /* IngressControllerDown, 5xx, 4xx */ ] },
    ] else []) + [
      { name: 'baseline-dns', rules: [ /* ... */ ] },
      // ...
    ],
  },
}
```

ingress가 없는 클러스터를 가진 fork는 `main.libsonnet`에서 override:

```jsonnet
local prometheus = (import 'prometheus/mixin.libsonnet') + {
  _config+:: { ingressControllerEnabled: false },
};
```

빌드 결과(`manifests/prometheus-rules/baseline.yaml`)에서 `baseline-network` group이 통째로 빠진다. PrometheusRule에 dormant alert가 남지 않으며, Prometheus는 해당 그룹 자체를 evaluate하지 않는다.

## 트레이드오프 — 왜 jsonnet flag인가

| 옵션 | 장점 | 단점 |
|---|---|---|
| **A. jsonnet `_config` flag (선택)** | 빌드 시점에 group 자체가 빠짐 — runtime cost 0, 명시적 | env마다 fork에서 `main.libsonnet` 한 줄 override 필요 |
| B. AlertManager silence | runtime 처리, mixin 코드 변경 X | 실수로 silence 만료/삭제 시 알림 폭주, silence 관리 부담 |
| C. `k8sDisabledAlerts` 리스트에 알람 이름 추가 | 기존 mechanism 재사용 | group이 아닌 alert 단위 — 3개 알람을 각각 추가, group 자체는 남음 |
| D. env fork에서 alerts.libsonnet 재작성 | 100% 제어 | 코드 중복, 본가(이 repo) 업데이트 머지 시 충돌 |

A가 가장 적은 코드로 group 단위 의도를 표현. ingress controller가 추후 추가되는 시점에는 fork의 `main.libsonnet`에서 override 한 줄 제거(또는 true) — 빌드 결과에 group이 다시 들어온다.

## 일반화 가능성

같은 패턴은 다른 선택적 컴포넌트에도 적용 가능:

- `corednsEnabled` — 비-K8s DNS 사용 클러스터
- `nodeExporterEnabled` — managed 노드(EKS Fargate 등)
- `kubeStateMetricsEnabled` — 메트릭 출처를 외부 monitoring으로 위임한 환경

현재는 ingress 한 가지만 flag화. 추가 환경 요구가 누적되면 같은 패턴을 확장한다 — 핵심은 **flag가 group(또는 selector dependent rule 집합) 단위 결정을 jsonnet 빌드 시점에 명시화**한다는 점.

## 함정

1. **`_config+::`의 `+::`는 dict deep merge.** `main.libsonnet`에서 `_config+:: { ingressControllerEnabled: false }`로 override하면 다른 필드(`runbookBase`, `thresholds`)는 디폴트가 유지된다. `::`(필드 hide) vs `+::`(merge) 혼동 주의.

2. **selector(`ingressControllerSelector`)는 그대로 둔다.** flag로 group을 끄더라도 selector 정의를 지우면 다른 mixin이 참조할 수 있는 형식 호환이 깨진다. group 합성만 조건부, selector는 baseline 정의 유지.

3. **빌드 결과 검증 필수.** flag 변경 후 `make build` → `manifests/prometheus-rules/baseline.yaml`에서 의도한 group이 빠졌는지 grep으로 확인:
   ```bash
   make build
   grep -c "name: baseline-network" manifests/prometheus-rules/baseline.yaml
   # ingressControllerEnabled=true → 1, false → 0
   ```
