#!/bin/bash
set -e

#################################
# COLORS
#################################
GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; RESET="\e[0m"; BOLD="\e[1m"

#################################
# PROJECT
#################################

export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export REGION=us-central1

gcloud config set compute/region $REGION

echo "Project: $PROJECT_ID"

#################################
# ENABLE APIS
#################################

echo -e "${BLUE}Enabling APIs...${RESET}"

gcloud services enable \
 cloudresourcemanager.googleapis.com \
 container.googleapis.com \
 cloudbuild.googleapis.com \
 containerregistry.googleapis.com \
 run.googleapis.com \
 secretmanager.googleapis.com

#################################
# IAM
#################################

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member=serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com \
--role=roles/secretmanager.admin

#################################
# GITHUB CLI
#################################

echo -e "${BLUE}Installing GitHub CLI...${RESET}"

curl -sS https://webi.sh/gh | sh

export PATH=$HOME/.local/bin:$PATH

#################################
# AUTH
#################################

echo
echo -e "${YELLOW}${BOLD}LOGIN TO GITHUB NOW${RESET}"
echo "Browser will open. Authenticate."

gh auth login

#################################
# CONFIG GIT
#################################

GITHUB_USERNAME=$(gh api user -q ".login")
USER_EMAIL=$(gh api user -q ".email")

git config --global user.name "$GITHUB_USERNAME"
git config --global user.email "$USER_EMAIL"

echo "GitHub: $GITHUB_USERNAME"

#################################
# CREATE REPO
#################################

gh repo create cloudrun-progression --private || true

#################################
# CLONE
#################################

cd ~

git clone https://github.com/GoogleCloudPlatform/training-data-analyst || true

mkdir -p cloudrun-progression

cp -r ~/training-data-analyst/self-paced-labs/cloud-run/canary/* \
   ~/cloudrun-progression/

cd ~/cloudrun-progression

#################################
# REGION PATCH
#################################

sed -i "s/REGION/us-central1/g" branch-cloudbuild.yaml
sed -i "s/REGION/us-central1/g" master-cloudbuild.yaml
sed -i "s/REGION/us-central1/g" tag-cloudbuild.yaml

#################################
# JSON PATCH
#################################

sed -e "s/PROJECT/${PROJECT_ID}/g" \
    -e "s/NUMBER/${PROJECT_NUMBER}/g" \
    branch-trigger.json-tmpl > branch-trigger.json

sed -e "s/PROJECT/${PROJECT_ID}/g" \
    -e "s/NUMBER/${PROJECT_NUMBER}/g" \
    master-trigger.json-tmpl > master-trigger.json

sed -e "s/PROJECT/${PROJECT_ID}/g" \
    -e "s/NUMBER/${PROJECT_NUMBER}/g" \
    tag-trigger.json-tmpl > tag-trigger.json

#################################
# PUSH
#################################

git init || true
git config credential.helper gcloud.sh
git remote add gcp https://github.com/$GITHUB_USERNAME/cloudrun-progression || true

git branch -m master

git add .
git commit -m "initial commit" || true
git push -u gcp master

#################################
# CHECKPOINT
#################################

echo
echo -e "${GREEN}${BOLD}TASK 1 COMPLETE${RESET}"
echo "👉 Click Check My Progress (Prepare Environment)"
echo
echo "NOW RUN: ./GSP1078_part2.sh"
