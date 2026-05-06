#!/usr/bin/env bash
# tools/validate.sh — promtool + kubeconform 일괄 실행.
# Usage:
#   tools/validate.sh test    # promtool test rules tests/*.yaml
#   tools/validate.sh lint    # kubeconform on manifests/
#   tools/validate.sh all     # test + lint
#
# 빌드 의존: tools/build.sh가 먼저 manifests/ + out/prometheus-rules-raw/ 생성.

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
        return 0
    fi
    if [[ ! -d out/prometheus-rules-raw ]]; then
        echo "[error] out/prometheus-rules-raw/ missing — run 'make build' first" >&2
        exit 1
    fi
    echo "[test] promtool test rules tests/*.yaml"
    (cd tests && promtool test rules ./*.yaml)
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
