# Build pipeline & kind e2e — research notes

**Date:** 2026-05-06
**Context:** o11y repo 2차 PR 준비 — jsonnet mixin → CR 변환 도구체인 선택, kind 기반 시나리오 테스트 패턴

## Q1. jsonnet mixin → CR 변환: 표준 도구체인

### 결론

`jsonnet -m` (multi-output) + `gojsontoyaml` + 외부 셸 스크립트로 split — **kube-prometheus의 build.sh가 사실상의 표준**. mixtool은 alpha이고 더 이상 권장 위치 아님.

### 4가지 결정 사항

| 결정 | 표준 | 비고 |
|------|------|------|
| jsonnet 컴파일러 | **go-jsonnet** (`google/go-jsonnet`) | go 단일 바이너리, kube-prometheus 공식. C++ `google/jsonnet`은 호환되지만 배포가 무거움 |
| JSON→YAML 변환 | **gojsontoyaml** (`brancz/gojsontoyaml`) | kube-prometheus 공식. yq도 가능하지만 멀티문서 처리/순서가 미묘함 |
| 출력 모드 | **`jsonnet -m`** 멀티파일 | 단일 출력 후 split보다 단순. 각 manifest가 별도 파일이라 GitOps diff가 깔끔 |
| CR wrapping | **jsonnet 안에서** | `apiVersion: monitoring.coreos.com/v1`, `kind: PrometheusRule` 등은 jsonnet 라이브러리(kube-prometheus의 `prometheus.libsonnet`)가 만들어줌 — 셸이 wrap하지 않음 |

### kube-prometheus build.sh 핵심 로직 (재구성)

```bash
# 1. clean
rm -rf manifests
mkdir -p manifests/setup

# 2. compile to JSON, multi-file output
jsonnet -J vendor -m manifests example.jsonnet \
  | xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml' -- {}

# 3. drop intermediate JSON files
find manifests -type f ! -name '*.yaml' -delete
```

핵심 포인트:
- `-J vendor` — `vendor/`(jb install 결과) 안의 mixin import 가능
- `-m <dir>` — top-level object의 각 key가 별도 파일이 됨 (`{ 'foo-rules': {...}, 'bar-config': {...} }` → `foo-rules`, `bar-config`)
- `gojsontoyaml`은 stdin/stdout 단순 변환기. xargs로 파일 단위 처리

### Grafana 대시보드 → ConfigMap

jsonnet에서 다음과 같이 wrap (kube-prometheus 패턴):

```jsonnet
{
  ['grafana-dashboard-' + name]: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: 'grafana-dashboard-' + name,
      namespace: 'monitoring',
      labels: { grafana_dashboard: '1' },
    },
    data: { [name + '.json']: std.manifestJsonEx(dashboards[name], '    ') },
  }
  for name in std.objectFields(dashboards)
}
```

→ `kube-prometheus-stack`의 Grafana sidecar가 `grafana_dashboard: "1"` 라벨 ConfigMap을 watch해서 자동 import. 별도 API 호출 불필요.

### 대안 — 왜 mixtool이 아닌가

- **상태**: 공식 README가 _alpha_ 명시. 활동이 미미함.
- **기능**: `mixtool generate`가 alerts/rules/dashboards를 산출은 함. 하지만 wrapping(CR/ConfigMap)은 자체적으로 해주지 않아 어차피 래핑은 직접 해야 함.
- **현장**: kube-prometheus, kubernetes-mixin, loki-mixin 등 메인스트림 mixin들이 모두 자체 Makefile + build.sh로 처리. mixtool 의존 사례가 거의 없음.
- **결론**: 채택하지 않음.

### 권장 도구셋 (2026 시점)

| 도구 | 출처 | 용도 |
|------|------|------|
| `jsonnet` (go-jsonnet) | github.com/google/go-jsonnet | 컴파일러 |
| `jb` (jsonnet-bundler) | github.com/jsonnet-bundler/jsonnet-bundler | 의존성 관리 |
| `gojsontoyaml` | github.com/brancz/gojsontoyaml | JSON→YAML |
| `promtool` | prometheus 릴리스 번들 | 룰 검증/단위 테스트 |
| `kubeconform` | github.com/yannh/kubeconform | K8s 매니페스트 스키마 검증 |
| `amtool` | alertmanager 릴리스 번들 | AlertmanagerConfig 검증 + 라우팅 테스트 |

---

## Q2. 알림 룰 시나리오 테스트 — 계층 전략

### 결론

**3단계 피라미드**로 가는 것이 표준. 각각 비용·신뢰도·실행 시간이 다름.

```
       ┌─────────────────────────┐
       │  (3) kind 시나리오 e2e   │  무겁다, 느리다, 진실하다
       │   합성 메트릭 주입       │
       ├─────────────────────────┤
       │  (2) amtool routing     │  중간
       │   AlertmanagerConfig 검증│
       ├─────────────────────────┤
       │  (1) promtool test      │  싸고 빠르다, 모든 룰에 적용
       │   alerting_rules 단위   │
       └─────────────────────────┘
```

### (1) promtool test rules — 모든 PR에서 필수

공식 문서(`docs/configuration/unit_testing_rules`)에 정식 지원되는 PromQL 단위 테스트.

```yaml
# tests/rpc-stale-head.yaml
rule_files:
  - ../manifests/prometheus-rules/rpc-mixin-rules.yaml

evaluation_interval: 1m

tests:
  - interval: 1m
    input_series:
      - series: 'eth_block_height{instance="node1"}'
        values: '100 100 100 100 100'   # 4분 동안 헤드 정지
    alert_rule_test:
      - eval_time: 5m
        alertname: RpcStaleBlockHead
        exp_alerts:
          - exp_labels:
              severity: critical
              instance: node1
            exp_annotations:
              summary: "RPC head stalled"
```

**이게 핵심.** PromQL 표현식이 **언제** 발화하는지를 결정론적으로 검증. CI에서 매 PR 실행. **3차 PR에서 rpc-mixin과 함께 테스트도 같이 들어감**.

### (2) amtool — Alertmanager 라우팅 정적 검증

```bash
# 설정 자체의 문법/스키마 검증
amtool check-config alertmanager.yaml

# 특정 라벨이 실제로 어느 receiver로 가는지
amtool config routes test \
  --config.file=alertmanager.yaml \
  --tree \
  --verify.receivers=oncall-pagerduty \
  severity=critical alertname=RpcStaleBlockHead
```

`--verify.receivers`로 "이 라벨셋이 PagerDuty로 가야 한다"를 단언. **4차 PR(라우팅 도입)에서 CI에 추가.**

### (3) kind 기반 시나리오 e2e — 선택적, 최종 검증

목적: PromQL 작성 실수, scrape 라벨 mismatch, ServiceMonitor selector 오타, sidecar import 실패 같은 "런타임에서만 드러나는 결함" 잡기. **2차 PR에서는 빈 빌드만, 3차 PR에서 실제 알림 확인 추가.**

#### 합성 메트릭 주입 — 어떻게?

3가지 패턴 (난이도 ↑):

**A. 더미 exporter Pod (가장 단순)** ← 추천

```yaml
# Python/Go 한 줄짜리 HTTP 서버가 /metrics에 고정 텍스트 응답
# ServiceMonitor가 이걸 scrape → Prometheus에 메트릭 주입됨
apiVersion: v1
kind: ConfigMap
metadata: { name: fake-metrics }
data:
  metrics.txt: |
    eth_block_height{instance="fake-rpc"} 100
---
# nginx로 ConfigMap 서빙 + ServiceMonitor 등록
# 그 후 시간을 두고 같은 값 유지 → StaleHead 알림 발화 확인
```

장점: 인프라 가볍고, 메트릭 시나리오를 ConfigMap 한 줄로 변경.

**B. Pushgateway**

`prom/pushgateway` 1개 띄우고 `curl --data-binary` 로 푸시. 알림 시나리오를 셸 스크립트로 짜기 좋음.

**C. node_exporter textfile collector**

`textfile` 디렉토리에 `.prom` 파일 떨어뜨림 → node_exporter가 알림 메트릭 흡수. node 단위 알림 테스트할 때만 의미 있음.

#### kind에서 kube-prometheus-stack 띄울 때 주의점

GitHub issues에서 반복적으로 나오는 함정들:

1. **메모리** — Prometheus 기본 limit 2Gi 너무 큼. kind에서는:
   ```yaml
   prometheus:
     prometheusSpec:
       resources:
         requests: { cpu: 50m, memory: 200Mi }
         limits:   { memory: 500Mi }
       retention: 1h    # 디스크 절약
       walCompression: true
   ```
2. **AlertManager 미설치 이슈** — `alertmanager.enabled: true`만 켜고 `alertmanager.alertmanagerSpec.replicas: 1` 명시.
3. **CRD 크기** — `kubectl apply`가 too-large로 거부될 수 있음 → `helm upgrade --install` 권장 (Helm은 server-side apply 지원).
4. **kube-state-metrics, node-exporter, grafana 끄기** — 알림 룰 검증만 할 거면 모두 disable. 클러스터 1개당 메모리 절반 절약.
5. **타이밍** — `--wait` 옵션 + 명시적 `kubectl wait --for=condition=Ready` 단계.

#### 평가 — 어떤 e2e 프레임워크?

| 도구 | 적합성 | 비고 |
|------|--------|------|
| **bash 스크립트 + `kubectl wait`/`curl`** | ✅ 추천 | chain-node-infra/e2e 패턴이 이미 잘 정착. 알림 검증은 단계가 적어 프레임워크 오버킬. |
| **kuttl** | △ | 선언적이지만 KUDO 종속. 최근 활동성 낮음. |
| **chainsaw** (kyverno) | ◎ | 더 활발. 복잡한 시나리오/병렬 테스트 늘어나면 도입 고려. **지금은 X.** |
| **e2e-framework** (k8s-sigs) | ✗ | go 코드 작성 필요. ROI 낮음. |

**결론: bash + 단계별 verify 함수**(`chain-node-infra/e2e`의 `cluster.sh` 패턴 그대로 차용).

### 권장 도구셋 (2026 시점)

| 도구 | 용도 |
|------|------|
| `promtool test rules` | 단위 테스트 — **모든 PR** |
| `amtool check-config` / `amtool config routes test` | Alertmanager 검증 — **4차 PR부터** |
| `kind` + `kube-prometheus-stack` (helm) + 더미 exporter | 시나리오 e2e — **3차 PR 이후 선택적** |
| 격리된 `KUBECONFIG` (e2e/.kubeconfig) | `~/.kube/config` 오염 방지 |

---

## o11y repo에 적용할 결정

### 2차 PR (지금)
1. `tools/build.sh` — kube-prometheus 스타일 (`jsonnet -m | gojsontoyaml`)
2. `mixins/external/kubernetes.libsonnet` — 외부 mixin wrap (build 동작 증명용)
3. `Makefile` 실구현 — vendor/build/test/lint
4. `tests/` — promtool 테스트 1개 (kubernetes-mixin의 룰 하나에 대해)
5. `.github/workflows/ci.yml` — `jb install` 캐싱 + build/test/lint
6. `e2e/` 디렉토리 도입 — `chain-node-infra/e2e/` 구조 차용
   - `e2e/kind/cluster.yaml` — 1 control-plane + 1 worker
   - `e2e/scripts/cluster.sh` — kind + kube-prometheus-stack 설치/검증/삭제
   - `e2e/values/kube-prometheus-stack.yaml` — kind에 맞는 경량 설정
   - 알림 시나리오 검증은 3차 PR로 미룸 (지금은 cluster up & manifests apply까지만)

### 3차 PR
- `mixins/local/rpc-mixin/` 작성
- `tests/rpc-*.yaml` — promtool 단위 테스트
- `e2e/scripts/rpc-mixin.sh` — 더미 exporter 주입 → 알림 발화 확인

### 4차 PR
- AlertmanagerConfig
- `amtool config routes test` 를 CI에 추가

---

## 출처

### 공식 문서 / 프로젝트
1. [kube-prometheus — build.sh (main)](https://github.com/prometheus-operator/kube-prometheus/blob/main/build.sh) — 표준 빌드 스크립트
2. [kube-prometheus — example.jsonnet](https://github.com/prometheus-operator/kube-prometheus/blob/main/example.jsonnet) — multi-output naming convention
3. [Prometheus — Unit testing for rules](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/) — promtool test rules 공식
4. [Alertmanager — amtool 매뉴얼](https://github.com/prometheus/alertmanager) — `config routes test`
5. [monitoring.mixins.dev](https://monitoring.mixins.dev/) — mixin 허브
6. [prometheus-operator.dev — Developing rules and dashboards](https://prometheus-operator.dev/kube-prometheus/kube/developing-prometheus-rules-and-grafana-dashboards/)
7. [gojsontoyaml](https://github.com/brancz/gojsontoyaml)
8. [jsonnet-bundler](https://github.com/jsonnet-bundler/jsonnet-bundler)

### 평가 / 비교 / 사례
9. [mixtool — README (alpha 명시)](https://github.com/monitoring-mixins/mixtool) — 채택 안 함 근거
10. [Grafana Labs — Everything You Need to Know About Monitoring Mixins](https://grafana.com/blog/everything-you-need-to-know-about-monitoring-mixins/)
11. [kubernetes-monitoring/kubernetes-mixin](https://github.com/kubernetes-monitoring/kubernetes-mixin) — 표준 mixin Makefile 패턴 모델
12. [Aviator — Unit Testing Prometheus Alerts](https://www.aviator.co/blog/a-guide-to-unit-testing-prometheus-alerts/)
13. [chainsaw](https://github.com/kyverno/chainsaw) — 미래 e2e 프레임워크 후보
14. [helm-charts — issue #4068 AlertManager custom config](https://github.com/prometheus-community/helm-charts/issues/4068) — kind 운영 함정
15. [helm-charts — issue #3401 prometheus resource limits](https://github.com/prometheus-community/helm-charts/issues/3401)

### 내부 참고
16. `~/dev/seokheejang/chain-node-infra/e2e/` — bash + verify 패턴 모델
