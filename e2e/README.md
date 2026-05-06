# e2e/ — Local kind testing

`kind` 위에 `kube-prometheus-stack`을 올리고 본 repo의 `manifests/`를 apply 해서 빌드 산출물이 실제 클러스터에서 admit + reload 되는지 확인하는 골격.

> **2차 PR 시점 범위**: cluster up + manifests apply + Pod Ready까지.
> 알림 발화 시나리오 검증(더미 exporter 주입 → Prometheus `/api/v1/alerts` 단언)은 **3차 PR**에서 추가한다.

## Prerequisites

- Docker (실행 중)
- [kind](https://kind.sigs.k8s.io/) ≥ 0.20
- [helm](https://helm.sh/) v3.x
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- 호스트 권장: 4 CPU / 6 GB+ Docker desktop 할당

## Quick start

```bash
# 1) 클러스터 + kube-prometheus-stack 설치 + manifests apply
make e2e-up

# 2) (선택) 검증 단독 재실행
make e2e-verify

# 3) 정리
make e2e-down
```

`KUBECONFIG`는 항상 `e2e/.kubeconfig` (gitignored). `~/.kube/config`은 절대 건드리지 않는다.

## Layout

```
e2e/
├── README.md
├── kind/
│   └── cluster.yaml                 # 1 control-plane + 1 worker
├── values/
│   └── kube-prometheus-stack.yaml   # kind용 경량 values (메모리 제한, AM/nodeExporter disable)
└── scripts/
    ├── common.sh                    # require_cmd, check, wait_for + REPO_ROOT
    └── cluster.sh                   # setup / verify / teardown
```

## Verify가 단언하는 것

- Kind 클러스터 + 노드 Ready
- kube-prometheus-stack 컴포넌트 (Prometheus, Grafana, operator) 배포
- `manifests/prometheus-rules/kubernetes.yaml`이 `PrometheusRule`로 admit

> **대시보드 분담 정책**: 외부 mixin(`kubernetes-mixin`)의 대시보드는 `kube-prometheus-stack` 차트가 동일 출처에서 생성한다(중복 방지). 우리 `manifests/grafana-dashboards/`는 **자체 mixin**(3차 PR `rpc-mixin` 등)의 도메인 대시보드만 담는다.

## UI 접근

`make e2e-up` 후 브라우저에서 바로 열린다 — `kubectl port-forward` 불필요.

| UI | URL | 비고 |
|---|---|---|
| Prometheus | http://localhost:9090 | rule 평가, target 상태, alert 시뮬레이션 |
| Grafana | http://localhost:3000 | admin / admin |

원리: `e2e/kind/cluster.yaml`의 `extraPortMappings`가 컨테이너 NodePort 30090/30030을 호스트 9090/3000으로 직접 매핑. `e2e/values/kube-prometheus-stack.yaml`이 prometheus/grafana service를 `NodePort: 30090/30030`으로 핀.

`kubectl`/`helm`을 직접 쓰려면:
```bash
export KUBECONFIG=$PWD/e2e/.kubeconfig
```

## 다음 단계 (참고)

- 3차 PR — `e2e/scripts/rpc-mixin.sh deploy/verify`로 더미 exporter 주입 → 알림 발화 단언
- 4차 PR — `amtool config routes test`로 Alertmanager 라우팅 정합 검증
