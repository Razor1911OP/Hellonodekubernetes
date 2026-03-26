#!/bin/bash

set -e

echo "========== CONFIG =========="

PROJECT_ID=$(gcloud config get-value project)
echo "Using PROJECT_ID: $PROJECT_ID"

read -p "Enter REGION (e.g., us-central1): " REGION

echo "================================"

# -------------------------------
# SET REGION
# -------------------------------
gcloud config set compute/region "$REGION"

# -------------------------------
# ENABLE DATAPLEX API
# -------------------------------
gcloud services enable dataplex.googleapis.com

# -------------------------------
# CREATE LAKE (IDEMPOTENT)
# -------------------------------
if ! gcloud dataplex lakes describe ecommerce --location="$REGION" >/dev/null 2>&1; then
  gcloud dataplex lakes create ecommerce \
    --location="$REGION" \
    --display-name="Ecommerce" \
    --description="Ecommerce Domain"
else
  echo "⚠️ Lake already exists"
fi

echo "✅ Lake ready"

# -------------------------------
# CREATE ZONE
# -------------------------------
if ! gcloud dataplex zones describe orders-curated-zone \
  --location="$REGION" --lake=ecommerce >/dev/null 2>&1; then

  gcloud dataplex zones create orders-curated-zone \
    --location="$REGION" \
    --lake=ecommerce \
    --display-name="Orders Curated Zone" \
    --resource-location-type=SINGLE_REGION \
    --type=CURATED \
    --discovery-enabled \
    --discovery-schedule="0 * * * *"
else
  echo "⚠️ Zone already exists"
fi

echo "✅ Zone ready"

# -------------------------------
# CREATE BIGQUERY DATASET
# -------------------------------
bq --location="$REGION" mk --dataset --if_not_exists orders

echo "✅ Dataset ready"

# -------------------------------
# ATTACH ASSET
# -------------------------------
if ! gcloud dataplex assets describe orders-curated-dataset \
  --location="$REGION" --zone=orders-curated-zone --lake=ecommerce >/dev/null 2>&1; then

  gcloud dataplex assets create orders-curated-dataset \
    --location="$REGION" \
    --lake=ecommerce \
    --zone=orders-curated-zone \
    --display-name="Orders Curated Dataset" \
    --resource-type=BIGQUERY_DATASET \
    --resource-name="projects/$PROJECT_ID/datasets/orders" \
    --discovery-enabled
else
  echo "⚠️ Asset already exists"
fi

echo "✅ Asset attached"

# -------------------------------
# DELETE ASSET (AUTO CONFIRM)
# -------------------------------
gcloud dataplex assets delete orders-curated-dataset \
  --location="$REGION" \
  --zone=orders-curated-zone \
  --lake=ecommerce \
  --quiet || true

echo "✅ Asset deleted"

# -------------------------------
# DELETE ZONE
# -------------------------------
gcloud dataplex zones delete orders-curated-zone \
  --location="$REGION" \
  --lake=ecommerce \
  --quiet || true

echo "✅ Zone deleted"

# -------------------------------
# DELETE LAKE
# -------------------------------
gcloud dataplex lakes delete ecommerce \
  --location="$REGION" \
  --quiet || true

echo "✅ Lake deleted"

echo ""
echo "🎉 LAB COMPLETED — Click all 'Check my progress'"
