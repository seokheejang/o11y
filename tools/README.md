# tools/

빌드·검증 헬퍼 스크립트.

## 스크립트

### `build.sh` — jsonnet → manifests/

`mixins/main.libsonnet`을 입력으로 `manifests/{prometheus-rules,grafana-dashboards}/*.yaml`을 생성한다. 패턴은 [kube-prometheus의 `build.sh`](https://github.com/prometheus-operator/kube-prometheus/blob/main/build.sh) — `jsonnet -m` 멀티파일 출력 + `gojsontoyaml`로 JSON→YAML 변환.

부산물로 `out/prometheus-rules-raw/<name>.yaml`도 생성한다. `PrometheusRule` CR에서 `.spec`만 추출한 raw rules — `promtool test rules`가 CR 구조를 이해하지 못하므로 별도 형식이 필요.

### `validate.sh` — promtool + kubeconform

```bash
tools/validate.sh test    # promtool test rules tests/*.yaml
tools/validate.sh lint    # kubeconform on manifests/
tools/validate.sh all     # both
```

Makefile에서 `make test` / `make lint`로 호출.

## 필요 도구

| 도구 | 설치 |
|------|------|
| [`jsonnet`](https://github.com/google/go-jsonnet) (go-jsonnet) | `go install github.com/google/go-jsonnet/cmd/jsonnet@v0.20.0` |
| [`jb`](https://github.com/jsonnet-bundler/jsonnet-bundler) | `go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@v0.6.0` |
| [`gojsontoyaml`](https://github.com/brancz/gojsontoyaml) | `go install github.com/brancz/gojsontoyaml@latest` |
| [`yq`](https://github.com/mikefarah/yq) v4 | `brew install yq` |
| [`promtool`](https://prometheus.io/docs/prometheus/latest/command-line/promtool/) | Prometheus 릴리스 tarball에서 추출 (v2.55.x) |
| [`kubeconform`](https://github.com/yannh/kubeconform) | `brew install kubeconform` |
