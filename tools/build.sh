#!/usr/bin/env bash
# Compile main.libsonnet → manifests/{prometheus-rules,grafana-dashboards,alertmanager-config}/*.yaml
#
# Pattern: kube-prometheus build.sh — jsonnet -m + gojsontoyaml.
# top-level object의 슬래시 키(예: 'prometheus-rules/kubernetes')가 곧 산출 경로.
# jsonnet 검색 경로: `-J vendor -J components` — 후자는 _lib/, _external/, <component>/ 단축 import.
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

OUT_DIRS=(prometheus-rules prometheus-rules-meta grafana-dashboards alertmanager-config)
# alertmanager-config-raw는 amtool 입력용 raw 산출물 — manifests/에 잠깐 떨어졌다가
# out/alertmanager-config-raw/로 이동된다 (kubeconform이 raw config를 K8s 리소스로 오인 방지).
JSONNET_TMP_DIRS=(alertmanager-config-raw)

echo "[build] clean manifests/{$(IFS=,; echo "${OUT_DIRS[*]}")}"
for d in "${OUT_DIRS[@]}"; do
    rm -rf "manifests/${d:?}"
    mkdir -p "manifests/${d}"
done
for d in "${JSONNET_TMP_DIRS[@]}"; do
    rm -rf "manifests/${d:?}"
    mkdir -p "manifests/${d}"
done
rm -rf out/prometheus-rules-raw out/alertmanager-config-raw
mkdir -p out/prometheus-rules-raw out/alertmanager-config-raw

echo "[build] jsonnet -> JSON"
# -J vendor     : 외부 mixin import path
# -J components : components/_lib, components/_external, components/<comp>/ 단축 import
# -m manifests  : top-level 키별 1파일 출력
jsonnet -J vendor -J components -m manifests main.libsonnet \
    | xargs -I{} sh -c 'cat "$1" | gojsontoyaml > "$1.yaml"' -- {}

echo "[build] JSON -> YAML cleanup"
find manifests -type f ! -name '*.yaml' ! -name '.gitkeep' -delete

echo "[build] move alertmanager-config-raw → out/ (amtool 입력, 클러스터에 sync되지 않음)"
# main.libsonnet이 'alertmanager-config-raw/<name>' 키로 떨어뜨린 raw alertmanager.yml을
# out/으로 이동. manifests/에 두면 kubeconform이 raw config를 K8s 리소스로 오인한다.
if [[ -d manifests/alertmanager-config-raw ]]; then
    mv manifests/alertmanager-config-raw/*.yaml out/alertmanager-config-raw/ 2>/dev/null || true
    rmdir manifests/alertmanager-config-raw 2>/dev/null || true
fi

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
echo "[build] raw alertmanager configs (for amtool):"
find out/alertmanager-config-raw -type f -name '*.yaml' | sort | sed 's/^/  /'
