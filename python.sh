#!/bin/bash
set -euo pipefail

# =================================================
# FORCE IPV4 EVERYWHERE
# =================================================

export CURL_OPTIONS="-4"

export BOTO_CONFIG=/tmp/boto.conf

cat > $BOTO_CONFIG <<EOF
[Boto]
prefer_ipv6 = False
http_socket_timeout = 60
EOF

export CLOUDSDK_PYTHON_SITEPACKAGES=1
export PYTHONHTTPSVERIFY=1
export GODEBUG=netdns=go

echo "✓ IPv4 networking enforced"

# =================================================
# COLORS
# =================================================

GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
RED=$(tput setaf 1)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# =================================================
# PROJECT CHECK
# =================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
  echo "${RED}❌ No active GCP project found${RESET}"
  exit 1
fi

# =================================================
# FETCH VALID REGIONS
# =================================================

echo "${YELLOW}▶ Fetching valid App Engine regions...${RESET}"

VALID_REGIONS=$(gcloud app regions list \
  --format="value(locationId)" 2>/dev/null)

if [[ -z "$VALID_REGIONS" ]]; then
  echo "${RED}❌ Unable to fetch regions${RESET}"
  exit 1
fi

# =================================================
# ASK + VERIFY REGION
# =================================================

while true; do

  echo
  echo "${CYAN}${BOLD}Available App Engine Regions:${RESET}"
  echo "$VALID_REGIONS" | tr ' ' '\n' | column
  echo

  read -p "Enter region (default: us-central): " REGION

  REGION=${REGION:-us-central}

  if echo "$VALID_REGIONS" | grep -qx "$REGION"; then
    echo
    echo "${GREEN}✓ Valid region selected: $REGION${RESET}"
    echo
    break
  else
    echo
    echo "${RED}❌ Invalid region: $REGION${RESET}"
    echo "${YELLOW}Please choose from the list above.${RESET}"
    echo
  fi

done

# =================================================
# CONFIG
# =================================================

APP_DIR="python-docs-samples/appengine/standard_python3/hello_world"
VENV="myenv"

# =================================================
# HEADER
# =================================================

clear
echo
echo "${CYAN}${BOLD}============================================${RESET}"
echo "${CYAN}${BOLD}   APP ENGINE PYTHON LAB (VERIFIED MODE)   ${RESET}"
echo "${CYAN}${BOLD}============================================${RESET}"
echo
echo "${BLUE}Project: $PROJECT_ID${RESET}"
echo "${BLUE}Region:  $REGION${RESET}"
echo

# =================================================
# ENABLE API
# =================================================

echo "${YELLOW}▶ Enabling App Engine API...${RESET}"

gcloud services enable appengine.googleapis.com --quiet

echo "${GREEN}✓ API Enabled${RESET}"

# =================================================
# CLONE REPO
# =================================================

echo "${YELLOW}▶ Downloading sample app...${RESET}"

rm -rf python-docs-samples

git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git

cd $APP_DIR

echo "${GREEN}✓ Repository cloned${RESET}"

# =================================================
# INSTALL VENV
# =================================================

echo "${YELLOW}▶ Setting up Python environment...${RESET}"

sudo apt update -y >/dev/null
sudo apt install -y python3-venv >/dev/null

python3 -m venv $VENV
source $VENV/bin/activate

pip install --upgrade pip >/dev/null

echo "${GREEN}✓ Virtual environment ready${RESET}"

# =================================================
# TEST APP
# =================================================

echo "${YELLOW}▶ Testing app locally...${RESET}"

pkill -f flask >/dev/null 2>&1 || true

flask --app main run >/dev/null 2>&1 &

PID=$!
sleep 5

curl -4 -s http://127.0.0.1:5000 >/dev/null

kill $PID

echo "${GREEN}✓ Local test passed${RESET}"

# =================================================
# MODIFY CODE
# =================================================

echo "${YELLOW}▶ Updating application message...${RESET}"

sed -i 's/Hello World!/Hello, Cruel World!/g' main.py

echo "${GREEN}✓ Code updated${RESET}"

# =================================================
# RETEST
# =================================================

echo "${YELLOW}▶ Retesting app...${RESET}"

pkill -f flask >/dev/null 2>&1 || true

flask --app main run >/dev/null 2>&1 &

PID=$!
sleep 5

curl -4 -s http://127.0.0.1:5000 >/dev/null

kill $PID

echo "${GREEN}✓ Retest successful${RESET}"

# =================================================
# CREATE APP
# =================================================

echo "${YELLOW}▶ Creating App Engine app (if needed)...${RESET}"

gcloud app create --region="$REGION" --quiet || true

# =================================================
# DEPLOY
# =================================================

echo "${YELLOW}▶ Deploying application...${RESET}"

gcloud app deploy --quiet || {
  echo "${YELLOW}Retrying deployment...${RESET}"
  sleep 20
  gcloud app deploy --quiet
}

echo "${GREEN}✓ Deployment complete${RESET}"

# =================================================
# GET URL
# =================================================

URL=$(gcloud app browse --no-launch-browser 2>/dev/null | grep https || true)

# =================================================
# DONE
# =================================================

echo
echo "${GREEN}${BOLD}============================================${RESET}"
echo "${GREEN}${BOLD}   DEPLOYMENT SUCCESSFUL!                  ${RESET}"
echo "${GREEN}${BOLD}============================================${RESET}"
echo
echo "${BLUE}Application URL:${RESET}"
echo "${CYAN}$URL${RESET}"
echo
