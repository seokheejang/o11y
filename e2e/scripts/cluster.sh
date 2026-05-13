#!/usr/bin/env bash
# o11y e2e — kind cluster + kube-prometheus-stack lifecycle.
# Kubeconfig는 e2e/.kubeconfig — 절대 ~/.kube/config을 건드리지 않는다.
#
# Usage:
#   e2e/scripts/cluster.sh setup              # kind + kube-prometheus-stack + manifests apply
#   e2e/scripts/cluster.sh verify             # 클러스터 + manifests 상태 검증
#   e2e/scripts/cluster.sh teardown           # kind cluster 삭제
#   e2e/scripts/cluster.sh setup --name foo   # 커스텀 클러스터 이름

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# --- Config ---
CLUSTER_NAME="o11y-e2e"
MONITORING_NAMESPACE="monitoring"
KPS_RELEASE="kps"
KPS_CHART_VERSION="65.5.0"  # kube-prometheus-stack — 2024-11 안정 버전 (Prom 2.55+)
GRAFANA_PASSWORD="admin"

# --- Parse command + flags ---
COMMAND="${1:-}"
shift 2>/dev/null || true

while [[ $# -gt 0 ]]; do
    case $1 in
        --name) CLUSTER_NAME="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

export KUBECONFIG="${E2E_KUBECONFIG}"

# ============================================================
# Commands
# ============================================================

cmd_setup() {
    require_cmd kind
    require_cmd helm
    require_cmd kubectl
    require_cmd make

    echo ""
    echo "=== o11y e2e — Cluster Setup ==="
    echo "  Cluster   : ${CLUSTER_NAME}"
    echo "  Kubeconfig: ${E2E_KUBECONFIG}"
    echo "  Namespace : ${MONITORING_NAMESPACE}"
    echo ""

    # [1/5] Kind cluster — idempotent
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        echo "[1/5] Kind cluster '${CLUSTER_NAME}' already exists. Reusing."
        kind get kubeconfig --name "${CLUSTER_NAME}" > "${E2E_KUBECONFIG}"
    else
        echo "[1/5] Creating Kind cluster '${CLUSTER_NAME}'..."
        kind create cluster \
            --name "${CLUSTER_NAME}" \
            --config "${E2E_DIR}/kind/cluster.yaml" \
            --kubeconfig "${E2E_KUBECONFIG}" \
            --wait 60s
    fi
    echo "[1/5] Done."

    # [2/5] Helm repo
    echo "[2/5] Adding helm repo..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update prometheus-community
    echo "[2/5] Done."

    # [3/5] Install kube-prometheus-stack
    echo "[3/5] Installing kube-prometheus-stack (chart ${KPS_CHART_VERSION})..."
    helm upgrade --install "${KPS_RELEASE}" prometheus-community/kube-prometheus-stack \
        --version "${KPS_CHART_VERSION}" \
        --namespace "${MONITORING_NAMESPACE}" \
        --create-namespace \
        -f "${E2E_DIR}/values/kube-prometheus-stack.yaml" \
        --set "grafana.adminPassword=${GRAFANA_PASSWORD}" \
        --timeout 10m \
        --wait
    echo "[3/5] Done."

    # [4/5] Slack webhook placeholder Secret + o11y manifests
    # AlertmanagerConfig CR의 slackConfigs.apiURL이 참조하는 Secret을 placeholder로 만든다.
    # 없으면 operator reload는 통과해도 alertmanager가 receiver dispatch 시점에 url resolve 실패.
    # 실제 webhook URL은 환경 인프라(prod GitOps/SealedSecret 등)에서 주입 — repo는 placeholder만 보장.
    echo "[4/5] Creating placeholder Slack webhook Secret + applying o11y manifests..."
    kubectl create secret generic alertmanager-slack-webhook \
        -n "${MONITORING_NAMESPACE}" \
        --from-literal=url='https://hooks.slack.com/services/PLACEHOLDER/PLACEHOLDER/PLACEHOLDER' \
        --dry-run=client -o yaml | kubectl apply -f -
    (cd "${REPO_ROOT}" && make build)
    kubectl apply -R -f "${REPO_ROOT}/manifests/" -n "${MONITORING_NAMESPACE}"
    echo "[4/5] Done."

    # [5/5] Wait for pods
    echo "[5/5] Waiting for pods Ready..."
    kubectl wait --for=condition=Ready pods --all \
        -n "${MONITORING_NAMESPACE}" --timeout=300s || true
    echo "[5/5] Done."

    echo ""
    cmd_verify

    cat <<EOF

===========================================
  Cluster ready
===========================================

  Cluster      : kind-${CLUSTER_NAME}
  KUBECONFIG   : ${E2E_KUBECONFIG}
  Namespace    : ${MONITORING_NAMESPACE}

  Web UI (kind extraPortMappings 통해 호스트 직결 — port-forward 불필요):
    Prometheus  : http://localhost:9090
    Grafana     : http://localhost:3000   (admin/${GRAFANA_PASSWORD})

  kubectl/helm 직접:
    export KUBECONFIG=${E2E_KUBECONFIG}

  Teardown     : make e2e-down
===========================================
EOF
}

cmd_verify() {
    PASS=0
    FAIL=0

    echo ""
    echo "=== o11y e2e — Verification ==="
    echo ""

    echo "Cluster:"
    check "Kind cluster exists"        "kind get clusters 2>/dev/null | grep -q '^${CLUSTER_NAME}$'"
    check "Kubeconfig valid"           "kubectl cluster-info"
    check "Nodes Ready"                "kubectl wait --for=condition=Ready nodes --all --timeout=10s"

    echo ""
    echo "kube-prometheus-stack:"
    check "Namespace exists"           "kubectl get namespace ${MONITORING_NAMESPACE}"
    check "Prometheus statefulset"     "kubectl get statefulset -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=prometheus"
    check "Grafana deployment"         "kubectl get deployment -n ${MONITORING_NAMESPACE} -l app.kubernetes.io/name=grafana"
    check "Operator deployment"        "kubectl get deployment -n ${MONITORING_NAMESPACE} -l app=kube-prometheus-stack-operator"

    echo ""
    echo "o11y manifests:"
    check "PrometheusRule (kubernetes) applied" "kubectl get prometheusrule -n ${MONITORING_NAMESPACE} kubernetes"
    check "PrometheusRule (baseline) applied"   "kubectl get prometheusrule -n ${MONITORING_NAMESPACE} baseline"
    # AlertmanagerConfig CR — operator가 watch하여 alertmanager.yml로 컴파일.
    # admit만 확인 (실제 라우팅 작동은 amtool로 빌드 시 검증됨).
    check "AlertmanagerConfig admitted"         "kubectl get alertmanagerconfig -n ${MONITORING_NAMESPACE} baseline"
    # Slack receiver가 참조하는 Secret이 존재해야 operator/Alertmanager가 url을 resolve할 수 있음.
    # 값은 e2e용 placeholder — 실 webhook URL은 환경별 인프라에서 주입.
    check "Slack webhook Secret present"        "kubectl get secret -n ${MONITORING_NAMESPACE} alertmanager-slack-webhook"
    # 대시보드는 자체 mixin(3차 PR rpc-mixin 등)에서만 만든다 — 외부 kubernetes-mixin
    # 대시보드는 kube-prometheus-stack 차트가 디폴트로 동일 출처를 import하므로 중복 회피.

    echo ""
    echo "-------------------------------------------"
    echo "  Result: ${PASS} passed, ${FAIL} failed"
    echo "-------------------------------------------"

    [[ ${FAIL} -gt 0 ]] && return 1
    return 0
}

cmd_teardown() {
    require_cmd kind

    echo ""
    echo "=== o11y e2e — Cluster Teardown ==="
    echo ""

    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        echo "[1/2] Deleting Kind cluster '${CLUSTER_NAME}'..."
        kind delete cluster --name "${CLUSTER_NAME}"
        echo "[1/2] Done."
    else
        echo "[1/2] Cluster '${CLUSTER_NAME}' does not exist. Skipping."
    fi

    if [[ -f "${E2E_KUBECONFIG}" ]]; then
        rm -f "${E2E_KUBECONFIG}"
        echo "[2/2] Removed ${E2E_KUBECONFIG}"
    else
        echo "[2/2] Kubeconfig not found. Skipping."
    fi

    echo ""
    echo "Teardown complete."
}

# ============================================================
# Main
# ============================================================

case "${COMMAND}" in
    setup)    cmd_setup ;;
    verify)   cmd_verify ;;
    teardown) cmd_teardown ;;
    *)
        echo "Usage: $0 {setup|verify|teardown} [--name <cluster-name>]"
        echo ""
        echo "  setup      Create Kind cluster, install kube-prometheus-stack, apply o11y manifests"
        echo "  verify     Check cluster health + manifests applied"
        echo "  teardown   Delete Kind cluster + kubeconfig"
        exit 1
        ;;
esac
