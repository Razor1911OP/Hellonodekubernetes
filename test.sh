#!/bin/bash
set -euo pipefail

# ===============================
# COLORS
# ===============================
BLUE=$'\033[0;94m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
RED=$'\033[0;91m'
NC=$'\033[0m'
BOLD=$'\033[1m'

# ===============================
# FUNCTIONS
# ===============================

log() {
  echo "${BLUE}${BOLD}▶ $1${NC}"
}

success() {
  echo "${GREEN}✔ $1${NC}"
}

error() {
  echo "${RED}${BOLD}✖ $1${NC}"
  exit 1
}

wait_for_pods() {
  log "Waiting for pods to be ready..."
  kubectl wait \
    --for=condition=Ready \
    pod \
    --selector=app=hello-node \
    --timeout=180s
}

wait_for_service_ip() {
  log "Waiting for external IP..."

  for i in {1..30}; do
    IP=$(kubectl get svc hello-node \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

    if [[ -n "$IP" ]]; then
      echo "$IP"
      return
    fi

    sleep 10
  done

  error "Timed out waiting for external IP"
}

# ===============================
# HEADER
# ===============================

clear

echo
echo "${BLUE}${BOLD}╔════════════════════════════════════════════╗${NC}"
echo "${BLUE}${BOLD}║     Dr Abhishek – GKE Automation Script     ║${NC}"
echo "${BLUE}${BOLD}╚════════════════════════════════════════════╝${NC}"
echo

# ===============================
# PROJECT CONFIG
# ===============================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

[[ -z "$PROJECT_ID" ]] && error "No GCP project set"

ZONE=$(gcloud config get-value compute/zone 2>/dev/null)

[[ -z "$ZONE" ]] && error "No compute zone set"

REGION="${ZONE%-*}"

REPO="my-docker-repo"
IMAGE="hello-node"

log "Project: $PROJECT_ID"
log "Zone:    $ZONE"
log "Region:  $REGION"

# ===============================
# STEP 1: APP FILES
# ===============================

log "Creating Node.js app..."

cat > server.js <<EOF
var http = require('http');

var handleRequest = function(req, res) {
  res.writeHead(200);
  res.end("Hello World!");
};

http.createServer(handleRequest).listen(8080);
EOF

cat > Dockerfile <<EOF
FROM node:18-alpine
WORKDIR /app
COPY server.js .
EXPOSE 8080
CMD ["node","server.js"]
EOF

success "Application files created"

# ===============================
# STEP 2: ARTIFACT REGISTRY
# ===============================

log "Creating Artifact Registry..."

gcloud artifacts repositories create "$REPO" \
  --repository-format=docker \
  --location="$REGION" \
  --quiet || true

gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

IMAGE_URI="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/$IMAGE"

success "Registry ready"

# ===============================
# STEP 3: BUILD IMAGE
# ===============================

log "Building Docker image..."

docker build -t "$IMAGE_URI:v1" .

success "Image built"

# ===============================
# STEP 4: PUSH IMAGE
# ===============================

log "Pushing image..."

docker push "$IMAGE_URI:v1"

success "Image pushed"

# ===============================
# STEP 5: CREATE CLUSTER
# ===============================

log "Creating GKE cluster..."

gcloud container clusters create hello-world \
  --zone="$ZONE" \
  --num-nodes=2 \
  --machine-type=e2-medium \
  --quiet || true

gcloud container clusters get-credentials hello-world \
  --zone="$ZONE" \
  --quiet

success "Cluster ready"

# ===============================
# STEP 6: DEPLOY
# ===============================

log "Deploying application..."

kubectl create deployment hello-node \
  --image="$IMAGE_URI:v1" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl set image deployment/hello-node \
  hello-node="$IMAGE_URI:v1"

success "Deployment created"

# ===============================
# STEP 7: EXPOSE
# ===============================

log "Creating service..."

kubectl expose deployment hello-node \
  --type=LoadBalancer \
  --port=8080 \
  --dry-run=client -o yaml | kubectl apply -f -

success "Service exposed"

# ===============================
# STEP 8: SCALE
# ===============================

log "Scaling deployment..."

kubectl scale deployment hello-node --replicas=4

success "Scaled to 4 replicas"

# ===============================
# STEP 9: WAIT
# ===============================

wait_for_pods

SERVICE_IP=$(wait_for_service_ip)

# ===============================
# FINAL
# ===============================

echo
echo "${GREEN}${BOLD}🎉 Deployment Successful!${NC}"
echo
echo "${YELLOW}Application URL:${NC}"
echo "${BLUE}http://$SERVICE_IP:8080${NC}"
echo
echo "${GREEN}YouTube: https://www.youtube.com/@drabhishek.5460${NC}"
echo
