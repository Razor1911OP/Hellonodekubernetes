#!/bin/bash
set -e

### COLORS ###
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

### RETRY ###
retry() {
  local n=1
  local max=5
  local delay=10

  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        echo -e "${YELLOW}Retry $n/$max...${NC}"
        sleep $delay
      else
        echo -e "${RED}Failed after $max attempts${NC}"
        exit 1
      fi
    }
  done
}

################################
# PROJECT CHECK
################################

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}No active project. Run: gcloud config set project PROJECT_ID${NC}"
  exit 1
fi

echo -e "${GREEN}Project: $PROJECT_ID${NC}"

################################
# ENABLE API
################################

echo -e "${BLUE}Checking Compute API...${NC}"

if ! gcloud services list --enabled | grep -q compute.googleapis.com; then
  retry gcloud services enable compute.googleapis.com
fi

################################
# FIREWALL RULE
################################

RULE_NAME="iperf-testing"

if gcloud compute firewall-rules describe $RULE_NAME &>/dev/null; then
  echo -e "${GREEN}Firewall rule '$RULE_NAME' already exists. Skipping.${NC}"
else
  echo -e "${BLUE}Creating firewall rule '$RULE_NAME'...${NC}"

  retry gcloud compute firewall-rules create $RULE_NAME \
    --network default \
    --direction INGRESS \
    --priority 1000 \
    --allow tcp:5001,udp:5001 \
    --source-ranges 0.0.0.0/0
fi

################################
# VERIFY
################################

echo
echo -e "${BLUE}Verifying firewall rule...${NC}"

gcloud compute firewall-rules describe $RULE_NAME \
  --format="table(name,allowed,sourceRanges)"

################################
# DONE
################################

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}GSP045 COMPLETED (Scored Task Done)${NC}"
echo -e "${GREEN}======================================${NC}"
echo

echo "Now click:"
echo "👉 Check My Progress → Create the firewall rule"

echo
echo "Lab Console:"
echo "https://www.cloudskillsboost.google/catalog_lab/"

echo
