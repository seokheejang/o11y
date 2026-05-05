SHELL := /usr/bin/env bash

.PHONY: help vendor build test lint clean

help: ## Show available targets
	@echo "o11y — observability-as-code"
	@echo ""
	@echo "Targets (1차 PR 시점에는 stub — 다음 PR에서 실구현):"
	@echo "  vendor    Install jsonnet dependencies (jb install)"
	@echo "  build     Compile jsonnet → manifests/"
	@echo "  test      Run promtool test rules"
	@echo "  lint      Run jsonnet-lint and kubeconform"
	@echo "  clean     Remove out/ build artifacts"
	@echo "  help      Show this message"

vendor: ## Install jsonnet dependencies
	@echo "[stub] TODO: jb install — implement in next PR"

build: vendor ## Compile jsonnet to manifests/
	@echo "[stub] TODO: jsonnet → manifests/{prometheus-rules,alertmanager-config,grafana-dashboards}/ — implement in next PR"

test: ## Run promtool tests on generated rules
	@echo "[stub] TODO: promtool test rules tests/*.yaml — implement in next PR"

lint: ## Lint jsonnet sources and generated manifests
	@echo "[stub] TODO: jsonnet-lint mixins/ && kubeconform manifests/ — implement in next PR"

clean: ## Remove build artifacts
	rm -rf out/
	@echo "cleaned out/"
