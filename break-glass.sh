#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ROOT_DIR}/.project.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: ${ENV_FILE} does not exist."
    echo "Run ./bootstrap.sh first."
    exit 1
fi

# Load SID, CLUSTER_NAME and NAMESPACE.
# shellcheck disable=SC1090
source "$ENV_FILE"

ADMIN_KUBECONFIG="${ROOT_DIR}/kubeconfigs/break-glass-admin.kubeconfig"

cleanup() {
    rm -f "$ADMIN_KUBECONFIG"
}

trap cleanup EXIT

echo
echo "============================================================"
echo "WARNING: BREAK-GLASS ADMINISTRATOR ACCESS"
echo "Cluster:   ${CLUSTER_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "============================================================"
echo
echo "Use this access only after diagnosing a confirmed RBAC failure."
echo "Exit the administrator shell immediately after recovery."
echo

kind get kubeconfig \
  --name "$CLUSTER_NAME" \
  > "$ADMIN_KUBECONFIG"

chmod 600 "$ADMIN_KUBECONFIG"

echo "Opening break-glass administrator shell..."
echo "Run 'exit' when the repair is complete."
echo

KUBECONFIG="$ADMIN_KUBECONFIG" \
PS1="[BREAK-GLASS ${CLUSTER_NAME}] \u@\h:\w\$ " \
bash --noprofile --norc -i

echo
echo "Break-glass administrator shell closed."
echo "Temporary administrator kubeconfig removed."
