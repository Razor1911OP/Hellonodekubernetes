#!/bin/bash

set -e

echo "==============================="
echo "GSP1008 - GEO Routing Policy Lab"
echo "==============================="

PROJECT_ID=$(gcloud config get-value project)
echo "Project: $PROJECT_ID"

echo ""
echo "⚠️  Enter zones EXACTLY as provided in lab instructions."
echo ""

read -p "Enter ZONE1 (REGION1 zone): " ZONE1
read -p "Enter ZONE2 (REGION2 zone): " ZONE2
read -p "Enter ZONE3 (REGION3 zone): " ZONE3

REGION1=$(echo $ZONE1 | sed 's/-[a-z]$//')
REGION2=$(echo $ZONE2 | sed 's/-[a-z]$//')
REGION3=$(echo $ZONE3 | sed 's/-[a-z]$//')

echo ""
echo "Using:"
echo "ZONE1=$ZONE1"
echo "ZONE2=$ZONE2"
echo "ZONE3=$ZONE3"
echo ""

# ------------------------------------------------
# TASK 1 — ENABLE APIs
# ------------------------------------------------

echo "Enabling APIs..."

gcloud services enable compute.googleapis.com dns.googleapis.com

echo "✅ APIs enabled"
echo "👉 Check My Progress: Enable APIs"

# ------------------------------------------------
# TASK 2 — FIREWALL RULES
# ------------------------------------------------

echo "Creating firewall rules..."

if ! gcloud compute firewall-rules describe fw-default-iapproxy &>/dev/null; then
  gcloud compute firewall-rules create fw-default-iapproxy \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:22,icmp \
  --source-ranges=35.235.240.0/20
fi

if ! gcloud compute firewall-rules describe allow-http-traffic &>/dev/null; then
  gcloud compute firewall-rules create allow-http-traffic \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=http-server
fi

echo "✅ Firewall configured"
echo "👉 Check My Progress: Configure the Firewall"

# ------------------------------------------------
# TASK 3 — CLIENT VMs
# ------------------------------------------------

echo "Creating client VMs..."

gcloud compute instances create us-client-vm \
--zone=$ZONE1 --machine-type=e2-micro --quiet || true

gcloud compute instances create europe-client-vm \
--zone=$ZONE2 --machine-type=e2-micro --quiet || true

gcloud compute instances create asia-client-vm \
--zone=$ZONE3 --machine-type=e2-micro --quiet || true

echo "✅ Client VMs created"
echo "👉 Check My Progress: Launch client VMs"

# ------------------------------------------------
# TASK 4 — SERVER VMs
# ------------------------------------------------

echo "Creating server VMs..."

gcloud compute instances create us-web-vm \
--zone=$ZONE1 \
--machine-type=e2-micro \
--network=default \
--subnet=default \
--tags=http-server \
--metadata=startup-script="#!/bin/bash
apt-get update
apt-get install apache2 -y
echo 'Page served from: $REGION1' > /var/www/html/index.html
systemctl restart apache2" \
--quiet || true

gcloud compute instances create europe-web-vm \
--zone=$ZONE2 \
--machine-type=e2-micro \
--network=default \
--subnet=default \
--tags=http-server \
--metadata=startup-script="#!/bin/bash
apt-get update
apt-get install apache2 -y
echo 'Page served from: $REGION2' > /var/www/html/index.html
systemctl restart apache2" \
--quiet || true

echo "✅ Server VMs created"
echo "👉 Check My Progress: Launch Server VMs"

# ------------------------------------------------
# TASK 5 — STORE INTERNAL IPS
# ------------------------------------------------

echo "Saving internal IPs..."

US_WEB_IP=$(gcloud compute instances describe us-web-vm \
--zone=$ZONE1 \
--format="value(networkInterfaces.networkIP)")

EUROPE_WEB_IP=$(gcloud compute instances describe europe-web-vm \
--zone=$ZONE2 \
--format="value(networkInterfaces.networkIP)")

echo "US_WEB_IP=$US_WEB_IP"
echo "EUROPE_WEB_IP=$EUROPE_WEB_IP"

# ------------------------------------------------
# TASK 6 — PRIVATE DNS ZONE
# ------------------------------------------------

echo "Creating private DNS zone..."

if ! gcloud dns managed-zones describe example &>/dev/null; then
  gcloud dns managed-zones create example \
  --description="test zone" \
  --dns-name=example.com \
  --networks=default \
  --visibility=private
fi

echo "✅ Private zone created"

# ------------------------------------------------
# TASK 7 — GEO ROUTING POLICY
# ------------------------------------------------

echo "Creating GEO routing policy..."

if ! gcloud dns record-sets describe geo.example.com \
--type=A --zone=example &>/dev/null; then

  gcloud dns record-sets create geo.example.com \
  --ttl=5 \
  --type=A \
  --zone=example \
  --routing-policy-type=GEO \
  --routing-policy-data="$REGION1=$US_WEB_IP;$REGION2=$EUROPE_WEB_IP"
fi

echo "✅ GEO routing policy created"
echo "👉 Check My Progress: Create the Private Zone"

echo ""
echo "=================================="
echo "✅ ALL CHECKPOINTS COMPLETED"
echo "=================================="
echo ""
echo "Now perform SSH testing manually if required by lab."
echo ""
echo "To delete everything after finishing lab:"
echo ""
echo "gcloud compute instances delete -q us-client-vm --zone=$ZONE1"
echo "gcloud compute instances delete -q europe-client-vm --zone=$ZONE2"
echo "gcloud compute instances delete -q asia-client-vm --zone=$ZONE3"
echo "gcloud compute instances delete -q us-web-vm --zone=$ZONE1"
echo "gcloud compute instances delete -q europe-web-vm --zone=$ZONE2"
echo "gcloud compute firewall-rules delete -q allow-http-traffic"
echo "gcloud compute firewall-rules delete -q fw-default-iapproxy"
echo "gcloud dns record-sets delete geo.example.com --type=A --zone=example"
echo "gcloud dns managed-zones delete example"
