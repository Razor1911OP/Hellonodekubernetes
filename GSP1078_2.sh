#!/bin/bash
set -e

#################################
# COLORS
#################################
GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; RESET="\e[0m"; BOLD="\e[1m"

#################################
# VARS
#################################

PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
REGION=us-central1

cd ~/cloudrun-progression

#################################
# TASK 2 DEPLOY
#################################

echo -e "${BLUE}Deploying Cloud Run...${RESET}"

gcloud builds submit --tag gcr.io/$PROJECT_ID/hello-cloudrun

gcloud run deploy hello-cloudrun \
--image gcr.io/$PROJECT_ID/hello-cloudrun \
--platform managed \
--region $REGION \
--tag=prod -q

#################################
# TEST PROD
#################################

PROD_URL=$(gcloud run services describe hello-cloudrun \
--region $REGION --format="value(status.url)")

curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" $PROD_URL

echo
echo -e "${GREEN}TASK 2 COMPLETE${RESET}"
echo "👉 Click Check My Progress (Cloud Run)"

#################################
# TASK 3 GITHUB CONNECT
#################################

echo -e "${BLUE}Connecting GitHub...${RESET}"

gcloud builds connections create github cloud-build-connection \
--project=$PROJECT_ID --region=$REGION || true

gcloud builds connections describe cloud-build-connection \
--region=$REGION

echo
echo -e "${YELLOW}${BOLD}OPEN actionUri URL ABOVE IN BROWSER${RESET}"
read -p "Press ENTER after authorization..."

#################################
# REPO LINK
#################################

GITHUB_USERNAME=$(gh api user -q ".login")

gcloud builds repositories create cloudrun-progression \
--remote-uri="https://github.com/$GITHUB_USERNAME/cloudrun-progression.git" \
--connection=cloud-build-connection \
--region=$REGION || true

#################################
# BRANCH TRIGGER
#################################

gcloud builds triggers create github \
--name="branch" \
--repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
--build-config=branch-cloudbuild.yaml \
--service-account=$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
--region=$REGION \
--branch-pattern='[^(?!.*master)].*' || true

#################################
# DEV BRANCH
#################################

git checkout -b new-feature-1 || true

sed -i "s/v1.0/v1.1/g" app.py

git add .
git commit -m "update v1.1" || true
git push gcp new-feature-1

sleep 120

echo
echo -e "${GREEN}TASK 3 COMPLETE${RESET}"
echo "👉 Click Check My Progress (Branch Trigger)"

#################################
# TASK 4 CANARY
#################################

gcloud builds triggers create github \
--name="master" \
--repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
--build-config=master-cloudbuild.yaml \
--service-account=$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
--region=$REGION \
--branch-pattern='master' || true

git checkout master
git merge new-feature-1
git push gcp master

sleep 180

echo
echo -e "${GREEN}TASK 4 COMPLETE${RESET}"
echo "👉 Click Check My Progress (Canary)"

#################################
# TASK 5 TAG
#################################

gcloud builds triggers create github \
--name="tag" \
--repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/cloudrun-progression \
--build-config=tag-cloudbuild.yaml \
--service-account=$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
--region=$REGION \
--tag-pattern='.*' || true

git tag 1.1 || true
git push gcp 1.1

sleep 180

echo
echo -e "${GREEN}TASK 5 COMPLETE${RESET}"
echo "👉 Click Check My Progress (Tag Release)"

#################################
# FINAL
#################################

echo
echo -e "${GREEN}${BOLD}GSP1078 COMPLETE${RESET}"
echo "Task 6 (Cleanup) is optional — no score"
