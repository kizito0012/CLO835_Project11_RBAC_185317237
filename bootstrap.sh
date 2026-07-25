#!/usr/bin/env bash

set -Eeuo pipefail

# Project parameters: change values only here.
SID="185317237"
DOCKERHUB_USER="christian9299"

CLUSTER_NAME="clo835-rbac-${SID}"
NAMESPACE="rbac-${SID}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_DIR="${ROOT_DIR}/kubeconfigs"
RENDER_DIR="${ROOT_DIR}/.rendered"
ENV_FILE="${ROOT_DIR}/.project.env"
MODE="${1:-full}"

log() {
    echo
    echo "============================================================"
    echo "$*"
    echo "============================================================"
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        fail "Required command not found: ${command_name}"
    fi
}

write_project_environment() {
    cat > "$ENV_FILE" <<ENVEOF
SID="${SID}"
DOCKERHUB_USER="${DOCKERHUB_USER}"
CLUSTER_NAME="${CLUSTER_NAME}"
NAMESPACE="${NAMESPACE}"
ENVEOF

    chmod 600 "$ENV_FILE"
}

use_project_context() {
    kubectl config use-context \
      "kind-${CLUSTER_NAME}" \
      >/dev/null
}

render_manifests() {
    log "Rendering manifests with student ID ${SID}"

    rm -rf "$RENDER_DIR"
    mkdir -p "${RENDER_DIR}/manifests/rbac"
    mkdir -p "${RENDER_DIR}/manifests/workload"

    while IFS= read -r -d '' source_file; do
        relative_path="${source_file#${ROOT_DIR}/}"
        target_file="${RENDER_DIR}/${relative_path}"

        mkdir -p "$(dirname "$target_file")"

        sed \
          -e "s/sidplaceholder/${SID}/g" \
          "$source_file" > "$target_file"

    done < <(
        find "${ROOT_DIR}/manifests" \
          -type f \
          -name '*.yaml' \
          -print0
    )

    if grep -Rqs "sidplaceholder" "$RENDER_DIR"; then
        fail "One or more placeholders remain in rendered manifests."
    fi
}

generate_kubeconfig() {
    local persona="$1"
    local service_account="$2"
    local output_file="${KUBECONFIG_DIR}/${persona}.kubeconfig"

    local token
    local server
    local ca_data

    log "Generating kubeconfig for ${persona}"

    token="$(
        kubectl create token "$service_account" \
          -n "$NAMESPACE" \
          --duration=24h
    )"

    server="$(
        kubectl config view \
          --raw \
          --minify \
          -o jsonpath='{.clusters[0].cluster.server}'
    )"

    ca_data="$(
        kubectl config view \
          --raw \
          --minify \
          -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
    )"

    [[ -n "$token" ]] || fail "Could not create token for ${service_account}"
    [[ -n "$server" ]] || fail "Could not determine Kubernetes API server"
    [[ -n "$ca_data" ]] || fail "Could not determine cluster CA data"

    cat > "$output_file" <<KUBECONFIGEOF
apiVersion: v1
kind: Config
clusters:
  - name: ${CLUSTER_NAME}
    cluster:
      server: ${server}
      certificate-authority-data: ${ca_data}
users:
  - name: ${persona}-${SID}
    user:
      token: ${token}
contexts:
  - name: ${persona}-${SID}@${CLUSTER_NAME}
    context:
      cluster: ${CLUSTER_NAME}
      user: ${persona}-${SID}
      namespace: ${NAMESPACE}
current-context: ${persona}-${SID}@${CLUSTER_NAME}
KUBECONFIGEOF

    chmod 600 "$output_file"
}

generate_all_kubeconfigs() {
    mkdir -p "$KUBECONFIG_DIR"

    rm -f \
      "${KUBECONFIG_DIR}/deployer.kubeconfig" \
      "${KUBECONFIG_DIR}/readonly.kubeconfig" \
      "${KUBECONFIG_DIR}/ci.kubeconfig"

    generate_kubeconfig \
      "deployer" \
      "deployer-${SID}"

    generate_kubeconfig \
      "readonly" \
      "readonly-${SID}"

    generate_kubeconfig \
      "ci" \
      "ci-${SID}"
}

apply_rbac() {
    use_project_context
    render_manifests

    log "Applying canonical RBAC manifests"

    kubectl apply \
      -f "${RENDER_DIR}/manifests/rbac"
}

run_full_bootstrap() {
    log "Deleting an older Project 11 cluster if it exists"

    kind delete cluster \
      --name "$CLUSTER_NAME" \
      >/dev/null 2>&1 || true

    log "Creating kind cluster ${CLUSTER_NAME}"

    kind create cluster \
      --name "$CLUSTER_NAME" \
      --config "${ROOT_DIR}/kind-config.yaml"

    use_project_context

    log "Waiting for both kind nodes to become Ready"

    kubectl wait \
      --for=condition=Ready \
      nodes \
      --all \
      --timeout=180s

    log "Creating namespace ${NAMESPACE}"

    kubectl create namespace "$NAMESPACE" \
      --dry-run=client \
      -o yaml |
    kubectl apply -f -

    kubectl label namespace "$NAMESPACE" \
      "owner=${SID}" \
      --overwrite

    render_manifests

    log "Applying ServiceAccounts, Roles and RoleBindings"

    kubectl apply \
      -f "${RENDER_DIR}/manifests/rbac"

    log "Applying demo workload"

    kubectl apply \
      -f "${RENDER_DIR}/manifests/workload"

    log "Waiting for web-${SID} rollout"

    kubectl rollout status \
      "deployment/web-${SID}" \
      -n "$NAMESPACE" \
      --timeout=180s

    generate_all_kubeconfigs

    log "Running RBAC permission tests"

    "${ROOT_DIR}/tests/rbac-test.sh"

    log "Final cluster state"

    kubectl get nodes -o wide

    echo

    kubectl get \
      all,serviceaccounts,roles,rolebindings \
      -n "$NAMESPACE"

    log "Bootstrap completed successfully"
}

for required_command in docker kind kubectl sed find grep; do
    require_command "$required_command"
done

if ! docker info >/dev/null 2>&1; then
    fail "Docker is not running."
fi

[[ -f "${ROOT_DIR}/kind-config.yaml" ]] ||
    fail "kind-config.yaml is missing."

[[ -d "${ROOT_DIR}/manifests/rbac" ]] ||
    fail "manifests/rbac is missing."

[[ -d "${ROOT_DIR}/manifests/workload" ]] ||
    fail "manifests/workload is missing."

write_project_environment

case "$MODE" in
    full)
        run_full_bootstrap
        ;;

    --repair-rbac)
        apply_rbac
        generate_all_kubeconfigs

        log "Running permission tests after RBAC repair"
        "${ROOT_DIR}/tests/rbac-test.sh"
        ;;

    --regenerate-kubeconfigs)
        use_project_context
        generate_all_kubeconfigs

        log "Running tests with regenerated tokens"
        "${ROOT_DIR}/tests/rbac-test.sh"
        ;;

    *)
        echo "Usage:"
        echo "  ./bootstrap.sh"
        echo "  ./bootstrap.sh --repair-rbac"
        echo "  ./bootstrap.sh --regenerate-kubeconfigs"
        exit 1
        ;;
esac
