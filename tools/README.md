# tools/

빌드·검증·설치 헬퍼 스크립트.

## 한 줄 요약

```bash
tools/install.sh           # 모든 도구 자동 설치 (멱등)
tools/install.sh --check   # 설치 상태만 점검
make all                   # vendor → build → test → lint
```

## 스크립트

| 스크립트 | 역할 |
|---|---|
| `install.sh` | 빌드/검증/e2e 도구 일괄 설치. macOS/Linux 모두 지원 |
| `build.sh` | `mixins/main.libsonnet` → `manifests/{prometheus-rules,grafana-dashboards}/*.yaml`. [kube-prometheus build.sh](https://github.com/prometheus-operator/kube-prometheus/blob/main/build.sh) 패턴 (`jsonnet -m` + `gojsontoyaml`). `out/prometheus-rules-raw/`도 생성 — promtool은 PrometheusRule CR을 못 읽으므로 `.spec`만 추출 |
| `validate.sh` | `validate.sh test`(promtool) / `validate.sh lint`(kubeconform) / `validate.sh all` |

Makefile에서 모두 wrapping 됨 (`make build` / `make test` / `make lint`).

## 필요한 도구

`tools/install.sh`이 자동으로 처리하지만, 어떤 도구가 어디서 어떻게 들어오는지 정리:

### Go 토큰 — `go install`

| 도구 | 출처 | 핀 |
|---|---|---|
| `jsonnet` (go-jsonnet) | `github.com/google/go-jsonnet/cmd/jsonnet` | `v0.20.0` |
| `jb` (jsonnet-bundler) | `github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb` | `v0.6.0` |
| `gojsontoyaml` | `github.com/brancz/gojsontoyaml` | latest (릴리스 태그 미운영) |

**전제: Go ≥ 1.22.** Go가 없으면 install.sh가 macOS는 `brew install go`로 부트스트랩. Linux는 [go.dev/dl](https://go.dev/dl/) 또는 distro 패키지 매니저로 직접 설치(install.sh가 가이드 출력).

설치 후 `$(go env GOPATH)/bin`이 PATH에 있어야 함 — 없으면 install.sh가 경고하면서 추가할 줄을 알려줌:
```bash
export PATH="$(go env GOPATH)/bin:$PATH"
```

### Prometheus 도구 — release tarball

| 도구 | 출처 | 핀 |
|---|---|---|
| `promtool` | [Prometheus releases](https://github.com/prometheus/prometheus/releases) | `v2.55.1` |

`brew install prometheus`는 데몬까지 끌려와 무거우므로 **tarball에서 `promtool` 바이너리만 빼서** 설치한다. install.sh가 OS/arch 자동 감지(`darwin/arm64`, `darwin/amd64`, `linux/amd64`, `linux/arm64`).

### Native 도구 — brew (macOS) / 직접 다운로드 (Linux)

| 도구 | macOS | Linux |
|---|---|---|
| `kubeconform` | `brew install kubeconform` | release tarball (auto, v0.6.7) |
| `yq` (mikefarah v4) | `brew install yq` | release binary (auto, latest) |
| `kind` | `brew install kind` | [kind 공식 가이드](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) (수동) |
| `helm` | `brew install helm` | [helm 공식 가이드](https://helm.sh/docs/intro/install/) (수동) |
| `kubectl` | `brew install kubectl` | [kubectl 공식 가이드](https://kubernetes.io/docs/tasks/tools/) (수동) |

> Linux의 `kind`/`helm`/`kubectl`은 distro별 차이가 커서 install.sh에서 자동화하지 않는다 — 위 공식 가이드 따라 설치.

## 왜 brew/go install/tarball을 섞나

- **`jb`, `gojsontoyaml`** — brew formula 없음 → `go install` 외 선택지 없음
- **`jsonnet`** — brew는 C++ 구현(`google/jsonnet`). 우린 Go 구현(`google/go-jsonnet` v0.20). monitoring-mixins 생태계가 go-jsonnet 표준 — `go install`이 정합
- **`promtool`** — brew formula `prometheus`는 서버 데몬까지 — 무거움. tarball이 깔끔
- **`kubeconform`/`yq`/`kind`/`helm`/`kubectl`** — brew/공식 패키지가 가장 잘 관리됨

## CI 환경

`.github/workflows/ci.yml`이 동일 도구·동일 버전을 GitHub Actions ubuntu runner에 설치한다. `setup-go@v5`가 Go 모듈 캐시를 자동 처리. 로컬과 CI 차이 없음.

## OSS 사용자 — 한 줄로 시작

```bash
git clone <repo>
cd <repo>
tools/install.sh
make all
```

문제 있으면 `tools/install.sh --check`로 어느 도구가 부족한지 확인.
