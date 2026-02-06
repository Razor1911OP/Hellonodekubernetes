#!/bin/bash
set -euo pipefail

# =================================================
# FORCE IPV4 EVERYWHERE (CRITICAL)
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

echo "✓ IPv4 enforced globally"

# =================================================
# COLORS
# =================================================

GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# =================================================
# CONFIG
# =================================================

PROJECT_ID=$(gcloud config get-value project)
REGION="us-central"

APP_DIR="python-docs-samples/appengine/standard_python3/hello_world"
VENV="myenv"

# =================================================
# HEADER
# =================================================

clear
echo
echo "${CYAN}${BOLD}============================================${RESET}"
echo "${CYAN}${BOLD}   APP ENGINE PYTHON FAST LAB SCRIPT        ${RESET}"
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

echo "${GREEN}✓ Repo cloned${RESET}"

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
# TEST APP (BACKGROUND)
# =================================================

echo "${YELLOW}▶ Testing app locally...${RESET}"

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
# RE-TEST
# =================================================

echo "${YELLOW}▶ Retesting app...${RESET}"

flask --app main run >/dev/null 2>&1 &

PID=$!
sleep 5

curl -4 -s http://127.0.0.1:5000 >/dev/null

kill $PID

echo "${GREEN}✓ Retest successful${RESET}"

# =================================================
# DEPLOY APP
# =================================================

echo "${YELLOW}▶ Deploying to App Engine...${RESET}"

# Create app if not exists
gcloud app create --region=$REGION --quiet || true

# Deploy without prompt
gcloud app deploy --quiet

echo "${GREEN}✓ Deployment complete${RESET}"

# =================================================
# BROWSE APP
# =================================================

echo "${YELLOW}▶ Fetching app URL...${RESET}"

URL=$(gcloud app browse --no-launch-browser 2>/dev/null | grep https)

# =================================================
# DONE
# =================================================

echo
echo "${GREEN}${BOLD}============================================${RESET}"
echo "${GREEN}${BOLD}   APP ENGINE DEPLOYMENT SUCCESSFUL!       ${RESET}"
echo "${GREEN}${BOLD}============================================${RESET}"
echo
echo "${BLUE}Application URL:${RESET}"
echo "${CYAN}$URL${RESET}"
echo
