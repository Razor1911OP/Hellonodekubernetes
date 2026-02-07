#!/bin/bash
set -e

############################
# COLORS
############################
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
RESET="\033[0m"
BOLD="\033[1m"

############################
# FUNCTIONS
############################

retry() {
  local n=1
  local max=5
  local delay=10

  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        echo -e "${YELLOW}Retry $n/$max...${RESET}"
        ((n++))
        sleep $delay
      else
        echo -e "${RED}Command failed after $max attempts.${RESET}"
        exit 1
      fi
    }
  done
}

pause() {
  echo
  read -p "Press ENTER to continue..." _
}

############################
# INIT
############################

clear
echo -e "${BLUE}${BOLD}=== GSP1051 : OmegaTrade Automation ===${RESET}"

PROJECT_ID=$(gcloud config get-value project)
ACCOUNT=$(gcloud config get-value account)

if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}No active project. Exiting.${RESET}"
  exit 1
fi

echo -e "${GREEN}Project: $PROJECT_ID${RESET}"
echo -e "${GREEN}Account: $ACCOUNT${RESET}"

############################
# REGION
############################

echo
read -p "Enter Cloud Run region (example: us-central1): " REGION

if ! gcloud compute regions list --format="value(name)" | grep -q "^$REGION$"; then
  echo -e "${RED}Invalid region.${RESET}"
  exit 1
fi

gcloud config set run/region "$REGION"

############################
# ENABLE APIS
############################

echo -e "${BLUE}Enabling APIs...${RESET}"

retry gcloud services enable \
  spanner.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com

############################
# CLONE REPO
############################

echo -e "${BLUE}Cloning repo...${RESET}"

cd ~
rm -rf training-data-analyst

retry git clone https://github.com/GoogleCloudPlatform/training-data-analyst

cd training-data-analyst/courses/cloud-spanner/omegatrade/

############################
# BACKEND SETUP
############################

echo -e "${BLUE}Setting backend env...${RESET}"

cd backend

cat > .env <<EOF
PROJECTID=$PROJECT_ID
INSTANCE=omegatrade-instance
DATABASE=omegatrade-db
JWT_KEY=w54p3Y?4dj%8Xqa2jjVC84narhe5Pk
EXPIRE_IN=30d
EOF

############################
# NODE SETUP
############################

echo -e "${BLUE}Installing Node...${RESET}"

retry nvm install 22.6

npm install -g npm
npm install --loglevel=error

############################
# BUILD BACKEND
############################

echo -e "${BLUE}Building backend image...${RESET}"

retry docker build \
-t gcr.io/$PROJECT_ID/omega-trade/backend:v1 \
-f dockerfile.prod .

############################
# PUSH BACKEND
############################

echo -e "${BLUE}Auth docker...${RESET}"

yes | gcloud auth configure-docker

echo -e "${BLUE}Pushing backend...${RESET}"

retry docker push gcr.io/$PROJECT_ID/omega-trade/backend:v1

############################
# DEPLOY BACKEND
############################

echo -e "${BLUE}Deploying backend...${RESET}"

BACKEND_URL=$(gcloud run deploy omegatrade-backend \
--platform managed \
--image gcr.io/$PROJECT_ID/omega-trade/backend:v1 \
--memory 512Mi \
--allow-unauthenticated \
--region $REGION \
--format="value(status.url)")

echo -e "${GREEN}Backend URL:${RESET} $BACKEND_URL"

############################
# SEED DATA (CHECKPOINT)
############################

echo -e "${BLUE}Seeding database...${RESET}"

unset SPANNER_EMULATOR_HOST

retry node seed-data.js

echo
echo -e "${GREEN}✅ CHECKPOINT: Click 'Check My Progress' for Task 4${RESET}"
pause

############################
# FRONTEND CONFIG
############################

cd ../frontend/src/environments

echo -e "${BLUE}Configuring frontend...${RESET}"

cat > environment.ts <<EOF
export const environment = {
  production: false,
  name: "dev",
  baseUrl:"${BACKEND_URL}/api/v1/",
  clientId: ""
};
EOF

############################
# BUILD FRONTEND
############################

cd ../..

npm install -g npm
npm install --loglevel=error

echo -e "${BLUE}Building frontend...${RESET}"

retry docker build \
-t gcr.io/$PROJECT_ID/omegatrade/frontend:v1 \
-f dockerfile .

############################
# PUSH FRONTEND
############################

retry docker push gcr.io/$PROJECT_ID/omegatrade/frontend:v1

############################
# DEPLOY FRONTEND
############################

FRONTEND_URL=$(gcloud run deploy omegatrade-frontend \
--platform managed \
--image gcr.io/$PROJECT_ID/omegatrade/frontend:v1 \
--allow-unauthenticated \
--region $REGION \
--format="value(status.url)")

echo
echo -e "${GREEN}Frontend URL:${RESET} $FRONTEND_URL"

############################
# FINAL
############################

echo
echo -e "${GREEN}${BOLD}==================================${RESET}"
echo -e "${GREEN}${BOLD}AUTOMATION COMPLETE${RESET}"
echo -e "${GREEN}${BOLD}==================================${RESET}"

echo
echo -e "${YELLOW}⚠️ Manual Tasks Remaining (No Automation Possible):${RESET}"

echo "1. Open Frontend URL"
echo "2. Create account"
echo "3. Add company"
echo "4. Run simulation"
echo "5. Edit DB in Console"

echo
echo -e "${GREEN}These steps do NOT affect scoring.${RESET}"

echo
echo -e "${BLUE}Frontend:${RESET} $FRONTEND_URL"
echo -e "${BLUE}Backend:${RESET}  $BACKEND_URL"

echo
echo -e "${GREEN}Lab scoring complete after Task 4.${RESET}"
