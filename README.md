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
│   ├── main.libsonnet            # 빌드 진입점 — multi-output 키 생성 (manifests/<kind>/<name>)
│   ├── lib/                      # CR/ConfigMap wrapping 헬퍼
│   ├── local/                    # 자체(in-house) mixin — 도메인별 디렉토리 (rpc-mixin/, dns-mixin/, ...)
│   └── external/                 # 외부 mixin import wrapper (.libsonnet)
│
├── vendor/                   # jb install 결과 (gitignored)
├── out/                      # 빌드 부산물 (promtool/amtool용 raw 형식, gitignored)
│
├── manifests/                # 빌드 산출물 — 클러스터에 sync 되는 YAML
│   ├── prometheus-rules/         # PrometheusRule CR
│   ├── alertmanager-config/      # AlertmanagerConfig CR (severity 라우팅 + inhibit_rules)
│   └── grafana-dashboards/       # ConfigMap (grafana_dashboard="1" 라벨)
│
├── tests/                    # promtool test rules + amtool routing 단언 입력
│
├── tools/                    # 빌드/검증 헬퍼 스크립트 (build.sh, validate.sh)
│
├── e2e/                      # 로컬 kind e2e 골격 (cluster + kube-prometheus-stack)
│
├── docs/
│   ├── alerting-philosophy.md    # SRE 원칙 — 어떤 알림을 만들/안 만들 것인가
│   ├── severity-policy.md        # critical/warning 2단계 정책
│   ├── adding-a-mixin.md         # 외부/자체 mixin 추가 절차
│   ├── runbooks/                 # 알림별 대응 절차서
│   └── learnings/                # 의사결정 노트 (도구 선택 근거 등)
│
├── argocd/                   # ArgoCD Application 매니페스트 (4차 PR에서 채움)
│
└── .github/
    ├── CODEOWNERS
    └── workflows/ci.yml      # build / promtool test / kubeconform
```

## Quick start

```bash
# 0. 도구 설치 (jsonnet/jb/gojsontoyaml/promtool/amtool/kubeconform/yq/kind/helm/kubectl)
tools/install.sh                    # 전체 설치 (멱등)
tools/install.sh --check            # 설치 상태만 점검

# 1. mixin 의존성 다운로드 → vendor/
make vendor

# 2. jsonnet → manifests/ 빌드
make build

# 3. 룰 테스트 + 매니페스트 스키마 검증
make test
make lint

# 4. (ArgoCD가 sync하는 경우) 자동 반영. 수동 적용 시:
kubectl apply -R -f manifests/
```

로컬 kind 클러스터에 올려서 실제 admit 되는지 보고 싶으면 `make e2e-up` (자세한 건 [e2e/README.md](e2e/README.md)).

도구 버전 핀과 설치 경로 상세는 [tools/README.md](tools/README.md) 참고.

## Concepts

### Monitoring Mixin 패턴

한 컴포넌트(예: kubernetes, RPC 노드, DNS)의 **알림 룰 + 레코딩 룰 + 대시보드**를 jsonnet 한 묶음으로 만든다. CNCF 생태계 표준이며 [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus)가 그대로 쓰는 방식. 외부 mixin은 [monitoring.mixins.dev](https://monitoring.mixins.dev/)에서 import해서 `mixins/external/`에 wrapper를 두고, 자체 mixin은 `mixins/local/`에 둔다. 자세한 추가 절차는 [docs/adding-a-mixin.md](docs/adding-a-mixin.md).

### kube-prometheus-stack sidecar 통합

이 repo가 만드는 산출물은 두 종류:

- **`PrometheusRule` / `AlertmanagerConfig` CR** → Prometheus Operator가 watch하여 자동 reload
- **Grafana dashboard ConfigMap** (`grafana_dashboard: "1"` 라벨 부착) → Grafana sidecar가 watch하여 자동 import

별도 Grafana API 호출/Terraform 없이 **kubectl apply**(또는 ArgoCD sync)만으로 알림과 대시보드가 반영된다.

## Toolchain

빌드/검증 파이프라인이 쓰는 도구들. `tools/install.sh`이 OS/arch 감지해서 한 방에 설치한다 — 자세한 핀 버전·설치 경로는 [tools/README.md](tools/README.md).

| 도구 | 역할 | 본 repo에서의 쓰임 |
|---|---|---|
| [`jsonnet`](https://github.com/google/go-jsonnet) | JSON을 코드로 만드는 데이터 템플릿 언어 (Go 구현) | mixin 소스 컴파일 — `mixins/main.libsonnet` → JSON → YAML |
| [`jb`](https://github.com/jsonnet-bundler/jsonnet-bundler) | jsonnet 의존성 관리자 (npm/cargo 같은 역할) | `jsonnetfile.json`의 외부 mixin을 `vendor/`에 받음 |
| [`gojsontoyaml`](https://github.com/brancz/gojsontoyaml) | JSON → YAML 변환기 (필드 순서 안정) | jsonnet 출력 → kubectl이 읽는 YAML |
| [`yq`](https://github.com/mikefarah/yq) | YAML용 jq | PrometheusRule CR에서 `.spec`만 추출해 promtool에 먹임 |
| [`promtool`](https://github.com/prometheus/prometheus/tree/main/cmd/promtool) | Prometheus 공식 CLI — 룰 검증·테스트 | `tests/*.yaml`의 알림 발화/억제 단언 (회귀 방지) |
| [`amtool`](https://github.com/prometheus/alertmanager/tree/main/cmd/amtool) | Alertmanager 공식 CLI — 설정·라우팅 검증 | AlertmanagerConfig 문법 검사(`check-config`) + severity 매처가 의도한 receiver로 가는지 단언(`config routes test`) |
| [`kubeconform`](https://github.com/yannh/kubeconform) | K8s 매니페스트 스키마 검증 (kubeval 후속) | 빌드된 `manifests/`가 K8s 1.x + CRD 스키마와 맞는지 |
| [`kind`](https://kind.sigs.k8s.io/) | Docker 컨테이너로 띄우는 K8s 클러스터 | `e2e/`에서 kube-prometheus-stack 위에 manifests 배포 검증 |
| [`helm`](https://helm.sh/) / [`kubectl`](https://kubernetes.io/docs/tasks/tools/) | K8s 표준 도구 | e2e에서 kube-prometheus-stack 차트 설치 + manifests apply |

### 왜 amtool이 별도 도구인가

AlertmanagerConfig CR(`monitoring.coreos.com/v1alpha1`)의 spec은 **raw alertmanager.yml과 필드명이 다르다** (`groupBy` vs `group_by`, `matchers: [{name,value,matchType}]` vs `matchers: ["severity=\"critical\""]` 등). 운영 클러스터의 alertmanager 본체는 raw 형식만 이해하므로 amtool도 raw만 받는다.

본 repo는 jsonnet에서 routing intent 객체를 정의하고 [`mixins/lib/alertmanager.libsonnet`](mixins/lib/alertmanager.libsonnet)이 양쪽으로 변환한다 — 클러스터에 sync되는 CR(`manifests/alertmanager-config/`)과 amtool 검증용 raw(`out/alertmanager-config-raw/`). 이렇게 해야 "라우팅 단언이 통과한 그 라우팅이 클러스터에 들어간다"가 같은 source-of-truth로 보장된다.

## Policy & Conventions

| 문서 | 내용 |
|------|------|
| [Alerting Philosophy](docs/alerting-philosophy.md) | "할 일 없으면 알림 만들지 마라" — SRE 원칙 |
| [Severity Policy](docs/severity-policy.md) | `critical` / `warning` 2단계만. 채널/응답 기대 매핑 |
| [Adding a Mixin](docs/adding-a-mixin.md) | 외부 mixin import / 자체 mixin 작성 컨벤션 |
| [Runbooks](docs/runbooks/) | 알림별 대응 절차서 (`runbook_url` annotation 대상) |

## Roadmap

### ✅ 1차 PR — 골격
- [x] 디렉토리 구조
- [x] README + 정책 문서 (`docs/`)
- [x] Makefile / `jsonnetfile.json` / CI workflow stub
- [x] CODEOWNERS

### ✅ 2차 PR — 동작하는 빌드 파이프라인
- [x] `jb install` + `jsonnetfile.lock.json` commit (vendor/는 gitignored)
- [x] Makefile build/test/lint 실구현 (`tools/build.sh` + `tools/validate.sh`)
- [x] CI에서 `promtool test rules` + `kubeconform` 활성화
- [x] 외부 mixin 1개(kubernetes-mixin) wrap — 빌드 동작 증명
- [x] 로컬 kind e2e 골격 (`e2e/`) — cluster up + manifests apply까지

### ✅ 베이스라인 PR — 운영 알림 베이스라인 (현재)
- [x] kubernetes-mixin noisy 7개 disable (`mixins/main.libsonnet` 코멘트에 근거 issue 링크)
- [x] 자체 `mixins/local/baseline-mixin/` — critical 5 + warning 5
- [x] `mixins/lib/transform.libsonnet` — disable / severity / runbook 정책 강제
- [x] cert-manager mixin import wrap stub (디폴트 OFF)
- [x] critical 12개 룬북 stub
- [x] [docs/baseline-alerts.md](docs/baseline-alerts.md) 의사결정 노트 + 적용 결과

### 🚧 Alertmanager 라우팅 PR (현재)
- [x] `mixins/local/baseline-mixin/alertmanager.libsonnet` — severity 기반 routing tree + inhibit_rules
- [x] `mixins/lib/alertmanager.libsonnet` — CR ↔ raw 변환 (단일 source-of-truth)
- [x] AlertmanagerConfig CR 렌더링 → `manifests/alertmanager-config/`
- [x] amtool 통합 — `check-config` + `config routes test` 단언 (`tests/alertmanager-routing.sh`)

### 🚧 클러스터 sync PR — 후속
- [ ] `argocd/` Application 매니페스트
- [ ] 테스트 클러스터에서 ConfigMap sidecar 픽업 검증
- [ ] Slack/PagerDuty receiver 연결 (Secret은 SealedSecret/SOPS로 별도 repo)

### 🚧 첫 도메인 mixin PR
- [ ] `mixins/local/rpc-mixin/` — 블록 헤드/peer/sync 알림 + 패널 1세트
- [ ] `docs/runbooks/rpc-*.md` — RPC 룬북 초안

### 🚧 시나리오 e2e PR — 알림 실제 발화 검증
- [ ] `e2e/scripts/scenarios.sh fire-rule-failure` — 잘못된 PrometheusRule 주입 → API에서 firing 단언
- [ ] `e2e/scripts/scenarios.sh fire-oom` — stress-ng로 메모리 압박 → HighOOMKillRate 발화
- [ ] `e2e/scripts/scenarios.sh fire-ingress-down` — ingress controller scale=0 → IngressControllerDown 발화
- [ ] `e2e/scripts/scenarios.sh fire-pv-failed` — bad StorageClass → KubePersistentVolumeErrors 발화

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
