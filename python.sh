#!/bin/bash
set -euo pipefail

# =================================================
# FORCE IPV4
# =================================================

export CURL_OPTIONS="-4"

export BOTO_CONFIG=/tmp/boto.conf

echo "[Boto]
prefer_ipv6 = False
http_socket_timeout = 60" > $BOTO_CONFIG

export CLOUDSDK_PYTHON_SITEPACKAGES=1
export PYTHONHTTPSVERIFY=1
export GODEBUG=netdns=go

echo "✓ IPv4 enforced"

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
# PROJECT
# =================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
  echo "❌ No active project"
  exit 1
fi

# =================================================
# REGION INPUT
# =================================================

echo
echo "Enter App Engine region (default: us-central):"
read -p "> " REGION

REGION=${REGION:-us-central}

echo "Using region: $REGION"
echo

# =================================================
# CONFIG
# =================================================

APP_DIR="python-docs-samples/appengine/standard_python3/hello_world"
VENV="myenv"

# =================================================
# ENABLE API
# =================================================

echo "▶ Enabling API..."
gcloud services enable appengine.googleapis.com --quiet

# =================================================
# CLONE
# =================================================

echo "▶ Cloning repo..."

rm -rf python-docs-samples
git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git

cd "$APP_DIR"

# =================================================
# VENV
# =================================================

echo "▶ Setting up venv..."

sudo apt update -y >/dev/null
sudo apt install -y python3-venv >/dev/null

python3 -m venv "$VENV"
source "$VENV/bin/activate"

pip install --upgrade pip >/dev/null

# =================================================
# TEST
# =================================================

echo "▶ Testing app..."

pkill -f "flask --app main" >/dev/null 2>&1 || true

nohup flask --app main run >/dev/null 2>&1 &

FLASK_PID=$!

sleep 6

curl -4 -s http://127.0.0.1:5000 >/dev/null

kill "$FLASK_PID" >/dev/null 2>&1 || true


# =================================================
# MODIFY
# =================================================

echo "▶ Updating code..."

sed -i 's/Hello World!/Hello, Cruel World!' main.py

# =================================================
# RETEST
# =================================================

echo "▶ Retesting..."

# Kill any old Flask process
pkill -f "flask --app main" >/dev/null 2>&1 || true

# Start Flask in background
nohup flask --app main run >/dev/null 2>&1 &

FLASK_PID=$!

# Wait for startup
sleep 6

# Test endpoint
curl -4 -s http://127.0.0.1:5000 >/dev/null

# Stop Flask
kill "$FLASK_PID" >/dev/null 2>&1 || true


# =================================================
# CREATE APP
# =================================================

echo "▶ Creating app..."

gcloud app create --region="$REGION" --quiet || true

# =================================================
# DEPLOY
# =================================================

echo "▶ Deploying..."

gcloud app deploy --quiet || {
  sleep 20
  gcloud app deploy --quiet
}

# =================================================
# URL
# =================================================

URL=$(gcloud app browse --no-launch-browser 2>/dev/null | grep https || true)

# =============
