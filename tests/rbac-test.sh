#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.project.env"
EXPECTATIONS_FILE="${ROOT_DIR}/tests/expected.txt"
KUBECONFIG_DIR="${ROOT_DIR}/kubeconfigs"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: ${ENV_FILE} does not exist."
    echo "Run ./bootstrap.sh first."
    exit 1
fi

if [[ ! -f "$EXPECTATIONS_FILE" ]]; then
    echo "ERROR: ${EXPECTATIONS_FILE} does not exist."
    exit 1
fi

# Load SID, CLUSTER_NAME and NAMESPACE.
# shellcheck disable=SC1090
source "$ENV_FILE"

PASS_COUNT=0
FAIL_COUNT=0
CHECK_COUNT=0

while IFS='|' read -r persona verb resource namespace_value expected subresource ||
      [[ -n "${persona:-}" ]]; do

    # Ignore comments and blank lines.
    [[ -z "${persona:-}" ]] && continue
    [[ "$persona" == \#* ]] && continue

    if [[ "$namespace_value" == "project" ]]; then
        target_namespace="$NAMESPACE"
    else
        target_namespace="$namespace_value"
    fi

    kubeconfig="${KUBECONFIG_DIR}/${persona}.kubeconfig"
    CHECK_COUNT=$((CHECK_COUNT + 1))

    if [[ ! -f "$kubeconfig" ]]; then
        echo "FAIL: persona=${persona} missing kubeconfig=${kubeconfig}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    can_i_args=(
    auth can-i
    "$verb"
    "$resource"
    -n "$target_namespace"
)

if [[ -n "${subresource:-}" ]]; then
    can_i_args+=(--subresource="$subresource")
fi

actual="$(
    kubectl \
      --kubeconfig "$kubeconfig" \
      "${can_i_args[@]}" \
      2>/dev/null |
    tr -d '\r\n'
)"
subresource_display="${subresource:-none}"
    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: persona=${persona} verb=${verb} resource=${resource} namespace=${target_namespace} expected=${expected} actual=${actual}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "FAIL: persona=${persona} verb=${verb} resource=${resource} namespace=${target_namespace} expected=${expected} actual=${actual}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

done < "$EXPECTATIONS_FILE"

echo
echo "Total checks: ${CHECK_COUNT}"
echo "Passed:       ${PASS_COUNT}"
echo "Failed:       ${FAIL_COUNT}"

if (( FAIL_COUNT > 0 )); then
    exit 1
fi

exit 0
