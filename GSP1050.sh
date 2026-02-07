#!/bin/bash
set -e

#################################
# CONFIG
#################################

INSTANCE="banking-ops-instance"
DB="banking-ops-db"

WORKDIR="$HOME/gsp1050"
REQ_URL="https://storage.googleapis.com/cloud-training/OCBL373/requirements.txt"
SNIP_URL="https://storage.googleapis.com/cloud-training/OCBL373/snippets.py"

#################################
# COLORS
#################################

GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

#################################
# FUNCTIONS
#################################

log() {
  echo -e "${BLUE}▶ $1${NC}"
}

success() {
  echo -e "${GREEN}✔ $1${NC}"
}

warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

retry() {
  local n=1
  local max=5
  local delay=5

  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        warn "Retry $n/$max failed. Retrying..."
        ((n++))
        sleep $delay
      else
        echo -e "${RED}Command failed after $max tries.${NC}"
        exit 1
      fi
    }
  done
}

#################################
# PRECHECK
#################################

log "Checking authentication..."
gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q . \
  || { echo "Not logged in"; exit 1; }

PROJECT_ID=$(gcloud config get-value project)

log "Project: $PROJECT_ID"
success "Auth OK"

#################################
# TASK 1: LOAD TABLE DATA
#################################

log "Loading Portfolio, Category, Product data..."

gcloud spanner databases execute-sql "$DB" \
--instance="$INSTANCE" <<EOF

INSERT INTO Portfolio VALUES
(1,"Banking","Bnkg","All Banking Business"),
(2,"Asset Growth","AsstGrwth","All Asset Focused Products"),
(3,"Insurance","Ins","All Insurance Focused Products");

INSERT INTO Category VALUES
(1,1,"Cash"),
(2,2,"Investments - Short Return"),
(3,2,"Annuities"),
(4,3,"Life Insurance");

INSERT INTO Product VALUES
(1,1,1,"Checking Account","ChkAcct","Banking LOB"),
(2,2,2,"Mutual Fund Consumer Goods","MFundCG","Investment LOB"),
(3,3,2,"Annuity Early Retirement","AnnuFixed","Investment LOB"),
(4,4,3,"Term Life Insurance","TermLife","Insurance LOB"),
(5,1,1,"Savings Account","SavAcct","Banking LOB"),
(6,1,1,"Personal Loan","PersLn","Banking LOB"),
(7,1,1,"Auto Loan","AutLn","Banking LOB"),
(8,4,3,"Permanent Life Insurance","PermLife","Insurance LOB"),
(9,2,2,"US Savings Bonds","USSavBond","Investment LOB");

EOF || warn "Data may already exist (skipped)"

success "Task 1 complete"

#################################
# TASK 2: PYTHON SETUP
#################################

log "Setting up Python helper..."

mkdir -p "$WORKDIR"
cd "$WORKDIR"

retry wget -q "$REQ_URL" -O requirements.txt
retry wget -q "$SNIP_URL" -O snippets.py

pip install --quiet -r requirements.txt
pip install --quiet setuptools

success "Python ready"

log "Loading Campaigns data..."

retry python snippets.py "$INSTANCE" \
  --database-id "$DB" insert_data

success "Task 2 complete"

#################################
# TASK 3: QUERY CAMPAIGNS
#################################

log "Querying Campaigns..."

python snippets.py "$INSTANCE" \
  --database-id "$DB" query_data

success "Query OK"

#################################
# TASK 4: ADD COLUMN
#################################

log "Adding MarketingBudget column..."

python snippets.py "$INSTANCE" \
  --database-id "$DB" add_column || warn "Column may exist"

success "Column ready"

log "Updating new column..."

python snippets.py "$INSTANCE" \
  --database-id "$DB" update_data

python snippets.py "$INSTANCE" \
  --database-id "$DB" query_data_with_new_column

success "Task 4 complete"

#################################
# TASK 5: ADD INDEX
#################################

log "Adding secondary index..."

python snippets.py "$INSTANCE" \
  --database-id "$DB" add_index || warn "Index may exist"

success "Index created"

log "Reading with index..."

python snippets.py "$INSTANCE" \
  --database-id "$DB" read_data_with_index

log "Adding storing index..."

python snippets.py "$INSTANCE" \
  --database-id "$DB" add_storing_index || warn "Index may exist"

python snippets.py "$INSTANCE" \
  --database-id "$DB" read_data_with_storing_index

success "Task 5 complete"

#################################
# FINAL
#################################

echo
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN} GSP1050 - AUTOMATION COMPLETE${NC}"
echo -e "${GREEN}==========================================${NC}"
echo

echo -e "${BLUE}✅ SCORING TASKS DONE:${NC}"
echo -e "${GREEN}1) Load Portfolio/Category/Product${NC}"
echo -e "${GREEN}2) Load Campaigns Table${NC}"
echo -e "${GREEN}3) Add MarketingBudget Column${NC}"
echo -e "${GREEN}4) Add Secondary Index${NC}"
echo

echo -e "${YELLOW}👉 NOW CLICK:${NC}"
echo -e "${YELLOW}Check My Progress for ALL 4 Tasks${NC}"
echo

echo -e "${BLUE}Remaining Manual Task:${NC}"
echo "→ Task 6 (Query Plans) is informational only (no score)"

echo
echo "Lab Page:"
echo "https://www.cloudskillsboost.google/catalog_lab/"
echo
