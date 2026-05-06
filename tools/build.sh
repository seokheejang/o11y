#!/usr/bin/env bash
# Compile mixins/main.libsonnet → manifests/{prometheus-rules,grafana-dashboards}/*.yaml
#
# Pattern: kube-prometheus build.sh — jsonnet -m + gojsontoyaml.
# top-level object의 슬래시 키(예: 'prometheus-rules/kubernetes')가 곧 산출 경로.
#
# 부산물:
#   out/prometheus-rules-raw/<name>.yaml — promtool test rules 입력용
#     (PrometheusRule CR의 .spec만 추출 — promtool은 CR 구조를 이해하지 못함)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "[error] $1 missing — see tools/README.md" >&2; exit 1; }
}
require jsonnet
require gojsontoyaml
require jb
require yq

if [[ ! -f vendor/.jb-stamp ]] || [[ jsonnetfile.lock.json -nt vendor/.jb-stamp ]]; then
    echo "[build] jb install"
    jb install
    touch vendor/.jb-stamp
fi

OUT_DIRS=(prometheus-rules grafana-dashboards)

echo "[build] clean manifests/{$(IFS=,; echo "${OUT_DIRS[*]}")}"
for d in "${OUT_DIRS[@]}"; do
    rm -rf "manifests/${d:?}"
    mkdir -p "manifests/${d}"
done
rm -rf out/prometheus-rules-raw
mkdir -p out/prometheus-rules-raw

echo "[build] jsonnet -> JSON"
# -J vendor : 외부 mixin import path
# -J mixins : mixins/lib/, mixins/external/ 단축 import
# -m manifests : top-level 키별 1파일 출력
jsonnet -J vendor -J mixins -m manifests mixins/main.libsonnet \
    | xargs -I{} sh -c 'cat "$1" | gojsontoyaml > "$1.yaml"' -- {}

echo "[build] JSON -> YAML cleanup"
find manifests -type f ! -name '*.yaml' ! -name '.gitkeep' -delete

echo "[build] extract raw rules for promtool"
for cr in manifests/prometheus-rules/*.yaml; do
    [[ -e "$cr" ]] || continue
    name="$(basename "$cr")"
    yq '.spec' "$cr" > "out/prometheus-rules-raw/${name}"
done

echo "[build] generated:"
find manifests -type f -name '*.yaml' | sort | sed 's/^/  /'
echo "[build] raw rules (for promtool):"
find out/prometheus-rules-raw -type f -name '*.yaml' | sort | sed 's/^/  /'
