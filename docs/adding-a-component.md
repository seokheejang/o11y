# Adding a Component

이 repo는 [Monitoring Mixins](https://monitoring.mixins.dev/) 패턴을 monitoring stack의 **컴포넌트별 디렉토리**로 표현한다. 한 컴포넌트(예: prometheus, alertmanager, grafana, 후속 rpc/ingress)는 자기 영역의 **알림 룰 + 레코딩 룰 + 대시보드 + 라우팅**을 jsonnet 한 묶음(`components/<name>/`)으로 export.

## 외부 mixin 추가하기 (`components/_external/`)

[monitoring.mixins.dev](https://monitoring.mixins.dev/)에서 원하는 mixin을 찾아 `jsonnetfile.json`에 의존성을 추가.

> **외부 mixin은 rules만 가져온다.** 대시보드는 `kube-prometheus-stack` 차트가 동일 mixin 출처에서 디폴트로 ConfigMap을 만들어주므로 중복 회피. (자체 컴포넌트는 rules + dashboards 모두 export.)

### 예: node-exporter mixin 추가

```bash
jb install github.com/prometheus/node_exporter/docs/node-mixin@master
```

`jsonnetfile.json`이 자동 갱신되고 `vendor/` 아래로 다운로드된다.

이후 `components/_external/node-exporter.libsonnet`을 만들어 import + 환경 라벨/임계값을 override:

```jsonnet
// components/_external/node-exporter.libsonnet
(import 'github.com/prometheus/node_exporter/docs/node-mixin/mixin.libsonnet') +
{
  _config+:: {
    nodeExporterSelector: 'job="node-exporter"',
    grafanaPrefix: '/grafana',
  },
}
```

`main.libsonnet`에서 import + 활성화하면 `make build`가 이 mixin의 알림/레코딩 룰을 `manifests/prometheus-rules/`에 렌더링한다.

## 자체 컴포넌트 추가하기 (`components/<name>/`)

도메인별로 `components/<name>/` 디렉토리를 만든다. 컨벤션은 [kubernetes-monitoring/kubernetes-mixin](https://github.com/kubernetes-monitoring/kubernetes-mixin) 구조를 따른다:

```
components/rpc/
├── mixin.libsonnet         # 진입점 (config + alerts/rules/dashboards 합성, 다른 컴포넌트와 + 으로 합쳐짐)
├── config.libsonnet        # _config — 셀렉터, 임계값, 라벨
├── alerts.libsonnet        # PrometheusRule (alerting rules)
├── rules.libsonnet         # PrometheusRule (recording rules)
├── dashboards/
│   ├── overview.libsonnet
│   └── per-node.libsonnet
└── README.md               # 카피본 동료 onboarding용
```

`mixin.libsonnet` 진입점 예:

```jsonnet
// components/rpc/mixin.libsonnet
{
  _config+:: (import 'config.libsonnet')._config,
  prometheusAlerts+:: (import 'alerts.libsonnet'),
  prometheusRules+:: (import 'rules.libsonnet'),
  grafanaDashboards+:: {
    'rpc-overview.json': (import 'dashboards/overview.libsonnet'),
    'rpc-per-node.json': (import 'dashboards/per-node.libsonnet'),
  },
}
```

`main.libsonnet`에 다음 추가:

```jsonnet
local rpc = import 'rpc/mixin.libsonnet';
local baseline = prometheus + alertmanager + grafana + rpc;
```

## 빌드 흐름

```
components/{_lib,_external,<comp>}/     jsonnet 소스
     │
     ▼  make vendor           (jb install — vendor/ 채움)
     ▼  make build            (jsonnet -J vendor -J components → out/ → manifests/)
     │
manifests/
├── prometheus-rules/        # PrometheusRule CR YAML
├── alertmanager-config/     # AlertmanagerConfig CR YAML
└── grafana-dashboards/      # ConfigMap (grafana_dashboard="1" 라벨)
     │
     ▼  ArgoCD sync           (deploy/argocd/appset-o11y.yaml 기반)
     │
K8s 클러스터 (kube-prometheus-stack이 흡수)
```

## 컴포넌트 분리 가이드

새 영역을 어떤 컴포넌트로 분리할지 모호하면:

| 신호 | 컴포넌트 |
|---|---|
| `PrometheusRule` / recording rule / alerts | `prometheus/` 또는 새 도메인 컴포넌트 |
| Alertmanager `route` / `receivers` / `inhibit_rules` | `alertmanager/` (현재 단일) |
| Grafana dashboard | 도메인 컴포넌트 안 `dashboards/` (예: `rpc/dashboards/`) — `grafana/`는 공용 헬퍼만 |
| 도메인 특정 (RPC node, ingress) 전체 영역 | 새 디렉토리 `components/<domain>/` |

## PR 체크리스트

컴포넌트 추가/수정 PR 머지 전 확인:

- [ ] `make vendor && make build` 성공
- [ ] `make test` (`promtool test rules` + `amtool routes test`) 통과
- [ ] `make lint` (`kubeconform`) 통과
- [ ] 모든 critical 알림에 `runbook_url` annotation 존재 (`components/_lib/transform.libsonnet`이 strict 검증)
- [ ] 새 알림은 `docs/runbooks/`에 룬북 stub 추가
- [ ] severity는 `critical` 또는 `warning`만 사용 ([severity-policy.md](severity-policy.md))
- [ ] `for:` 평가 윈도우 명시
- [ ] 컴포넌트 디렉토리에 `README.md` 추가 (카피본 동료 onboarding 가이드)
- [ ] 영향받는 도메인의 CODEOWNER 리뷰
