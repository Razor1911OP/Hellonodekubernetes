#!/bin/bash

set -e

# -------------------------------
# FUNCTION: Y/N CHECK
# -------------------------------
ask_yn() {
  while true; do
    read -p "$1 (y/n): " ans
    case "$ans" in
      y) return 0 ;;
      n) echo "❌ Fix issue before continuing"; exit 1 ;;
      *) echo "⚠️ Enter only y or n" ;;
    esac
  done
}

echo "========== CONFIG =========="

# Get project automatically
PROJECT_ID=$(gcloud config get-value project)
echo "Using PROJECT_ID: $PROJECT_ID"

# Ask region (REQUIRED)
read -p "Enter REGION (e.g., us-central1): " REGION

echo "================================"

# -------------------------------
# SET REGION
# -------------------------------
gcloud config set dataproc/region "$REGION"

# -------------------------------
# RESET DATAPROC API (IDEMPOTENT)
# -------------------------------
gcloud services disable dataproc.googleapis.com --force || true
gcloud services enable dataproc.googleapis.com

# -------------------------------
# GET PROJECT NUMBER
# -------------------------------
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID \
  --format='value(projectNumber)')

# -------------------------------
# IAM FIX (CRITICAL)
# -------------------------------
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --role=roles/storage.admin >/dev/null

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --role=roles/dataproc.worker >/dev/null

echo "✅ IAM fixed"

# -------------------------------
# ENABLE PRIVATE ACCESS
# -------------------------------
gcloud compute networks subnets update default \
  --region="$REGION" \
  --enable-private-ip-google-access || true

# -------------------------------
# CREATE CLUSTER (SAFE RE-RUN)
# -------------------------------
if ! gcloud dataproc clusters describe example-cluster >/dev/null 2>&1; then
  gcloud dataproc clusters create example-cluster \
    --region="$REGION" \
    --worker-boot-disk-size=500 \
    --worker-machine-type=e2-standard-4 \
    --master-machine-type=e2-standard-4 \
    --quiet
else
  echo "⚠️ Cluster already exists, skipping creation"
fi

echo "✅ Cluster ready"

ask_yn "Did Task 1 (cluster creation) pass?"

# -------------------------------
# SUBMIT SPARK JOB
# -------------------------------
gcloud dataproc jobs submit spark \
  --cluster=example-cluster \
  --region="$REGION" \
  --class=org.apache.spark.examples.SparkPi \
  --jars=file:///usr/lib/spark/examples/jars/spark-examples.jar \
  -- 1000

echo "✅ Spark job completed"

ask_yn "Did Task 2 (job submission) pass?"

# -------------------------------
# UPDATE CLUSTER (SCALE UP)
# -------------------------------
gcloud dataproc clusters update example-cluster \
  --region="$REGION" \
  --num-workers=4

echo "✅ Scaled to 4 workers"

# -------------------------------
# UPDATE CLUSTER (SCALE DOWN)
# -------------------------------
gcloud dataproc clusters update example-cluster \
  --region="$REGION" \
  --num-workers=2

echo "✅ Scaled back to 2 workers"

ask_yn "Did Task 3 (cluster update) pass?"

echo ""
echo "🎉 ALL TASKS COMPLETED SUCCESSFULLY"
