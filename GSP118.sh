#!/bin/bash
set -e

echo "=============================================="
echo " GSP118 - Progress Validation Automation Only"
echo "=============================================="

ask_continue() {
  read -p "$1 (yes/no): " choice
  case "$choice" in
    yes|YES|y|Y ) ;;
    * )
      echo "❌ Stopped by user."
      exit 1
      ;;
  esac
}

# -------------------------
# 1️⃣ Validate gcloud auth
# -------------------------
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")

if [ -z "$ACCOUNT" ]; then
  echo "❌ No active account."
  echo "Login reference: https://cloud.google.com/sdk/docs/authorizing"
  exit 1
fi

echo "✅ Active account: $ACCOUNT"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
  echo "❌ No project configured."
  exit 1
fi

echo "✅ Project: $PROJECT_ID"
ask_continue "Proceed with this project?"

# -------------------------
# 2️⃣ Define Required Variables
# -------------------------
read -p "Enter region1 (e.g. us-central1): " region1
read -p "Enter region2 (e.g. us-east1): " region2
read -p "Enter zone1 (e.g. us-central1-a): " zone_1
read -p "Enter zone2 (e.g. us-east1-b): " zone_2

export vpc_name=webappnet

# REQUIRED BY LAB
echo "Setting compute region to ${region1}"
gcloud config set compute/region ${region1}

ask_continue "Continue with these values?"

# ==================================================
# TASK 2 — Creating the network infrastructure
# (Check My Progress #1)
# ==================================================

echo "🚀 Creating VPC..."

gcloud compute networks create ${vpc_name} \
  --description "VPC network to deploy Active Directory" \
  --subnet-mode custom || echo "VPC may already exist."

echo "🚀 Creating subnets..."

gcloud compute networks subnets create private-ad-zone-1 \
  --network ${vpc_name} \
  --range 10.1.0.0/24 \
  --region ${region1} || echo "Subnet1 may already exist."

gcloud compute networks subnets create private-ad-zone-2 \
  --network ${vpc_name} \
  --range 10.2.0.0/24 \
  --region ${region2} || echo "Subnet2 may already exist."

echo "🚀 Creating firewall rules..."

gcloud compute firewall-rules create allow-internal-ports-private-ad \
  --network ${vpc_name} \
  --allow tcp:1-65535,udp:1-65535,icmp \
  --source-ranges 10.1.0.0/24,10.2.0.0/24 || echo "Internal rule exists."

gcloud compute firewall-rules create allow-rdp \
  --network ${vpc_name} \
  --allow tcp:3389 \
  --source-ranges 0.0.0.0/0 || echo "RDP rule exists."

echo "✅ Network infrastructure completed."
echo "👉 You may now click 'Check My Progress' for Task 2."

ask_continue "Continue to create Domain Controller 1?"

# ==================================================
# TASK 3 — Create first domain controller
# (Check My Progress #2)
# ==================================================

gcloud compute instances create ad-dc1 \
  --machine-type e2-standard-2 \
  --boot-disk-type pd-ssd \
  --boot-disk-size 50GB \
  --image-family windows-2016 \
  --image-project windows-cloud \
  --network ${vpc_name} \
  --zone ${zone_1} \
  --subnet private-ad-zone-1 \
  --private-network-ip=10.1.0.100

echo "✅ ad-dc1 created."
echo "👉 Click 'Check My Progress' for Task 3."

ask_continue "Continue to create Domain Controller 2?"

# ==================================================
# TASK 5 — Create second domain controller
# (Check My Progress #3)
# ==================================================

gcloud compute instances create ad-dc2 \
  --machine-type e2-standard-2 \
  --boot-disk-type pd-ssd \
  --boot-disk-size 50GB \
  --image-family windows-2016 \
  --image-project windows-cloud \
  --network ${vpc_name} \
  --zone ${zone_2} \
  --subnet private-ad-zone-2 \
  --private-network-ip=10.2.0.100

echo "✅ ad-dc2 created."
echo "👉 Click 'Check My Progress' for Task 5."

echo "=============================================="
echo " 🎉 ALL PROGRESS-VALIDATED TASKS COMPLETE"
echo "=============================================="
