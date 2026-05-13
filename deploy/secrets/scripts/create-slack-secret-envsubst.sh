#!/usr/bin/env bash
# 빠른 검증용 — 환경변수 `$SLACK_WEBHOOK_URL`을 받아 `alertmanager-slack-webhook` Secret을
# 클러스터에 1회성으로 주입. local kind 클러스터, 첫 staging, 통합 검증 시에만 사용.
#
# 운영 환경엔 사용 X — kubectl create secret 명령이 셸 history와 audit log에 평문 URL을
# 남김. sealed/ 또는 eso/ 패턴으로 교체.
#
# Usage:
#   export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/XXX/YYY/ZZZ'
#   bash deploy/secrets/scripts/create-slack-secret-envsubst.sh
#
#   # 다른 ns 또는 다른 이름이 필요하면:
#   NAMESPACE=monitoring NAME=alertmanager-slack-webhook bash ...
#
# 멱등 — Secret이 이미 있으면 갱신 (kubectl apply 패턴).

set -euo pipefail

NAMESPACE="${NAMESPACE:-monitoring}"
NAME="${NAME:-alertmanager-slack-webhook}"
WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

if [[ -z "${WEBHOOK_URL}" ]]; then
    echo "[error] SLACK_WEBHOOK_URL 환경변수가 비어 있다." >&2
    echo "사용 예: export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/XXX/YYY/ZZZ'" >&2
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "[error] kubectl이 PATH에 없다." >&2
    exit 1
fi

# Secret 형식 검증 — Slack webhook URL은 https://hooks.slack.com/services/ 로 시작.
if [[ ! "${WEBHOOK_URL}" =~ ^https://hooks\.slack\.com/services/ ]]; then
    echo "[warn] SLACK_WEBHOOK_URL이 https://hooks.slack.com/services/ 로 시작하지 않는다." >&2
    echo "       의도된 값이면 무시. (e.g. local proxy)" >&2
fi

echo "[..] creating/updating Secret ${NAMESPACE}/${NAME}..."
kubectl create secret generic "${NAME}" \
    --namespace "${NAMESPACE}" \
    --from-literal=url="${WEBHOOK_URL}" \
    --dry-run=client -o yaml \
    | kubectl apply -f -

echo "[ok] done. Verify: kubectl -n ${NAMESPACE} get secret ${NAME}"
