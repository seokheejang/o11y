# Shared helpers for e2e scripts. source 전용 — 직접 실행하지 않는다.
# 사용처: e2e/scripts/cluster.sh

# REPO_ROOT — common.sh 위치(e2e/scripts/) 기준 2단계 위.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E2E_DIR="${REPO_ROOT}/e2e"
E2E_KUBECONFIG="${E2E_DIR}/.kubeconfig"

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[error] required command not found: $1" >&2
        exit 1
    }
}

# 카운터 + 단언 헬퍼 — chain-node-infra/e2e/scripts/cluster.sh 패턴.
PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    if eval "$*" &>/dev/null; then
        echo "  [PASS] ${label}"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] ${label}"
        FAIL=$((FAIL + 1))
    fi
}

# wait_for label timeout cmd...  — cmd가 성공할 때까지 5초 간격으로 폴링.
wait_for() {
    local label="$1"
    local timeout="$2"
    shift 2
    local deadline=$((SECONDS + timeout))
    while [[ $SECONDS -lt $deadline ]]; do
        if eval "$*" &>/dev/null; then
            echo "  [PASS] ${label}"
            PASS=$((PASS + 1))
            return 0
        fi
        sleep 5
    done
    echo "  [FAIL] ${label} (timed out after ${timeout}s)"
    FAIL=$((FAIL + 1))
    return 1
}
