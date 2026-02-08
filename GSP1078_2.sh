#!/bin/bash
set -euo pipefail

############################
# CONFIG
############################

LAB="GSP1078"
STATE="$HOME/.gsp1078_state"

REGION="us-central1"
SERVICE="hello-cloudrun"
REPO="cloudrun-progression"

RETRY=5
WAIT=15

############################
# COLORS
############################

G="\e[32m"; R="\e[31m"; B="\e[34m"; Y="\e[33m"; N="\e[0m"

log(){ echo -e "${B}[INFO]${N} $1"; }
ok(){ echo -e "${G}[OK]${N} $1"; }
warn(){ echo -e "${Y}[WARN]${N} $1"; }
die(){ echo -e "${R}[ERROR]${N} $1"; exit 1; }

############################
# UTILS
############################

retry(){
  for i in $(seq 1 $RETRY); do
    "$@" && return 0
    warn "Retry $i/$RETRY..."
    sleep $WAIT
  done
  die "Command failed: $*"
}

############################
# CHECK STATE
############################

[[ -f "$STATE" ]] || die "Run part1 first"

source "$STATE"

[[ "${STEP:-}" == "GITHUB_OK" ]] || die "GitHub auth incomplete"

############################
# PROJECT VARS
############################

PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID \
  --format='value(projectNumber)')

############################
# STEP 1: CLONE + PREP
############################

if [[ "${DONE_CLONE:-}" != "1" ]]; then

log "Preparing repo"

rm -rf training-data-analyst $REPO || true

retry git clone https://github.com/GoogleCloudPlatform/training-data-analyst

mkdir $REPO
cp -r training-data-analyst/self-paced-labs/cloud-run/canary/* $REPO

cd $REPO

git init
git branch -M master

GITHUB_USER=$(gh api user -q ".login")

git remote add gcp https://github.com/$GITHUB_USER/$REPO

git config credential.helper gcloud.sh

git add .
git commit -m "initial commit"

retry git push gcp master

echo "DONE_CLONE=1" >> $STATE
ok "Repo ready"

else
cd $REPO
fi


############################
# STEP 2: DEPLOY PROD (TASK2)
############################

if [[ "${DONE_PROD:-}" != "1" ]]; then

log "Deploying production"

retry gcloud builds submit \
  --tag gcr.io/$PROJECT_ID/$SERVICE

retry gcloud run deploy $SERVICE \
 --image gcr.io/$PROJECT_ID/$SERVICE \
 --region $REGION \
 --platform managed \
 --tag prod \
 -q

echo "DONE_PROD=1" >> $STATE
ok "Production deployed"

fi


############################
# STEP 3: CONNECT GITHUB (TASK3)
############################

if [[ "${DONE_CONN:-}" != "1" ]]; then

log "Creating Cloud Build connection"

retry gcloud builds connections create github cloud-build-conn \
 --project=$PROJECT_ID \
 --region=$REGION || true

gcloud builds connections describe cloud-build-conn \
 --region=$REGION

echo
warn "👉 If authorization URL appears, open it in browser NOW"
read -p "Press ENTER after authorization"

retry gcloud builds repositories create $REPO \
 --remote-uri=https://github.com/$GITHUB_USER/$REPO.git \
 --connection=cloud-build-conn \
 --region=$REGION || true

echo "DONE_CONN=1" >> $STATE
ok "GitHub connected"

fi


############################
# STEP 4: BRANCH TRIGGER (TASK3)
############################

if [[ "${DONE_BRANCH:-}" != "1" ]]; then

log "Creating branch trigger"

retry gcloud builds triggers create github \
 --name=branch \
 --region=$REGION \
 --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-conn/repositories/$REPO \
 --build-config=branch-cloudbuild.yaml \
 --service-account=$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
 --branch-pattern='.*'

echo "DONE_BRANCH=1" >> $STATE
ok "Branch trigger ready"

fi


############################
# STEP 5: DEV DEPLOY (TASK3)
############################

if [[ "${DONE_DEV:-}" != "1" ]]; then

log "Creating dev branch"

git checkout -B new-feature-1

sed -i "s/v1.0/v1.1/" app.py || true

git add .
git commit -m "v1.1"
retry git push gcp new-feature-1

log "Waiting for build..."
sleep 60

echo "DONE_DEV=1" >> $STATE
ok "Dev deployed"

fi


############################
# STEP 6: MASTER TRIGGER (TASK4)
############################

if [[ "${DONE_MASTER:-}" != "1" ]]; then

log "Creating master trigger"

retry gcloud builds triggers create github \
 --name=master \
 --region=$REGION \
 --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-conn/repositories/$REPO \
 --build-config=master-cloudbuild.yaml \
 --service-account=$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
 --branch-pattern='master'

echo "DONE_MASTER=1" >> $STATE
ok "Master trigger ready"

fi


############################
# STEP 7: CANARY (TASK4)
############################

if [[ "${DONE_CANARY:-}" != "1" ]]; then

log "Merging branch"

git checkout master
git merge new-feature-1
retry git push gcp master

log "Waiting for canary..."
sleep 90

echo "DONE_CANARY=1" >> $STATE
ok "Canary live"

fi


############################
# STEP 8: TAG TRIGGER (TASK5)
############################

if [[ "${DONE_TAG:-}" != "1" ]]; then

log "Creating tag trigger"

retry gcloud builds triggers create github \
 --name=tag \
 --region=$REGION \
 --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-conn/repositories/$REPO \
 --build-config=tag-cloudbuild.yaml \
 --service-account=$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
 --tag-pattern='.*'

echo "DONE_TAG=1" >> $STATE
ok "Tag trigger ready"

fi


############################
# STEP 9: RELEASE (TASK5)
############################

if [[ "${DONE_RELEASE:-}" != "1" ]]; then

log "Releasing"

git tag 1.1
retry git push gcp 1.1

log "Waiting for rollout..."
sleep 90

echo "DONE_RELEASE=1" >> $STATE
ok "Release complete"

fi


############################
# CLEANUP
############################

rm -f "$STATE"

############################
# FINISH
############################

echo
echo "======================================"
echo " 🎯 GSP1078 COMPLETED"
echo "======================================"
echo
echo "Click ALL Check My Progress buttons:"
echo "✔ Task 1"
echo "✔ Task 2"
echo "✔ Task 3"
echo "✔ Task 4"
echo "✔ Task 5"
echo
