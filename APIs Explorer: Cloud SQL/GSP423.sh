#!/bin/bash
set -euo pipefail

# ================= COLORS =================
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ================= CONFIG =================
PROJECT_ID=$(gcloud config get-value project)
INSTANCE="my-instance"
DB="mysql-db"
TABLE="info"
REGION="us-central1"
API="https://sqladmin.googleapis.com/sql/v1beta4"
BUCKET="${PROJECT_ID}-sql-$(date +%s)"
CSV="employee_info.csv"

# ================= HEADER =================
clear
echo
echo "${CYAN}${BOLD}============================================${RESET}"
echo "${CYAN}${BOLD}   DR. ABHISHEK CLOUD SQL FAST LAB SCRIPT    ${RESET}"
echo "${CYAN}${BOLD}============================================${RESET}"
echo

echo "${BLUE}Project: $PROJECT_ID${RESET}"
echo "${BLUE}Region:  $REGION${RESET}"
echo

# ================= ENABLE API =================
echo "${YELLOW}▶ Enabling SQL API...${RESET}"
gcloud services enable sqladmin.googleapis.com --quiet

# ================= TOKEN =================
TOKEN=$(gcloud auth print-access-token)

# ================= CREATE INSTANCE =================
echo "${YELLOW}▶ Creating instance...${RESET}"

curl -s -X POST \
 -H "Authorization: Bearer $TOKEN" \
 -H "Content-Type: application/json" \
 "${API}/projects/$PROJECT_ID/instances" \
 -d "{
  \"name\":\"$INSTANCE\",
  \"region\":\"$REGION\",
  \"databaseVersion\":\"MYSQL_5_7\",
  \"settings\":{\"tier\":\"db-n1-standard-1\"}
 }" >/dev/null

echo "${BLUE}Waiting for instance...${RESET}"

until gcloud sql instances describe $INSTANCE &>/dev/null
do
 sleep 8
done

echo "${GREEN}✓ Instance ready${RESET}"

# ================= CREATE DB =================
echo "${YELLOW}▶ Creating database...${RESET}"

curl -s -X POST \
 -H "Authorization: Bearer $TOKEN" \
 -H "Content-Type: application/json" \
 "${API}/projects/$PROJECT_ID/instances/$INSTANCE/databases" \
 -d "{\"name\":\"$DB\"}" >/dev/null

echo "${GREEN}✓ Database created${RESET}"

# ================= CREATE TABLE =================
echo "${YELLOW}▶ Creating table...${RESET}"

gcloud sql connect $INSTANCE --user=root <<EOF
USE $DB;
CREATE TABLE info(
 name VARCHAR(255),
 age INT,
 occupation VARCHAR(255)
);
EXIT
EOF

# ================= CREATE CSV =================
echo "${YELLOW}▶ Creating CSV...${RESET}"

cat > $CSV <<EOF
"Sean",23,"Content Creator"
"Emily",34,"Cloud Engineer"
"Rocky",40,"Event coordinator"
"Kate",28,"Data Analyst"
"Juan",51,"Program Manager"
"Jennifer",32,"Web Developer"
EOF

# ================= BUCKET =================
echo "${YELLOW}▶ Creating bucket...${RESET}"

gsutil mb -l $REGION gs://$BUCKET >/dev/null

gsutil cp $CSV gs://$BUCKET/ >/dev/null

# ================= PERMISSIONS =================
echo "${YELLOW}▶ Granting permissions...${RESET}"

SA=$(gcloud sql instances describe $INSTANCE \
 --format="value(serviceAccountEmailAddress)")

gsutil iam ch \
 serviceAccount:$SA:roles/storage.admin \
 gs://$BUCKET >/dev/null

# ================= IMPORT =================
echo "${YELLOW}▶ Importing CSV...${RESET}"

curl -s -X POST \
 -H "Authorization: Bearer $TOKEN" \
 -H "Content-Type: application/json" \
 "${API}/projects/$PROJECT_ID/instances/$INSTANCE/import" \
 -d "{
  \"importContext\":{
   \"database\":\"$DB\",
   \"uri\":\"gs://$BUCKET/$CSV\",
   \"fileType\":\"CSV\",
   \"csvImportOptions\":{\"table\":\"$TABLE\"}
  }
 }" >/dev/null

sleep 30

# ================= VERIFY =================
echo "${YELLOW}▶ Verifying data...${RESET}"

gcloud sql connect $INSTANCE --user=root <<EOF
USE $DB;
SELECT * FROM info;
EXIT
EOF

# ================= DELETE DB =================
echo "${YELLOW}▶ Deleting database...${RESET}"

curl -s -X DELETE \
 -H "Authorization: Bearer $TOKEN" \
 "${API}/projects/$PROJECT_ID/instances/$INSTANCE/databases/$DB" \
 >/dev/null

# ================= CLEAN =================
gsutil rm -r gs://$BUCKET >/dev/null
rm -f $CSV

# ================= DONE =================
echo
echo "${GREEN}${BOLD}============================================${RESET}"
echo "${GREEN}${BOLD}   ALL TASKS COMPLETED SUCCESSFULLY!        ${RESET}"
echo "${GREEN}${BOLD}============================================${RESET}"
echo
