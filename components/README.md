# components/

Monitoring stack의 **컴포넌트별 jsonnet 소스**. 빌드 시 `main.libsonnet`이 각 컴포넌트를 import해서 `manifests/<type>/*.yaml`로 렌더링한다.

## 디렉토리

| 디렉토리 | 역할 |
|---|---|
| `_lib/` | 공용 jsonnet 헬퍼 — wrap CR/ConfigMap, transform (disable/severity/runbook 정책), AlertmanagerConfig CR ↔ raw 변환 |
| `_external/` | 외부 mixin import wrapper — kubernetes-mixin (활성), cert-manager-mixin (디폴트 OFF) |
| `prometheus/` | 자체 알림 룰 + `_config` (selectors, thresholds) |
| `alertmanager/` | 라우팅 트리 + receivers + inhibit_rules |
| `grafana/` | 자체 대시보드 (현 placeholder, 후속) |

`_` prefix는 "컴포넌트가 아닌 인프라 자원"(라이브러리/외부 import)임을 시각적으로 분리하기 위함.

## 컴포넌트 entry point 컨벤션

각 컴포넌트는 `<name>/mixin.libsonnet`을 entry point로 둔다. 그 안에서 자기 영역의 jsonnet 객체를 export — `prometheusAlerts.groups`, `alertmanagerConfig.{route, receivers, inhibitRules}`, `grafanaDashboards`, `_config` 등 ([kube-prometheus](https://github.com/prometheus-operator/kube-prometheus) 컨벤션과 동일).

`main.libsonnet`이 컴포넌트들을 합쳐서 운영 단위 `baseline` 한 세트로 묶어 manifest를 만든다.

```jsonnet
// main.libsonnet
local prometheus = import 'prometheus/mixin.libsonnet';
local alertmanager = import 'alertmanager/mixin.libsonnet';
local grafana = import 'grafana/mixin.libsonnet';

local baseline = prometheus + alertmanager + grafana;
```

## 컴포넌트 추가 절차

새 도메인(예: `rpc`, `ingress`)이 필요할 때:

1. `components/<domain>/` 디렉토리 생성
2. `<domain>/mixin.libsonnet` 작성 — 자기 영역의 jsonnet 객체 export
3. `main.libsonnet`의 `baseline = prometheus + alertmanager + grafana + <domain>` 추가
4. `make build/test/lint` 통과 확인

상세 가이드는 [docs/adding-a-component.md](../docs/adding-a-component.md).
