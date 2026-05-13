#!/usr/bin/env bash
# Alertmanager routing 단언 테스트.
#
# amtool config routes test --config.file=<raw> <labelset>
# 의 출력을 expected receiver(쉼표 구분)와 비교한다.
#
# severity-policy.md의 보장:
#   severity=critical → pager + critical-chat (continue=true)
#   severity=warning  → warning-chat
#   severity 누락/기타 → null (drop)
#   inhibit: critical 발화 중일 때 같은 (alertname, cluster, namespace) warning 묵음
#   inhibit: KubeNodeNotReady 발화 중일 때 같은 (cluster, node) warning 묵음
#
# 참고: amtool routes test는 inhibit_rules를 평가하지 않는다 (라우팅만).
#       inhibit는 config check에서 syntax/equal-label 검증만 가능.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${REPO_ROOT}/out/alertmanager-config-raw/baseline.yaml"

if [[ ! -f "${CONFIG}" ]]; then
    echo "[error] ${CONFIG} missing — run 'make build' first" >&2
    exit 1
fi
if ! command -v amtool >/dev/null 2>&1; then
    echo "[error] amtool missing — run 'tools/install.sh'" >&2
    exit 1
fi

PASS=0
FAIL=0
FAILED_CASES=()

# expected: comma-separated receiver names in declaration order. amtool은 라우팅 트리
# 순서대로 receiver를 출력하므로 declaration order와 일치해야 한다.
assert_route() {
    local expected="$1"
    local description="$2"
    shift 2
    local labels=("$@")
    local actual
    actual="$(amtool config routes test --config.file="${CONFIG}" "${labels[@]}" 2>&1 | tr -d '\n')"
    if [[ "${actual}" == "${expected}" ]]; then
        printf "  [ok]   %-60s -> %s\n" "${description}" "${actual}"
        PASS=$((PASS + 1))
    else
        printf "  [FAIL] %-60s expected=%s actual=%s\n" "${description}" "${expected}" "${actual}"
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("${description}")
    fi
}

echo "=== amtool config check ==="
amtool check-config "${CONFIG}"

echo ""
echo "=== routing assertions ==="

# critical → pager + critical-chat (continue=true 둘 다)
assert_route "pager,critical-chat" \
    "severity=critical → pager + critical-chat" \
    severity=critical alertname=KubeNodeNotReady cluster=test namespace=kube-system

assert_route "pager,critical-chat" \
    "severity=critical (다른 alertname) → pager + critical-chat" \
    severity=critical alertname=PrometheusRuleFailures cluster=test namespace=monitoring

# warning → warning-chat
assert_route "warning-chat" \
    "severity=warning → warning-chat only" \
    severity=warning alertname=HighIngress5xxRate cluster=test namespace=ingress-nginx

# severity 누락 → null receiver (drop)
assert_route "null" \
    "severity 누락 → null (drop)" \
    alertname=Unknown cluster=test

# severity가 정책 외 값 → null
assert_route "null" \
    "severity=info → null (drop, 정책 외)" \
    severity=info alertname=Foo

echo ""
if [[ ${FAIL} -gt 0 ]]; then
    echo "[result] ${PASS} pass, ${FAIL} FAIL"
    for c in "${FAILED_CASES[@]}"; do
        echo "  - ${c}"
    done
    exit 1
else
    echo "[result] ${PASS} pass"
fi
