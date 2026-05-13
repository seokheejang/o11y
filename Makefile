SHELL := /usr/bin/env bash

.PHONY: help all vendor build test lint clean e2e-up e2e-verify e2e-down

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

all: vendor build test lint ## vendor → build → test → lint

vendor: ## Install jsonnet dependencies (jb install → vendor/)
	jb install
	@touch vendor/.jb-stamp

build: ## Compile jsonnet → manifests/
	bash tools/build.sh

test: build ## Run promtool test rules
	bash tools/validate.sh test

lint: build ## Run kubeconform on manifests/
	bash tools/validate.sh lint

clean: ## Remove build artifacts
	rm -rf manifests/prometheus-rules manifests/prometheus-rules-meta manifests/grafana-dashboards manifests/alertmanager-config out/
	@mkdir -p manifests/prometheus-rules manifests/grafana-dashboards manifests/alertmanager-config
	@echo "cleaned manifests/{prometheus-rules,prometheus-rules-meta,grafana-dashboards,alertmanager-config} + out/"

e2e-up: ## Bring up kind cluster + kube-prometheus-stack
	bash e2e/scripts/cluster.sh setup

e2e-verify: ## Verify kind cluster + manifests applied
	bash e2e/scripts/cluster.sh verify

e2e-down: ## Tear down kind cluster
	bash e2e/scripts/cluster.sh teardown
