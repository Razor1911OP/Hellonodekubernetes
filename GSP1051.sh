#!/bin/bash
set -e

########################################
# CONFIG
########################################

MAX_RETRIES=5
BACKEND_SERVICE="omegatrade-backend"
FRONTEND_SERVICE="omegatrade-frontend"
INSTANCE="omegatrade-instance"
DATABASE="omegatrade-db"

########################################
# COLORS
########################################

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"
BOLD="\e[1m"

########################################
# FUNCTIONS
########################################

retry() {
  local n=1
  until [ $n -gt $MAX_RETRIES ]; do
    "$@" && break
    echo -e "${YELLOW}Retry $n/$MAX_RETRIES...${RESET}"
    sleep 10
    ((n++))
  done

  if [ $n -gt $MAX_RETRIES ]; then
    echo -e "${RED}Command failed permanently${RESET}"
    exit 1
  fi
}

checkpoint() {
  echo
  echo -e "${BLUE}${BOLD}================================================${RESET}"
  echo -e "${GREEN}${BOLD}CHECKPOINT:${RESET} $1"
  echo -e "${YELLOW}👉 Click: Check My Progress in Lab UI${RESET}"
  echo -e "${BLUE}${BOLD}================================================${RESET}"
  echo
}

pause_manual() {
  echo
  echo -e "${YELLOW}${BOLD}MANUAL STEP REQUIRED:${RESET}"
  echo "$1"
  read -p "Press ENTER after completing..."
}

########################################
# PROJECT SETUP
########################################

echo -e "${BLUE}${BOLD}Initializing Environment...${RESET}"

PROJECT_ID=$(gcloud config get-value project)
ACCOUNT=$(gcloud config get-value account)

REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")

if [[ -z "$REGION" ]]; then
  REGION="us-central1"
fi

gcloud config set project "$PROJECT_ID"
gcloud config set compute/region "$REGION"

echo "Project : $PROJECT_ID"
echo "Region  : $REGION"
echo "Account : $ACCOUNT"

########################################
# ENABLE APIS
########################################

echo -e "${BLUE}${BOLD}Enabling APIs...${RESET}"

retry gcloud services enable \
  spanner.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com

########################################
# NVM + NODE FIX
########################################

echo -e "${BLUE}${BOLD}Setting up Node (NVM)...${RESET}"

export NVM_DIR="$HOME/.nvm"

if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  echo "Installing NVM..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi

source "$NVM_DIR/nvm.sh"

retry nvm install 22.6
nvm use 22.6
nvm alias default 22.6

node -v
npm -v

########################################
# DOWNLOAD CODE
########################################

echo -e "${BLUE}${BOLD}Downloading Repo...${RESET}"

if [ ! -d training-data-analyst ]; then
  retry git clone https://github.com/GoogleCloudPlatform/training-data-analyst
fi

cd training-data-analyst/courses/cloud-spanner/omegatrade/

########################################
# BACKEND SETUP
########################################

echo -e "${BLUE}${BOLD}Backend Setup...${RESET}"

cd backend

cat > .env <<EOF
PROJECTID=$PROJECT_ID
INSTANCE=$INSTANCE
DATABASE=$DATABASE
JWT_KEY=w54p3Y?4dj%8Xqa2jjVC84narhe5Pk
EXPIRE_IN=30d
EOF

npm install -g npm
npm install --loglevel=error

########################################
# DOCKER AUTH
########################################

echo -e "${BLUE}${BOLD}Configuring Docker...${RESET}"

retry gcloud auth configure-docker --quiet

########################################
# BUILD + PUSH BACKEND
########################################

BACKEND_IMG="gcr.io/$PROJECT_ID/omega-trade/backend:v1"

echo -e "${BLUE}${BOLD}Building Backend...${RESET}"

retry docker build -t $BACKEND_IMG -f dockerfile.prod .

retry docker push $BACKEND_IMG

########################################
# DEPLOY BACKEND
########################################

echo -e "${BLUE}${BOLD}Deploying Backend...${RESET}"

BACKEND_URL=$(gcloud run deploy $BACKEND_SERVICE \
  --platform managed \
  --region $REGION \
  --image $BACKEND_IMG \
  --memory 512Mi \
  --allow-unauthenticated \
  --format="value(status.url)")

echo "Backend URL: $BACKEND_URL"

########################################
# LOAD DATA
########################################

unset SPANNER_EMULATOR_HOST

echo -e "${BLUE}${BOLD}Seeding Database...${RESET}"

retry node seed-data.js

checkpoint "Import sample stock trade data"

########################################
# FRONTEND SETUP
########################################

echo -e "${BLUE}${BOLD}Frontend Setup...${RESET}"

cd ../frontend/src/environments

sed -i "s|http://localhost:3000|$BACKEND_URL/api/v1|g" environment.ts

cd ../..

npm install -g npm
npm install --loglevel=error

########################################
# BUILD + PUSH FRONTEND
########################################

FRONTEND_IMG="gcr.io/$PROJECT_ID/omegatrade/frontend:v1"

echo -e "${BLUE}${BOLD}Building Frontend...${RESET}"

retry docker build -t $FRONTEND_IMG -f dockerfile .

retry docker push $FRONTEND_IMG

########################################
# DEPLOY FRONTEND
########################################

echo -e "${BLUE}${BOLD}Deploying Frontend...${RESET}"

FRONTEND_URL=$(gcloud run deploy $FRONTEND_SERVICE \
  --platform managed \
  --region $REGION \
  --image $FRONTEND_IMG \
  --allow-unauthenticated \
  --format="value(status.url)")

echo "Frontend URL: $FRONTEND_URL"

########################################
# MANUAL APP TASKS
########################################

pause_manual "
1. Open: $FRONTEND_URL
2. Sign up:
   admin@spanner1.com / Spanner1
3. Add Company: Spanner1 (SPN)
4. Run Simulation
5. Rename Acme -> Coyote
6. Update Bar Industries in Spanner Console
"

########################################
# FINAL
########################################

echo
echo -e "${GREEN}${BOLD}==============================================${RESET}"
echo -e "${GREEN}${BOLD} GSP1051 AUTOMATION COMPLETE ${RESET}"
echo -e "${GREEN}${BOLD}==============================================${RESET}"
echo

echo -e "${YELLOW}👉 FINAL STEP:${RESET}"
echo -e "Click all remaining ${BOLD}Check My Progress${RESET} buttons"

echo
echo "Frontend URL:"
echo "$FRONTEND_URL"
echo
