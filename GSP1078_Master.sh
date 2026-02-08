#!/bin/bash
set -e

########################################
# COLORS
########################################
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"

########################################
# GLOBALS
########################################
REGION="us-central1"
RETRY_MAX=5

########################################
# LOGGING
########################################
log() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
  echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  exit 1
}

########################################
# RETRY
########################################
retry() {
  local n=1
  until "$@"; do
    if [[ $n -ge $RETRY_MAX ]]; then
      return 1
    fi
    warn "Retry $n/$RETRY_MAX..."
    ((n++))
    sleep 10
  done
}

########################################
# PRECHECK
########################################
precheck() {

  log "Running preflight checks..."

  command -v gcloud >/dev/null || fail "gcloud missing"
  command -v git >/dev/null || sudo apt install git -y
  command -v jq >/dev/null || sudo apt install jq -y

  if ! command -v gh >/dev/null; then
    curl -sS https://webi.sh/gh | sh
    source ~/.config/envman/PATH.env
  fi

  ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
  [[ -z "$ACCOUNT" ]] && fail "Not authenticated"

  PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
  [[ -z "$PROJECT_ID" ]] && fail "Project not set"

  PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID \
    --format='value(projectNumber)')

  export PROJECT_ID PROJECT_NUMBER REGION

  gcloud config set compute/region $REGION -q

  success "Precheck OK"
}

########################################
# ENABLE APIS
########################################
enable_apis() {

  log "Enabling APIs..."

  retry gcloud services enable \
    cloudresourcemanager.googleapis.com \
    container.googleapis.com \
    cloudbuild.googleapis.com \
    containerregistry.googleapis.com \
    run.googleapis.com \
    secretmanager.googleapis.com

  for api in run.googleapis.com cloudbuild.googleapis.com; do
    until gcloud services list --enabled | grep -q $api; do
      sleep 5
    done
  done

  success "APIs enabled"
}

########################################
# IAM
########################################
setup_iam() {

  log "Configuring IAM..."

  retry gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com \
    --role=roles/secretmanager.admin

  success "IAM configured"
}

########################################
# GITHUB AUTH
########################################
github_auth() {

  log "Authenticating GitHub..."

  if ! gh auth status >/dev/null 2>&1; then
    gh auth login
  fi

  until gh auth status >/dev/null 2>&1; do
    sleep 5
  done

  GITHUB_USERNAME=$(gh api user -q ".login")
  USER_EMAIL=$(gcloud config get-value account)

  git config --global user.name "$GITHUB_USERNAME"
  git config --global user.email "$USER_EMAIL"

  export GITHUB_USERNAME USER_EMAIL

  success "GitHub authenticated"
}

########################################
# REPO SETUP
########################################
setup_repo() {

  log "Setting up repository..."

  gh repo view cloudrun-progression >/dev/null 2>&1 || \
    gh repo create cloudrun-progression --private

  if [[ ! -d training-data-analyst ]]; then
    git clone https://github.com/GoogleCloudPlatform/training-data-analyst
  fi

  rm -rf cloudrun-progression || true
  mkdir cloudrun-progression

  cp -r training-data-analyst/self-paced-labs/cloud-run/canary/* \
    cloudrun-progression/

  cd cloudrun-progression

  sed -e "s/PROJECT/${PROJECT_ID}/g" \
      -e "s/NUMBER/${PROJECT_NUMBER}/g" \
      branch-trigger.json-tmpl > branch-trigger.json

  sed -e "s/PROJECT/${PROJECT_ID}/g" \
      -e "s/NUMBER/${PROJECT_NUMBER}/g" \
      master-trigger.json-tmpl > master-trigger.json

  sed -e "s/PROJECT/${PROJECT_ID}/g" \
      -e "s/NUMBER/${PROJECT_NUMBER}/g" \
      tag-trigger.json-tmpl > tag-trigger.json

  git init
  git remote remove gcp 2>/dev/null || true
  git remote add gcp https://github.com/$GITHUB_USERNAME/cloudrun-progression

  git branch -M master
  git add .
  git commit -m "initial commit" || true
  git push gcp master -f

  success "Repository ready"
}

########################################
# CLOUD RUN BASE
########################################
deploy_base() {

  log "Deploying base service..."

  retry gcloud builds submit \
    --tag gcr.io/$PROJECT_ID/hello-cloudrun

  retry gcloud run deploy hello-cloudrun \
    --image gcr.io/$PROJECT_ID/hello-cloudrun \
    --platform managed \
    --region $REGION \
    --tag=prod -q

  until gcloud run services describe hello-cloudrun \
    --region $REGION >/dev/null 2>&1; do
    sleep 5
  done

  success "Base deployed"
}

########################################
# CONNECTION
########################################
setup_connection() {

  log "Setting up Cloud Build connection..."

  if ! gcloud builds connections list --region=$REGION \
    | grep -q cloud-build-connection; then

    gcloud builds connections create github cloud-build-connection \
      --region=$REGION
  fi

  echo
  warn "AUTHORIZE NOW:"
  gcloud builds connections describe cloud-build-connection \
    --region=$REGION | grep actionUri
  echo

  read -t 900 -p "Authorize GitHub then press ENTER"

  until gcloud builds connections describe cloud-build-connection \
    --region=$REGION | grep -q COMPLETE; do
    sleep 10
  done

  success "Connection active"
}

########################################
# TRIGGERS
########################################
create_triggers() {

  log "Creating triggers..."

  gcloud builds repositories create cloudrun-progression \
    --remote-uri="https://github.com/$GITHUB_USERNAME/cloudrun-progression.git" \
    --connection="cloud-build-connection" \
    --region=$REGION 2>/dev/null || true

  if ! gcloud builds triggers list | grep -q branch; then
    gcloud builds triggers create github \
      --name="branch" \
      --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
      --build-config='branch-cloudbuild.yaml' \
      --service-account=$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
      --region=$REGION \
      --branch-pattern='[^(?!.*master)].*'
  fi

  if ! gcloud builds triggers list | grep -q master; then
    gcloud builds triggers create github \
      --name="master" \
      --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
      --build-config='master-cloudbuild.yaml' \
      --service-account=$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
      --region=$REGION \
      --branch-pattern='master'
  fi

  if ! gcloud builds triggers list | grep -q tag; then
    gcloud builds triggers create github \
      --name="tag" \
      --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
      --build-config='tag-cloudbuild.yaml' \
      --service-account=$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
      --region=$REGION \
      --tag-pattern='.*'
  fi

  success "Triggers ready"
}

########################################
# CANARY FLOW
########################################
run_pipeline() {

  log "Running pipeline..."

  git checkout -b new-feature-1 || git checkout new-feature-1

  sed -i "s/v1.0/v1.1/g" app.py

  git add .
  git commit -m "update v1.1" || true
  git push gcp new-feature-1 -f

  sleep 60

  git checkout master
  git merge new-feature-1 || true
  git push gcp master -f

  sleep 60

  git tag 1.1 || true
  git push gcp 1.1 -f

  success "Pipeline executed"
}

########################################
# SCORE
########################################
show_score() {

  echo
  echo "======================================"
  echo "CLICK CHECK MY PROGRESS:"
  echo
  echo "Task 1: Environment Setup"
  echo "Task 2: Cloud Run Deploy"
  echo "Task 3: Branch Trigger"
  echo "Task 4: Canary Deploy"
  echo "Task 5: Tag Release"
  echo
  echo "Task 6: GitHub Cleanup (Manual)"
  echo "======================================"
}

########################################
# MAIN
########################################
main() {

  precheck
  enable_apis
  setup_iam
  github_auth
  setup_repo
  deploy_base
  setup_connection
  create_triggers
  run_pipeline
  show_score

  success "LAB COMPLETE"
}

main
