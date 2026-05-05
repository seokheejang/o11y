# o11y

> Observability-as-code template: Prometheus rules, Alertmanager configs, and Grafana dashboards.

Kubernetes 클러스터에서 동작하는 [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) 위에 얹는 **observability 콘텐츠 레이어 템플릿**. 알림 룰·Alertmanager 라우팅·Grafana 대시보드를 [Monitoring Mixins](https://monitoring.mixins.dev/) 패턴(jsonnet/grafonnet)으로 한 묶음 관리하고, ArgoCD GitOps로 클러스터에 sync 하는 **참조 구조**를 제공한다.

이 repo는 **fork 해서 자기 환경에 맞게 가져다 쓰는 것**을 전제로 한다. 디렉토리 구조·정책 문서·툴체인 골격을 그대로 두고, `mixins/local/<도메인>-mixin/`만 채워나가면 된다.

> **인프라(차트 자체) 배포는 이 repo가 다루지 않는다.** 클러스터 위에 얹는 콘텐츠 — 알림이 무엇을 보고 무엇을 보내는가 — 만 다룬다.

## Why this repo exists

- **알림은 자주 바뀐다.** 인시던트마다 새 알림이 추가되거나 임계값이 조정된다. 인프라 차트와 다른 cadence를 가진 변경을 같은 repo에 섞으면 신호가 묻힌다.
- **알림과 대시보드는 같은 메트릭을 공유한다.** 라벨/지표 이름이 바뀔 때 한 PR에서 함께 갱신되어야 drift가 안 난다. → 한 repo에 묶음.
- **알림은 코드 리뷰 대상이다.** PR/CODEOWNERS/CI를 거쳐야 alert fatigue를 막을 수 있다.
- **포스트모템 추적성.** 인시던트 → 알림 변경 commit이 audit log로 남는다.

## Repo layout

```
.
├── README.md
├── LICENSE
├── .gitignore
├── Makefile                  # build / test / lint / vendor 타겟
├── jsonnetfile.json          # jsonnet-bundler 의존성 (외부 mixin 목록)
│
├── mixins/                   # mixin 소스
│   ├── local/                    # 자체(in-house) mixin — 도메인별 디렉토리 (rpc-mixin/, dns-mixin/, ...)
│   └── external/                 # 외부 mixin import wrapper (.libsonnet)
│
├── vendor/                   # jb install 결과 (gitignored)
│
├── manifests/                # 빌드 산출물 — 클러스터에 sync 되는 YAML
│   ├── prometheus-rules/         # PrometheusRule CR
│   ├── alertmanager-config/      # AlertmanagerConfig CR
│   └── grafana-dashboards/       # ConfigMap (grafana_dashboard="1" 라벨)
│
├── tests/                    # promtool test rules 입력
│
├── tools/                    # 빌드/검증 헬퍼 스크립트
│
├── docs/
│   ├── alerting-philosophy.md    # SRE 원칙 — 어떤 알림을 만들/안 만들 것인가
│   ├── severity-policy.md        # critical/warning 2단계 정책
│   ├── adding-a-mixin.md         # 외부/자체 mixin 추가 절차
│   └── runbooks/                 # 알림별 대응 절차서
│
├── argocd/                   # ArgoCD Application 매니페스트 (다음 PR에서 동작)
│
└── .github/
    ├── CODEOWNERS
    └── workflows/ci.yml      # promtool / jsonnet-lint / kubeconform (다음 PR에서 활성화)
```

## Quick start

> ⚠️ **현재(1차 PR) 상태**: 디렉토리·문서·툴체인 골격만 잡혀 있다. `make build`/`vendor` 등은 stub이며 다음 PR에서 실구현. 아래 흐름은 향후 동작할 모습.

```bash
# 1. 의존성 설치 (kubernetes-mixin, grafonnet 등 vendor/로 다운로드)
make vendor

# 2. jsonnet → manifests/ 빌드
make build

# 3. 룰 테스트
make test

# 4. (ArgoCD가 sync하는 경우) 자동 반영. 수동 적용 시:
kubectl apply -k manifests/
```

## Concepts

### Monitoring Mixin 패턴

한 컴포넌트(예: kubernetes, RPC 노드, DNS)의 **알림 룰 + 레코딩 룰 + 대시보드**를 jsonnet 한 묶음으로 만든다. CNCF 생태계 표준이며 [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus)가 그대로 쓰는 방식. 외부 mixin은 [monitoring.mixins.dev](https://monitoring.mixins.dev/)에서 import해서 `mixins/external/`에 wrapper를 두고, 자체 mixin은 `mixins/local/`에 둔다. 자세한 추가 절차는 [docs/adding-a-mixin.md](docs/adding-a-mixin.md).

### kube-prometheus-stack sidecar 통합

이 repo가 만드는 산출물은 두 종류:

- **`PrometheusRule` / `AlertmanagerConfig` CR** → Prometheus Operator가 watch하여 자동 reload
- **Grafana dashboard ConfigMap** (`grafana_dashboard: "1"` 라벨 부착) → Grafana sidecar가 watch하여 자동 import

별도 Grafana API 호출/Terraform 없이 **kubectl apply**(또는 ArgoCD sync)만으로 알림과 대시보드가 반영된다.

## Policy & Conventions

| 문서 | 내용 |
|------|------|
| [Alerting Philosophy](docs/alerting-philosophy.md) | "할 일 없으면 알림 만들지 마라" — SRE 원칙 |
| [Severity Policy](docs/severity-policy.md) | `critical` / `warning` 2단계만. 채널/응답 기대 매핑 |
| [Adding a Mixin](docs/adding-a-mixin.md) | 외부 mixin import / 자체 mixin 작성 컨벤션 |
| [Runbooks](docs/runbooks/) | 알림별 대응 절차서 (`runbook_url` annotation 대상) |

## Roadmap

### ✅ 1차 PR — 골격 (현재)
- [x] 디렉토리 구조
- [x] README + 정책 문서 (`docs/`)
- [x] Makefile / `jsonnetfile.json` / CI workflow stub
- [x] CODEOWNERS

### 🚧 2차 PR — 동작하는 빌드 파이프라인
- [ ] `jb install` 실행 + `vendor/` 커밋 정책 결정
- [ ] Makefile build/test/lint 실구현
- [ ] CI에서 `promtool test rules` + `kubeconform` 활성화

### 🚧 3차 PR — 첫 도메인 mixin
- [ ] `mixins/local/rpc-mixin/` — 블록 헤드/peer/sync 알림 + 패널 1세트
- [ ] `docs/runbooks/` — RPC 룬북 초안

### 🚧 4차 PR — 클러스터 sync
- [ ] `argocd/` Application 매니페스트
- [ ] 테스트 클러스터에서 ConfigMap sidecar 픽업 검증
- [ ] Slack/PagerDuty receiver 연결 (Secret은 SealedSecret/SOPS로 별도 repo)

### 🚧 그 이후
- [ ] `mixins/local/dns-mixin/` (권위 DNS 모니터링)
- [ ] `mixins/local/infra-mixin/` (환경 특화 알림)
- [ ] SLO 기반 multi-burn-rate 알림

## References

### Reference repositories (공식 / 인지도 높음)

| Repo | 무엇 |
|------|------|
| [prometheus/prometheus](https://github.com/prometheus/prometheus) | Prometheus 본체 (공식) |
| [prometheus/alertmanager](https://github.com/prometheus/alertmanager) | Alertmanager 본체 (공식) |
| [prometheus-operator/prometheus-operator](https://github.com/prometheus-operator/prometheus-operator) | K8s 위 Prometheus 운영 — `PrometheusRule` / `AlertmanagerConfig` CRD 정의 (공식) |
| [prometheus-operator/kube-prometheus](https://github.com/prometheus-operator/kube-prometheus) | mixin → CR 변환 통합 레퍼런스 — 본 repo 빌드 흐름의 원형 (공식) |
| [prometheus-community/helm-charts](https://github.com/prometheus-community/helm-charts) | `kube-prometheus-stack` 차트 (공식 커뮤니티) |
| [kubernetes-monitoring/kubernetes-mixin](https://github.com/kubernetes-monitoring/kubernetes-mixin) | K8s 클러스터 mixin — 본 repo 디렉토리 구조의 모델 |
| [monitoring-mixins/docs](https://github.com/monitoring-mixins/docs) | Mixin 허브 — [monitoring.mixins.dev](https://monitoring.mixins.dev) 소스 |
| [grafana/grafana](https://github.com/grafana/grafana) | Grafana 본체 (공식) |
| [grafana/grafonnet](https://github.com/grafana/grafonnet) | Grafana 대시보드 jsonnet DSL (공식) |
| [jsonnet-bundler/jsonnet-bundler](https://github.com/jsonnet-bundler/jsonnet-bundler) | `jb` — jsonnet 의존성 관리 (공식) |

### Reading

- [Prometheus — Alerting Best Practices](https://prometheus.io/docs/practices/alerting/) (공식)
- [Google SRE Workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- [Google SRE Book — Practical Alerting](https://sre.google/sre-book/practical-alerting/)

## License

[MIT](LICENSE)
