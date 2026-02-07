#!/bin/bash
set -e

# ================== COLORS ==================
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
RESET="\033[0m"
BOLD="\033[1m"

# ================== FUNCTIONS ==================

retry() {
  local retries=5
  local count=0
  until "$@"; do
    exit_code=$?
    count=$((count + 1))
    if [ $count -ge $retries ]; then
      echo -e "${RED}❌ Command failed after $retries attempts.${RESET}"
      exit $exit_code
    fi
    echo -e "${YELLOW}⚠️ Retry $count/$retries...${RESET}"
    sleep 5
  done
}

pause() {
  echo
  read -p "👉 Press ENTER to continue..." temp
}

checkpoint() {
  echo
  read -p "❓ Continue? (Y/n): " ans
  case "$ans" in
    [Nn]*) echo "Exiting..."; exit 0 ;;
  esac
}

# ================== HEADER ==================

clear
echo -e "${CYAN}${BOLD}"
echo "================================================="
echo "   🚀 GSP1021 Terraform Policy Validation Lab"
echo "================================================="
echo -e "${RESET}"

# ================== ENV SETUP ==================

echo -e "${BLUE}🔍 Detecting environment...${RESET}"

PROJECT_ID=$(gcloud config get-value project)
USER_EMAIL=$(gcloud config get-value account)

if [[ -z "$PROJECT_ID" || -z "$USER_EMAIL" ]]; then
  echo -e "${RED}❌ Could not detect project/user.${RESET}"
  exit 1
fi

echo -e "${GREEN}✅ Project: $PROJECT_ID${RESET}"
echo -e "${GREEN}✅ User:    $USER_EMAIL${RESET}"

pause

# ================== CLONE REPO ==================

echo -e "${BLUE}📥 Cloning policy library...${RESET}"

if [ ! -d "policy-library" ]; then
  retry git clone https://github.com/GoogleCloudPlatform/policy-library.git
fi

cd policy-library

# ================== COPY CONSTRAINT ==================

echo -e "${BLUE}📄 Copying constraint...${RESET}"

cp samples/iam_service_accounts_only.yaml policies/constraints/

echo -e "${GREEN}✅ Constraint copied${RESET}"

pause

# ================== CREATE main.tf ==================

echo -e "${BLUE}📝 Creating Terraform file...${RESET}"

cat > main.tf <<EOF
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 3.84"
    }
  }
}

resource "google_project_iam_binding" "sample_iam_binding" {
  project = "$PROJECT_ID"
  role    = "roles/viewer"

  members = [
    "user:$USER_EMAIL"
  ]
}
EOF

echo -e "${GREEN}✅ main.tf created${RESET}"

pause

# ================== TERRAFORM INIT ==================

echo -e "${BLUE}⚙️ Initializing Terraform...${RESET}"

retry terraform init

# ================== PLAN ==================

echo -e "${BLUE}📊 Creating Terraform plan...${RESET}"

retry terraform plan -out=test.tfplan

# ================== JSON CONVERT ==================

echo -e "${BLUE}📄 Converting plan to JSON...${RESET}"

terraform show -json test.tfplan > tfplan.json

# ================== INSTALL TOOLS ==================

echo -e "${BLUE}🧩 Installing terraform tools...${RESET}"

retry sudo apt-get update
retry sudo apt-get install -y google-cloud-sdk-terraform-tools

# ================== FIRST VALIDATION ==================

echo -e "${BLUE}🔍 Running first validation (expect FAIL)...${RESET}"

set +e
gcloud beta terraform vet tfplan.json --policy-library=. > first_check.log 2>&1
set -e

if grep -q "unexpected domain" first_check.log; then
  echo -e "${GREEN}✅ Expected violation detected${RESET}"
else
  echo -e "${RED}❌ Expected violation not found${RESET}"
  cat first_check.log
  exit 1
fi

pause
checkpoint

# ================== MODIFY CONSTRAINT ==================

echo -e "${BLUE}✏️ Updating constraint to allow qwiklabs.net...${RESET}"

cat > policies/constraints/iam_service_accounts_only.yaml <<EOF
apiVersion: constraints.gatekeeper.sh/v1alpha1
kind: GCPIAMAllowedPolicyMemberDomainsConstraintV1
metadata:
  name: service_accounts_only
spec:
  severity: high
  match:
    target: ["organizations/**"]
  parameters:
    domains:
      - gserviceaccount.com
      - qwiklabs.net
EOF

echo -e "${GREEN}✅ Constraint updated${RESET}"

pause

# ================== REPLAN ==================

echo -e "${BLUE}📊 Recreating plan...${RESET}"

retry terraform plan -out=test.tfplan
terraform show -json test.tfplan > tfplan.json

# ================== SECOND VALIDATION ==================

echo -e "${BLUE}🔍 Running second validation (expect PASS)...${RESET}"

retry gcloud beta terraform vet tfplan.json --policy-library=.

echo -e "${GREEN}✅ Validation passed${RESET}"

pause
checkpoint

# ================== APPLY ==================

echo -e "${BLUE}🚀 Applying Terraform plan...${RESET}"

retry terraform apply -auto-approve test.tfplan

# ================== FINAL ==================

echo
echo -e "${CYAN}${BOLD}"
echo "================================================="
echo " 🎉 LAB COMPLETED SUCCESSFULLY!"
echo "================================================="
echo -e "${RESET}"

echo -e "${GREEN}Now click Check My Progress in the lab page.${RESET}"
echo
echo -e "${BLUE}📌 Lab Link:${RESET}"
echo -e "https://www.cloudskillsboost.google/focuses/10209"
echo

echo -e "${YELLOW}If score is not updated, wait 30s and retry.${RESET}"
echo
