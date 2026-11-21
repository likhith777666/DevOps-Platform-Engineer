
#!/usr/bin/env bash
set -Eeuo pipefail

# --------------------------------------------------
# Configuration
# --------------------------------------------------
CLUSTER_NAME="demo"
NAMESPACE="demo"
RELEASE_NAME="demo"
IMAGE_NAME="my-flask-app"
IMAGE_TAG="1.0.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="${ROOT_DIR}/service"
CHART_DIR="${ROOT_DIR}/chart"

INGRESS_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/kind/deploy.yaml"
KUBE_CONTEXT="kind-${CLUSTER_NAME}"

# --------------------------------------------------
# Helpers
# --------------------------------------------------
log() {
    echo
    echo "==> $*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# --------------------------------------------------
# 1. Check prerequisites and files
# --------------------------------------------------
log "Checking required commands"

for cmd in docker kind kubectl helm; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' is not installed or not in PATH."
done

[[ -f "${SERVICE_DIR}/Dockerfile" ]] || die "Missing service/Dockerfile"
[[ -f "${CHART_DIR}/Chart.yaml" ]] || die "Missing chart/Chart.yaml"
[[ -f "${CHART_DIR}/values.yaml" ]] || die "Missing chart/values.yaml"

docker info >/dev/null 2>&1 || die "Docker is not running. Start Docker Desktop or the Docker daemon."

# --------------------------------------------------
# 2. Create or reuse kind cluster
# --------------------------------------------------
log "Creating or reusing kind cluster: ${CLUSTER_NAME}"

if kind get clusters | grep -Fxq "${CLUSTER_NAME}"; then
    log "Kind cluster '${CLUSTER_NAME}' already exists; reusing it."
else
    log "Creating kind cluster '${CLUSTER_NAME}'"

    TMP_CONFIG="$(mktemp)"
    trap 'rm -f "${TMP_CONFIG}"' EXIT

    cat > "${TMP_CONFIG}" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    labels:
      ingress-ready: "true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
EOF

    kind create cluster \
        --name "${CLUSTER_NAME}" \
        --config "${TMP_CONFIG}" \
        --wait 180s
fi

# Always target the intended kind cluster, not whichever context was active.
kubectl config use-context "${KUBE_CONTEXT}" >/dev/null
kubectl --context "${KUBE_CONTEXT}" cluster-info

# Ensure the control-plane node is eligible for the kind ingress controller.
kubectl --context "${KUBE_CONTEXT}" label node \
    "${CLUSTER_NAME}-control-plane" ingress-ready=true --overwrite

# --------------------------------------------------
# 3. Install or update ingress-nginx
# --------------------------------------------------
log "Installing or updating ingress-nginx"

kubectl --context "${KUBE_CONTEXT}" apply -f "${INGRESS_MANIFEST}"

kubectl --context "${KUBE_CONTEXT}" rollout status \
    deployment/ingress-nginx-controller \
    --namespace ingress-nginx \
    --timeout=300s

# --------------------------------------------------
# 4. Build Docker image
# --------------------------------------------------
log "Building Docker image ${IMAGE_NAME}:${IMAGE_TAG}"

docker build \
    --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
    "${SERVICE_DIR}"

# --------------------------------------------------
# 5. Load image into kind
# --------------------------------------------------
log "Loading image into kind cluster"

kind load docker-image "${IMAGE_NAME}:${IMAGE_TAG}" \
    --name "${CLUSTER_NAME}"

# --------------------------------------------------
# 6. Validate Helm chart
# --------------------------------------------------
log "Validating Helm chart"

helm lint "${CHART_DIR}"

# --------------------------------------------------
# 7. Install or upgrade Helm release
# --------------------------------------------------
log "Installing or upgrading Helm release"

helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}" \
    --kube-context "${KUBE_CONTEXT}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set image.repository="${IMAGE_NAME}" \
    --set image.tag="${IMAGE_TAG}" \
    --set image.pullPolicy=IfNotPresent \
    --wait \
    --timeout 300s

# --------------------------------------------------
# 8. Wait for application deployment
# --------------------------------------------------
log "Waiting for application deployment"

kubectl --context "${KUBE_CONTEXT}" rollout status \
    "deployment/${RELEASE_NAME}" \
    --namespace "${NAMESPACE}" \
    --timeout=300s

# --------------------------------------------------
# 9. Display deployment status
# --------------------------------------------------
log "Deployment status"

kubectl --context "${KUBE_CONTEXT}" get nodes
kubectl --context "${KUBE_CONTEXT}" get pods -n "${NAMESPACE}"
kubectl --context "${KUBE_CONTEXT}" get services -n "${NAMESPACE}"
kubectl --context "${KUBE_CONTEXT}" get ingress -n "${NAMESPACE}"

log "Setup completed successfully."
