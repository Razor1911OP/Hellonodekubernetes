#!/bin/bash
set -e

# ==============================
# CONFIG
# ==============================

PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
INSTANCE="my-instance"
DB_NAME="mysql-db"
TABLE="info"
BUCKET="${PROJECT_ID}-sql-bucket-$(date +%s)"
CSV_FILE="employee_info.csv"

API="https://sqladmin.googleapis.com/sql/v1beta4"

echo "Project: $PROJECT_ID"
echo "Bucket:  $BUCKET"

# ==============================
# ENABLE API
# ==============================

echo "Enabling Cloud SQL API..."
gcloud services enable sqladmin.googleapis.com

# ==============================
# AUTH TOKEN
# ==============================

TOKEN=$(gcloud auth print-access-token)

# ==============================
# TASK 1: CREATE INSTANCE
# ==============================

echo "Creating Cloud SQL instance..."

curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "${API}/projects/${PROJECT_ID}/instances" \
  -d "{
    \"name\": \"${INSTANCE}\",
    \"region\": \"${REGION}\",
    \"databaseVersion\": \"MYSQL_5_7\",
    \"settings\": {
      \"tier\": \"db-n1-standard-1\"
    }
  }" > /dev/null


echo "Waiting for instance..."

until gcloud sql instances describe $INSTANCE &>/dev/null
do
  sleep 10
done

# ==============================
# TASK 2: CREATE DATABASE
# ==============================

echo "Creating database..."

curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "${API}/projects/${PROJECT_ID}/instances/${INSTANCE}/databases" \
  -d "{
    \"name\": \"${DB_NAME}\"
  }" > /dev/null

# ==============================
# TASK 3: CREATE TABLE
# ==============================

echo "Creating table..."

gcloud sql connect $INSTANCE --user=root <<EOF
USE ${DB_NAME};
CREATE TABLE info (
  name VARCHAR(255),
  age INT,
  occupation VARCHAR(255)
);
EXIT
EOF

# ==============================
# CREATE CSV
# ==============================

echo "Creating CSV..."

cat > $CSV_FILE <<EOF
"Sean",23,"Content Creator"
"Emily",34,"Cloud Engineer"
"Rocky",40,"Event coordinator"
"Kate",28,"Data Analyst"
"Juan",51,"Program Manager"
"Jennifer",32,"Web Developer"
EOF


# ==============================
# CREATE BUCKET
# ==============================

echo "Creating bucket..."

gsutil mb -l $REGION gs://$BUCKET

# ==============================
# UPLOAD CSV
# ==============================

echo "Uploading CSV..."

gsutil cp $CSV_FILE gs://$BUCKET/

# ==============================
# GRANT PERMISSIONS
# ==============================

echo "Granting Storage Admin..."

SERVICE_ACCOUNT=$(gcloud sql instances describe $INSTANCE \
  --format="value(serviceAccountEmailAddress)")

gsutil iam ch \
  serviceAccount:$SERVICE_ACCOUNT:roles/storage.admin \
  gs://$BUCKET


# ==============================
# TASK 4: IMPORT CSV
# ==============================

echo "Importing CSV..."

curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "${API}/projects/${PROJECT_ID}/instances/${INSTANCE}/import" \
  -d "{
    \"importContext\": {
      \"database\": \"${DB_NAME}\",
      \"uri\": \"gs://${BUCKET}/${CSV_FILE}\",
      \"fileType\": \"CSV\",
      \"csvImportOptions\": {
        \"table\": \"${TABLE}\"
      }
    }
  }" > /dev/null


echo "Waiting for import..."
sleep 40


# ==============================
# TASK 5: VERIFY DATA
# ==============================

echo "Verifying table..."

gcloud sql connect $INSTANCE --user=root <<EOF
USE ${DB_NAME};
SELECT * FROM info;
EXIT
EOF


# ==============================
# TASK 6: DELETE DATABASE
# ==============================

echo "Deleting database..."

curl -s -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  "${API}/projects/${PROJECT_ID}/instances/${INSTANCE}/databases/${DB_NAME}" \
  > /dev/null


# ==============================
# CLEANUP
# ==============================

echo "Cleaning up..."

gsutil rm -r gs://$BUCKET
rm -f $CSV_FILE


# ==============================
# DONE
# ==============================

echo
echo "===================================="
echo " All Tasks Completed Successfully! "
echo "===================================="
echo
