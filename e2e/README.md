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
- `manifests/grafana-dashboards/`의 ConfigMap이 `grafana_dashboard=1` 라벨로 적용 → Grafana sidecar가 픽업

## UI 접근

```bash
export KUBECONFIG=$PWD/e2e/.kubeconfig

# Prometheus
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090

# Grafana (admin/admin)
kubectl port-forward -n monitoring svc/kps-grafana 3000:80
```

## 다음 단계 (참고)

- 3차 PR — `e2e/scripts/rpc-mixin.sh deploy/verify`로 더미 exporter 주입 → 알림 발화 단언
- 4차 PR — `amtool config routes test`로 Alertmanager 라우팅 정합 검증
