#!/usr/bin/env bash
# tools/validate.sh — promtool + kubeconform + amtool 일괄 실행.
# Usage:
#   tools/validate.sh test    # promtool test rules + amtool routing test
#   tools/validate.sh lint    # kubeconform on manifests/
#   tools/validate.sh all     # test + lint
#
# 빌드 의존: tools/build.sh가 먼저 manifests/ + out/prometheus-rules-raw/
#            + out/alertmanager-config-raw/ 생성.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "[error] $1 missing — see tools/README.md" >&2; exit 1; }
}

run_test() {
    require promtool
    if ! ls tests/*.yaml >/dev/null 2>&1; then
        echo "[test] no tests/*.yaml — skipping"
    else
        if [[ ! -d out/prometheus-rules-raw ]]; then
            echo "[error] out/prometheus-rules-raw/ missing — run 'make build' first" >&2
            exit 1
        fi
        echo "[test] promtool test rules tests/*.yaml"
        (cd tests && promtool test rules ./*.yaml)
    fi
    run_amtool
}

run_amtool() {
    # amtool: alertmanager config 문법 검증 + 라우팅 단언.
    if ! ls out/alertmanager-config-raw/*.yaml >/dev/null 2>&1; then
        echo "[test] no out/alertmanager-config-raw/*.yaml — skipping amtool"
        return 0
    fi
    require amtool
    echo "[test] amtool routing assertions (tests/alertmanager-routing.sh)"
    bash tests/alertmanager-routing.sh
}

run_lint() {
    require kubeconform
    if ! ls manifests/prometheus-rules/*.yaml >/dev/null 2>&1 \
       && ! ls manifests/grafana-dashboards/*.yaml >/dev/null 2>&1; then
        echo "[lint] no manifests/ output — run 'make build' first" >&2
        exit 1
    fi
    echo "[lint] kubeconform on manifests/"
    # CRD(PrometheusRule, AlertmanagerConfig)는 datreeio CRDs-catalog 스키마 사용.
    kubeconform \
        -summary \
        -strict \
        -ignore-missing-schemas \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        manifests/
}

case "${1:-all}" in
    test) run_test ;;
    lint) run_lint ;;
    all)  run_test; run_lint ;;
    *)
        echo "Usage: $0 {test|lint|all}"
        exit 1
        ;;
esac
