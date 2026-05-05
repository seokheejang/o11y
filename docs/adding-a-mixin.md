# Adding a Mixin

이 repo는 [Monitoring Mixins](https://monitoring.mixins.dev/) 패턴을 따른다. 한 컴포넌트의 **알림 룰 + 레코딩 룰 + 대시보드**를 jsonnet 한 묶음으로 관리한다.

## 외부 mixin 추가하기

[monitoring.mixins.dev](https://monitoring.mixins.dev/)에서 원하는 mixin을 찾아 `jsonnetfile.json`에 의존성을 추가한다.

### 예: node-exporter mixin 추가

```bash
jb install github.com/prometheus/node_exporter/docs/node-mixin@master
```

`jsonnetfile.json`이 자동 갱신되고 `vendor/` 아래로 다운로드된다.

이후 `mixins/external/node-exporter.libsonnet`을 만들어 import + 우리 환경 라벨/임계값을 override:

```jsonnet
// mixins/external/node-exporter.libsonnet
(import 'github.com/prometheus/node_exporter/docs/node-mixin/mixin.libsonnet') +
{
  _config+:: {
    nodeExporterSelector: 'job="node-exporter"',
    grafanaPrefix: '/grafana',
  },
}
```

`make build`가 이 mixin의 알림/대시보드를 `manifests/` 아래로 렌더링한다.

## 자체 mixin 추가하기

도메인별로 `mixins/local/<name>-mixin/` 디렉토리를 만든다. 컨벤션은 [kubernetes-monitoring/kubernetes-mixin](https://github.com/kubernetes-monitoring/kubernetes-mixin) 구조를 따른다:

```
mixins/local/rpc-mixin/
├── mixin.libsonnet         # 진입점 (config + alerts/rules/dashboards 합성)
├── config.libsonnet        # _config — 셀렉터, 임계값, 라벨
├── alerts.libsonnet        # PrometheusRule (alerting rules)
├── rules.libsonnet         # PrometheusRule (recording rules)
└── dashboards/
    ├── overview.libsonnet
    └── per-node.libsonnet
```

`mixin.libsonnet` 진입점 예:

```jsonnet
{
  _config+:: (import 'config.libsonnet'),
  prometheusAlerts+:: (import 'alerts.libsonnet'),
  prometheusRules+:: (import 'rules.libsonnet'),
  grafanaDashboards+:: {
    'rpc-overview.json': (import 'dashboards/overview.libsonnet'),
    'rpc-per-node.json': (import 'dashboards/per-node.libsonnet'),
  },
}
```

## 빌드 흐름 (다음 PR에서 동작)

```
mixins/{local,external}/     # jsonnet 소스
     │
     ▼  make vendor           (jb install — vendor/ 채움)
     ▼  make build             (jsonnet → out/ → manifests/)
     │
manifests/
├── prometheus-rules/        # PrometheusRule CR YAML
├── alertmanager-config/     # AlertmanagerConfig CR YAML
└── grafana-dashboards/      # ConfigMap (grafana_dashboard="1" 라벨)
     │
     ▼  ArgoCD sync
     │
K8s 클러스터 (kube-prometheus-stack이 흡수)
```

## PR 체크리스트

mixin 추가/수정 PR 머지 전 확인:

- [ ] `make vendor && make build` 성공
- [ ] `make test` (`promtool test rules`) 통과
- [ ] `make lint` 통과
- [ ] 모든 critical 알림에 `runbook_url` annotation 존재
- [ ] 새 알림은 `docs/runbooks/`에 룬북 stub 추가
- [ ] severity는 `critical` 또는 `warning`만 사용 ([severity-policy.md](severity-policy.md))
- [ ] `for:` 평가 윈도우 명시
- [ ] 영향받는 도메인의 CODEOWNER 리뷰
