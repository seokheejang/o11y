#!/usr/bin/env bash
# tools/install.sh — o11y 빌드/검증/e2e 도구 한 방 설치.
#
# 지원 OS  : macOS (darwin/arm64, darwin/amd64), Linux (linux/amd64, linux/arm64)
# 멱등성   : 이미 깔린 도구는 skip.
# 권한     : sudo가 필요한 단계는 명시. 그 외는 사용자 영역(~/go, brew prefix).
#
# Usage:
#   tools/install.sh           # 전체 설치
#   tools/install.sh --check   # 설치 상태만 점검 (변경 없음)
#
# 도구별 설치 경로:
#   Go 토큰      : go install (jsonnet, jb, gojsontoyaml) → $GOPATH/bin
#   tarball     : promtool (Prometheus 릴리스에서 추출) → /usr/local/bin (sudo)
#   brew/native : kubeconform, yq, kind, helm, kubectl

set -euo pipefail

# === 핀 버전 ===
JSONNET_VERSION="v0.20.0"
JB_VERSION="v0.6.0"
GOJSONTOYAML_VERSION="latest"
PROMTOOL_VERSION="2.55.1"
KUBECONFORM_VERSION="0.6.7"
YQ_VERSION="4.45.1"  # mikefarah yq v4 — Linux fallback에서 핀해서 공급망 공격 면적 축소

CHECK_ONLY=0
BUILD_ONLY=0
for arg in "$@"; do
    case "${arg}" in
        --check)      CHECK_ONLY=1 ;;
        --build-only) BUILD_ONLY=1 ;;
        -h|--help)
            cat <<EOF
Usage: $0 [--check] [--build-only]

  --check       Only report missing tools, do not install.
  --build-only  Skip e2e-only tools (kind, helm, kubectl) — useful in CI.
EOF
            exit 0
            ;;
        *) echo "unknown option: ${arg}"; exit 1 ;;
    esac
done

# === OS / arch 감지 ===
case "$(uname -s)" in
    Darwin) OS=darwin ;;
    Linux)  OS=linux ;;
    *) echo "[error] unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
    x86_64|amd64) ARCH=amd64 ;;
    arm64|aarch64) ARCH=arm64 ;;
    *) echo "[error] unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

# === 색상/로깅 ===
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; BLUE=''; NC=''
fi
ok()    { printf "${GREEN}[ok]${NC} %s\n" "$*"; }
info()  { printf "${BLUE}[..]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!!]${NC} %s\n" "$*"; }
fail()  { printf "${RED}[xx]${NC} %s\n" "$*"; }

# === 헬퍼 ===
have() { command -v "$1" >/dev/null 2>&1; }

go_bin() {
    if have go; then
        echo "$(go env GOPATH)/bin"
    else
        echo ""
    fi
}

ensure_path_hint() {
    local gobin
    gobin=$(go_bin)
    if [[ -n "${gobin}" ]] && ! echo ":${PATH}:" | grep -q ":${gobin}:"; then
        warn "GOPATH/bin이 PATH에 없음 — 다음 줄을 ~/.zshrc 또는 ~/.bashrc에 추가:"
        printf "       %s\n" "export PATH=\"\$(go env GOPATH)/bin:\$PATH\""
    fi
}

# === 0. Go 부트스트랩 ===
ensure_go() {
    if have go; then
        local v
        v=$(go env GOVERSION 2>/dev/null | sed 's/go//')
        ok "go ${v} (already installed)"
        return 0
    fi
    if [[ ${CHECK_ONLY} -eq 1 ]]; then
        fail "go missing — install via:"
        printf "       macOS:  brew install go\n"
        printf "       Linux:  https://go.dev/dl/  (or your distro package)\n"
        return 1
    fi
    if [[ "${OS}" == "darwin" ]] && have brew; then
        info "brew install go"
        brew install go
    else
        fail "manual install required: https://go.dev/dl/"
        return 1
    fi
}

# === 1. Go 도구들 (jsonnet, jb, gojsontoyaml) ===
ensure_go_tools() {
    local pkgs=(
        "github.com/google/go-jsonnet/cmd/jsonnet@${JSONNET_VERSION}|jsonnet"
        "github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@${JB_VERSION}|jb"
        "github.com/brancz/gojsontoyaml@${GOJSONTOYAML_VERSION}|gojsontoyaml"
    )
    local rc=0
    for pair in "${pkgs[@]}"; do
        local pkg="${pair%|*}" bin="${pair#*|}"
        if have "${bin}"; then
            ok "${bin} (already installed)"
            continue
        fi
        if [[ ${CHECK_ONLY} -eq 1 ]]; then
            fail "${bin} missing — go install ${pkg}"
            rc=1
            continue
        fi
        info "go install ${pkg}"
        go install "${pkg}"
    done
    return ${rc}
}

# === 2. promtool (Prometheus tarball) ===
ensure_promtool() {
    if have promtool; then
        ok "promtool $(promtool --version 2>&1 | head -1 | awk '{print $3}') (already installed)"
        return 0
    fi
    if [[ ${CHECK_ONLY} -eq 1 ]]; then
        fail "promtool missing — version pin: v${PROMTOOL_VERSION}"
        return 1
    fi
    local url tmpdir
    url="https://github.com/prometheus/prometheus/releases/download/v${PROMTOOL_VERSION}/prometheus-${PROMTOOL_VERSION}.${OS}-${ARCH}.tar.gz"
    tmpdir="$(mktemp -d)"
    info "downloading promtool v${PROMTOOL_VERSION} (${OS}/${ARCH})"
    curl -fsSL "${url}" | tar xz -C "${tmpdir}"

    local gobin dest
    gobin=$(go_bin)
    if [[ -n "${gobin}" && -d "${gobin}" && -w "${gobin}" ]]; then
        dest="${gobin}/promtool"
        mv "${tmpdir}/prometheus-${PROMTOOL_VERSION}.${OS}-${ARCH}/promtool" "${dest}"
        ok "promtool installed → ${dest}"
        if ! echo ":${PATH}:" | grep -q ":${gobin}:"; then
            warn "  ⚠ ${gobin}이 PATH에 없음 — 새 셸을 열거나 export 필요"
        fi
    else
        dest="/usr/local/bin/promtool"
        sudo mv "${tmpdir}/prometheus-${PROMTOOL_VERSION}.${OS}-${ARCH}/promtool" "${dest}"
        sudo chmod +x "${dest}"
        ok "promtool installed → ${dest} (via sudo)"
    fi
    rm -rf "${tmpdir}"
}

# === 3. native 도구들 ===
# 빌드 필수 : kubeconform, yq
# e2e 전용  : kind, helm, kubectl  (--build-only 시 skip)
ensure_native() {
    local pkgs=(kubeconform yq)
    if [[ ${BUILD_ONLY} -eq 0 ]]; then
        pkgs+=(kind helm kubectl)
    fi
    local rc=0
    for bin in "${pkgs[@]}"; do
        if have "${bin}"; then
            ok "${bin} (already installed)"
            continue
        fi
        if [[ ${CHECK_ONLY} -eq 1 ]]; then
            fail "${bin} missing"
            rc=1
            continue
        fi
        if [[ "${OS}" == "darwin" ]]; then
            if ! have brew; then
                fail "Homebrew not found — install from https://brew.sh"
                rc=1; continue
            fi
            info "brew install ${bin}"
            brew install "${bin}"
        else
            case "${bin}" in
                kubeconform)
                    info "downloading kubeconform v${KUBECONFORM_VERSION}"
                    curl -fsSL "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-${ARCH}.tar.gz" \
                        | sudo tar xz -C /usr/local/bin kubeconform
                    sudo chmod +x /usr/local/bin/kubeconform
                    ok "kubeconform installed"
                    ;;
                yq)
                    info "downloading yq v${YQ_VERSION} (mikefarah)"
                    sudo curl -fsSL -o /usr/local/bin/yq \
                        "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}"
                    sudo chmod +x /usr/local/bin/yq
                    ok "yq installed"
                    ;;
                kind|helm|kubectl)
                    fail "${bin}: distro-specific install — see https://kind.sigs.k8s.io / https://helm.sh / https://kubernetes.io/docs/tasks/tools/"
                    rc=1
                    ;;
            esac
        fi
    done
    return ${rc}
}

# ============================================================
# Main
# ============================================================

echo "=== o11y tooling installer (${OS}/${ARCH}) ==="
echo ""

rc=0
ensure_go        || rc=1
ensure_go_tools  || rc=1
ensure_promtool  || rc=1
ensure_native    || rc=1

echo ""
ensure_path_hint
echo ""

if [[ ${rc} -eq 0 ]]; then
    ok "all tools ready"
    [[ ${CHECK_ONLY} -eq 1 ]] || echo "    next: make all"
else
    fail "some tools missing — see messages above"
    exit 1
fi
