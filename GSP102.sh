#!/bin/bash
set -Eeuo pipefail

# ===============================
# CONFIG
# ===============================
LOG_FILE="lab.log"
PROGRESS_FILE=".progress"
MAX_RETRIES=3
RETRY_DELAY=5

# ===============================
# FORCE IPV4 (SAFETY)
# ===============================
export GODEBUG=netdns=go
alias curl='curl -4'
alias wget='wget -4'

# ===============================
# LOGGING
# ===============================
exec > >(tee "$LOG_FILE") 2>&1

# ===============================
# COLORS
# ===============================
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RED=$(tput setaf 1)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ===============================
# UTILS
# ===============================

log() {
  echo "${BLUE}[$(date '+%H:%M:%S')]${RESET} $1"
}

success() {
  echo "${GREEN}✓ $1${RESET}"
}

fail() {
  echo "${RED}❌ $1${RESET}"
  exit 1
}

# -------------------------------
# RETRY FUNCTION
# -------------------------------
retry() {
  local n=0
  until [ $n -ge $MAX_RETRIES ]; do
    "$@" && return 0

    n=$((n+1))
    echo "${YELLOW}Retry $n/$MAX_RETRIES: $*${RESET}"
    sleep $RETRY_DELAY
  done

  fail "Command failed: $*"
}

# -------------------------------
# CHECKPOINT
# -------------------------------
checkpoint() {
  echo
  echo "${YELLOW}${BOLD}MANUAL STEP REQUIRED${RESET}"
  echo "$1"
  echo

  while true; do
    read -p "Type Y to continue: " c
    case "$c" in
      [Yy]) break ;;
      *) echo "Waiting..." ;;
    esac
  done
}

# -------------------------------
# PROGRESS
# -------------------------------
save_step() {
  echo "$1" > "$PROGRESS_FILE"
}

load_step() {
  [[ -f "$PROGRESS_FILE" ]] && cat "$PROGRESS_FILE" || echo "START"
}

# -------------------------------
# WAIT UNTIL READY
# -------------------------------
wait_until() {
  local cmd="$1"
  local name="$2"

  log "Waiting for $name..."

  for i in {1..60}; do
    if eval "$cmd" &>/dev/null; then
      success "$name ready"
      return
    fi
    sleep 5
  done

  fail "$name timeout"
}

# -------------------------------
# CLEANUP ON ERROR
# -------------------------------
trap 'echo "${RED}FAILED — Check $LOG_FILE${RESET}"' ERR


# ===============================
# HEADER
# ===============================
clear
echo
echo "${BLUE}${BOLD}=============================================${RESET}"
echo "${BLUE}${BOLD}   CLOUD SPANNER PRO AUTOMATION (GSP102)     ${RESET}"
echo "${BLUE}${BOLD}=============================================${RESET}"
echo


# ===============================
# STEP 0: ENV
# ===============================
STEP=$(load_step)

if [[ "$STEP" == "START" ]]; then

  log "Checking environment..."

  gcloud auth list | grep ACTIVE || fail "Not logged in"

  PROJECT_ID="$(gcloud config get-value project)"
  [[ -z "$PROJECT_ID" ]] && fail "No project set"

  success "Project: $PROJECT_ID"

  save_step "ENV_OK"
fi


# ===============================
# STEP 1: REGION
# ===============================
STEP=$(load_step)

if [[ "$STEP" == "ENV_OK" ]]; then

  read -p "Enter REGION (example: us-central1): " REGION

  gcloud compute regions list \
    --format="value(name)" | grep -qx "$REGION" \
    || fail "Invalid region"

  success "Region OK: $REGION"

  save_step "REGION_OK"
fi


# ===============================
# STEP 2: API
# ===============================
STEP=$(load_step)

if [[ "$STEP" == "REGION_OK" ]]; then

  log "Enabling APIs..."

  retry gcloud services enable spanner.googleapis.com

  wait_until \
   "gcloud services list --enabled | grep spanner" \
   "Spanner API"

  save_step "API_OK"
fi


# ===============================
# STEP 3: RESOURCES
# ===============================
STEP=$(load_step)

INSTANCE="test-instance"
DB="example-db"

if [[ "$STEP" == "API_OK" ]]; then

  log "Creating instance..."

  if ! gcloud spanner instances describe "$INSTANCE" &>/dev/null; then

    retry gcloud spanner instances create "$INSTANCE" \
      --config="regional-$REGION" \
      --nodes=1 \
      --description="Test Instance"

  fi

  wait_until \
   "gcloud spanner instances describe $INSTANCE" \
   "Instance"


  log "Creating database..."

  if ! gcloud spanner databases describe "$DB" \
    --instance="$INSTANCE" &>/dev/null; then

    retry gcloud spanner databases create "$DB" \
      --instance="$INSTANCE"
  fi

  wait_until \
   "gcloud spanner databases describe $DB --instance=$INSTANCE" \
   "Database"

  save_step "RESOURCES_OK"
fi


# ===============================
# STEP 4: SCHEMA
# ===============================
STEP=$(load_step)

if [[ "$STEP" == "RESOURCES_OK" ]]; then

  log "Creating schema..."

  cat > schema.ddl <<EOF
CREATE TABLE Singers (
  SingerId INT64 NOT NULL,
  FirstName STRING(1024),
  LastName STRING(1024),
  SingerInfo BYTES(MAX),
  BirthDate DATE,
) PRIMARY KEY(SingerId);
EOF

  retry gcloud spanner databases ddl update "$DB" \
    --instance="$INSTANCE" \
    --ddl-file=schema.ddl

  save_step "SCHEMA_OK"
fi


# ===============================
# STEP 5: MANUAL DATA
# ===============================
STEP=$(load_step)

if [[ "$STEP" == "SCHEMA_OK" ]]; then

checkpoint "
Open Cloud Console → Spanner

1. Insert 3 rows
2. Edit SingerId=3 (BirthDate)
3. Delete SingerId=2
4. Run SELECT query
"

  save_step "DATA_OK"
fi


# ===============================
# STEP 6: VERIFY
# ===============================
STEP=$(load_step)

if [[ "$STEP" == "DATA_OK" ]]; then

  log "Verifying data..."

  retry gcloud spanner databases execute-sql "$DB" \
    --instance="$INSTANCE" \
    --sql="SELECT * FROM Singers"

  success "Verification successful"

  save_step "DONE"
fi


# ===============================
# FINISH
# ===============================
echo
echo "${GREEN}${BOLD}=============================================${RESET}"
echo "${GREEN}${BOLD}        LAB COMPLETED SUCCESSFULLY 🎉        ${RESET}"
echo "${GREEN}${BOLD}=============================================${RESET}"
echo

echo "➡️ Click: Check My Progress"
echo "📄 Log: $LOG_FILE"
echo
