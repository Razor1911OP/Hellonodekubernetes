#!/bin/bash
set -e

# ================= COLORS =================
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RESET="\033[0m"
BOLD="\033[1m"

# ================= FUNCTIONS =================

retry() {
  local n=0
  until [ $n -ge 5 ]; do
    "$@" && break
    n=$((n+1))
    echo -e "${YELLOW}Retry $n/5...${RESET}"
    sleep 6
  done

  if [ $n -ge 5 ]; then
    echo -e "${RED}Command failed.${RESET}"
    exit 1
  fi
}

# ================= HEADER =================

clear
echo -e "${CYAN}${BOLD}"
echo "=============================================="
echo "   🚀 GSP041 Internal Load Balancer Automation"
echo "=============================================="
echo -e "${RESET}"

# ================= ENV =================

PROJECT_ID=$(gcloud config get-value project)
ACCOUNT=$(gcloud config get-value account)

if [[ -z "$PROJECT_ID" || -z "$ACCOUNT" ]]; then
  echo -e "${RED}❌ gcloud not configured${RESET}"
  exit 1
fi

echo -e "${GREEN}Project: $PROJECT_ID${RESET}"
echo -e "${GREEN}User:    $ACCOUNT${RESET}"

# ================= REGION / ZONE =================

echo
read -p "Enter REGION (e.g. us-central1): " REGION
read -p "Enter ZONE   (e.g. us-central1-a): " ZONE

gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

# ================= VENV (REQUIRED STEP) =================

echo -e "${BLUE}Installing virtualenv...${RESET}"
retry sudo apt-get update
retry sudo apt-get install -y virtualenv

python3 -m venv venv
source venv/bin/activate

# ================= ENABLE API =================

echo -e "${BLUE}Enabling Gemini API...${RESET}"
retry gcloud services enable cloudaicompanion.googleapis.com

# ================= BACKEND SCRIPT =================

echo -e "${BLUE}Creating backend script...${RESET}"

cat > backend.sh <<'EOF'
sudo chmod -R 777 /usr/local/sbin/
sudo cat << PYEOF > /usr/local/sbin/serveprimes.py
import http.server

def is_prime(a): return a!=1 and all(a % i for i in range(2,int(a**0.5)+1))

class myHandler(http.server.BaseHTTPRequestHandler):
  def do_GET(s):
    s.send_response(200)
    s.send_header("Content-type","text/plain")
    s.end_headers()
    s.wfile.write(bytes(str(is_prime(int(s.path[1:]))),'utf-8'))

http.server.HTTPServer(("",80),myHandler).serve_forever()
PYEOF

nohup python3 /usr/local/sbin/serveprimes.py >/dev/null 2>&1 &
EOF

chmod +x backend.sh

# ================= TEMPLATE =================

echo -e "${BLUE}Creating instance template...${RESET}"

retry gcloud compute instance-templates create primecalc \
  --metadata-from-file startup-script=backend.sh \
  --no-address \
  --tags backend \
  --machine-type=e2-medium

# ================= FIREWALL =================

echo -e "${BLUE}Creating firewall rule...${RESET}"

gcloud compute firewall-rules delete http-backend -q 2>/dev/null || true

retry gcloud compute firewall-rules create http-backend \
  --network default \
  --allow tcp:80 \
  --source-ranges 10.0.0.0/8 \
  --target-tags backend

# ================= MIG =================

echo -e "${BLUE}Creating managed instance group...${RESET}"

retry gcloud compute instance-groups managed create backend \
  --size 3 \
  --template primecalc \
  --zone "$ZONE"

# ================= HEALTH CHECK =================

echo -e "${BLUE}Creating health check...${RESET}"

retry gcloud compute health-checks create http ilb-health \
  --request-path /2

# ================= BACKEND SERVICE =================

echo -e "${BLUE}Creating backend service...${RESET}"

retry gcloud compute backend-services create prime-service \
  --load-balancing-scheme internal \
  --region "$REGION" \
  --protocol tcp \
  --health-checks ilb-health

retry gcloud compute backend-services add-backend prime-service \
  --instance-group backend \
  --instance-group-zone "$ZONE" \
  --region "$REGION"

# ================= INTERNAL IP =================

echo -e "${BLUE}Reserving internal IP...${RESET}"

retry gcloud compute addresses create ilb-ip \
  --region "$REGION" \
  --subnet default \
  --addresses 10.128.0.50

ILB_IP=$(gcloud compute addresses describe ilb-ip \
  --region "$REGION" \
  --format="value(address)")

# ================= FORWARDING RULE =================

echo -e "${BLUE}Creating forwarding rule...${RESET}"

retry gcloud compute forwarding-rules create prime-lb \
  --load-balancing-scheme internal \
  --ports 80 \
  --network default \
  --region "$REGION" \
  --address "$ILB_IP" \
  --backend-service prime-service

# ================= FRONTEND SCRIPT =================

echo -e "${BLUE}Creating frontend script...${RESET}"

cat > frontend.sh <<EOF
sudo chmod -R 777 /usr/local/sbin/
sudo cat << PYEOF > /usr/local/sbin/getprimes.py
import urllib.request
from multiprocessing.dummy import Pool as ThreadPool
import http.server

PREFIX="http://${ILB_IP}/"

def get_url(n):
  return urllib.request.urlopen(PREFIX+str(n)).read().decode('utf-8')

class myHandler(http.server.BaseHTTPRequestHandler):
  def do_GET(s):
    s.send_response(200)
    s.send_header("Content-type","text/html")
    s.end_headers()
    i=int(s.path[1:]) if len(s.path)>1 else 1
    s.wfile.write("<html><body><table>".encode())
    pool=ThreadPool(10)
    results=pool.map(get_url,range(i,i+100))
    for x in range(100):
      if not x%10: s.wfile.write("<tr>".encode())
      color="#00ff00" if results[x]=="True" else "#ff0000"
      s.wfile.write(f"<td bgcolor='{color}'>{x+i}</td>".encode())
      if not (x+1)%10: s.wfile.write("</tr>".encode())
    s.wfile.write("</table></body></html>".encode())

http.server.HTTPServer(("",80),myHandler).serve_forever()
PYEOF

nohup python3 /usr/local/sbin/getprimes.py >/dev/null 2>&1 &
EOF

chmod +x frontend.sh

# ================= FRONTEND VM =================

echo -e "${BLUE}Creating frontend VM...${RESET}"

retry gcloud compute instances create frontend \
  --zone "$ZONE" \
  --metadata-from-file startup-script=frontend.sh \
  --tags frontend \
  --machine-type e2-standard-2

# ================= FRONTEND FIREWALL =================

echo -e "${BLUE}Opening frontend firewall...${RESET}"

gcloud compute firewall-rules delete http-frontend -q 2>/dev/null || true

retry gcloud compute firewall-rules create http-frontend \
  --network default \
  --allow tcp:80 \
  --source-ranges 0.0.0.0/0 \
  --target-tags frontend

# ================= DONE =================

echo
echo -e "${GREEN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD}✅ GSP041 INFRASTRUCTURE READY FOR SCORING${RESET}"
echo -e "${GREEN}${BOLD}============================================${RESET}"
echo

echo -e "${BLUE}Now click Check My Progress in the lab.${RESET}"
echo -e "${BLUE}Lab Link:${RESET}"
echo "https://www.cloudskillsboost.google/focuses/1006"
echo
