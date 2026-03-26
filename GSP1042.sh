#!/bin/bash

set -e

echo "========== USER INPUT =========="

read -p "Enter PARTNER PROJECT ID: " PARTNER_PROJECT
read -p "Enter CUSTOMER A PROJECT ID: " CUST_A_PROJECT
read -p "Enter CUSTOMER B PROJECT ID: " CUST_B_PROJECT
read -p "Enter REGION (e.g., us-central1): " REGION

read -p "Enter Customer A Email (optional): " CUST_A_EMAIL
read -p "Enter Customer B Email (optional): " CUST_B_EMAIL

echo "================================"

# -------------------------------
# SET PROJECT
# -------------------------------
gcloud config set project "$PARTNER_PROJECT"

# -------------------------------
# ENABLE API
# -------------------------------
gcloud services enable bigquery.googleapis.com

# -------------------------------
# CREATE DATASET
# -------------------------------
bq --location="$REGION" mk -d --if_not_exists \
  --description "Demo dataset" \
  "${PARTNER_PROJECT}:demo_dataset"

echo "✅ Dataset ready"

# -------------------------------
# CREATE VIEWS
# -------------------------------
bq query --use_legacy_sql=false \
"CREATE OR REPLACE VIEW \`${PARTNER_PROJECT}.demo_dataset.authorized_view_a\` AS
SELECT * FROM \`bigquery-public-data.geo_us_boundaries.zip_codes\`
WHERE state_code='TX' LIMIT 4000;"

bq query --use_legacy_sql=false \
"CREATE OR REPLACE VIEW \`${PARTNER_PROJECT}.demo_dataset.authorized_view_b\` AS
SELECT * FROM \`bigquery-public-data.geo_us_boundaries.zip_codes\`
WHERE state_code='CA' LIMIT 4000;"

echo "✅ Views created"

echo ""
echo "👉 Go click: 'Check my progress' for TASK 1"
read -p "Did TASK 1 pass? (yes/no): " TASK1

if [[ "$TASK1" != "yes" ]]; then
  echo "❌ Fix views before continuing"
  exit 1
fi

# -------------------------------
# MANUAL STEP: AUTHORIZE VIEWS
# -------------------------------
echo ""
echo "======================================"
echo "🚨 MANUAL STEP REQUIRED - TASK 2 🚨"
echo "======================================"
echo "Go to:"
echo "BigQuery → demo_dataset → SHARE → Authorize views"
echo "Add:"
echo "${PARTNER_PROJECT}.demo_dataset.authorized_view_a"
echo "${PARTNER_PROJECT}.demo_dataset.authorized_view_b"
echo "======================================"

read -p "Did you complete TASK 2 and pass checkpoint? (yes/no): " TASK2

if [[ "$TASK2" != "yes" ]]; then
  echo "❌ Complete authorization before continuing"
  exit 1
fi

# -------------------------------
# IAM PERMISSIONS
# -------------------------------
if [[ -n "$CUST_A_EMAIL" ]]; then
  gcloud projects add-iam-policy-binding "$PARTNER_PROJECT" \
    --member="user:$CUST_A_EMAIL" \
    --role="roles/bigquery.dataViewer" >/dev/null
fi

if [[ -n "$CUST_B_EMAIL" ]]; then
  gcloud projects add-iam-policy-binding "$PARTNER_PROJECT" \
    --member="user:$CUST_B_EMAIL" \
    --role="roles/bigquery.dataViewer" >/dev/null
fi

echo "✅ IAM applied"

echo ""
echo "👉 Click 'Check my progress' for TASK 3"
read -p "Did TASK 3 pass? (yes/no): " TASK3

if [[ "$TASK3" != "yes" ]]; then
  echo "❌ Fix IAM before continuing"
  exit 1
fi

# -------------------------------
# CUSTOMER A TABLE
# -------------------------------
bq query --use_legacy_sql=false \
"CREATE OR REPLACE TABLE \`${CUST_A_PROJECT}.customer_a_dataset.customer_a_table\` AS
SELECT geos.zip_code, geos.city, cust.last_name, cust.first_name
FROM \`${CUST_A_PROJECT}.customer_a_dataset.customer_info\` cust
JOIN \`${PARTNER_PROJECT}.demo_dataset.authorized_view_a\` geos
ON geos.zip_code = cust.postal_code;"

echo "✅ Customer A table created"

# -------------------------------
# CUSTOMER B TABLE
# -------------------------------
bq query --use_legacy_sql=false \
"CREATE OR REPLACE TABLE \`${CUST_B_PROJECT}.customer_b_dataset.customer_b_table\` AS
SELECT geos.zip_code, geos.city, cust.last_name, cust.first_name
FROM \`${CUST_B_PROJECT}.customer_b_dataset.customer_info\` cust
JOIN \`${PARTNER_PROJECT}.demo_dataset.authorized_view_b\` geos
ON geos.zip_code = cust.postal_code;"

echo "✅ Customer B table created"

# -------------------------------
# FINAL MANUAL (LOOKER)
# -------------------------------
echo ""
echo "======================================"
echo "🚨 FINAL MANUAL STEPS (TASK 4 & 5) 🚨"
echo "======================================"
echo "1. Login Customer A → Create Looker report"
echo "2. Use customer_a_table → Pie chart (city)"
echo "3. Verify Customer B cannot access"
echo ""
echo "4. Login Customer B → Create Looker report"
echo "5. Use customer_b_table → Pie chart (city)"
echo "6. Verify Customer A cannot access"
echo "======================================"

read -p "Did TASK 4 & 5 pass? (yes/no): " FINAL

if [[ "$FINAL" != "yes" ]]; then
  echo "❌ Complete Looker steps"
  exit 1
fi

echo ""
echo "🎉 ALL TASKS COMPLETED SUCCESSFULLY"
