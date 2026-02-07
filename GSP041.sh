#!/bin/bash
set -e

### COLORS ###
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

### RETRY FUNCTION ###
retry() {
  local n=1
  local max=5
  local delay=20

  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        echo -e "${YELLOW}Retry $n/$max...${NC}"
        sleep $delay
      else
        echo -e "${RED}Command failed after $max attempts${NC}"
        exit 1
      fi
    }
  done
}

### PROJECT ###
PROJECT_ID=$(gcloud config get-value project)
echo -e "${GREEN}Project: $PROJECT_ID${NC}"

### REGION / ZONE ###
read -p "Enter REGION (ex: us-central1): " REGION
read -p "Enter ZONE (ex: us-central1-a): " ZONE

gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

### ENABLE API ###
echo -e "${BLUE}Enabling APIs...${NC}"
retry gcloud services enable compute.googleapis.com

################################
# BACKEND SCRIPT
################################

echo -e "${BLUE}Creating backend startup script...${NC}"

cat > ~/backend.sh << 'EOF'
sudo chmod -R 777 /usr/local/sbin/
sudo cat << PYEOF > /usr/local/sbin/serveprimes.py
import http.server

def is_prime(a): return a!=1 and all(a % i for i in range(2,int(a**0.5)+1))

class myHandler(http.server.BaseHTTPRequestHandler):
  def do_GET(s):
    s.send_response(200)
    s.send_header("Content-type","text/plain")
    s.end_headers()
    s.wfile.write(bytes(str(is_prime(int(s.path[1:]))),"utf-8"))

http.server.HTTPServer(("",80),myHandler).serve_forever()
PYEOF

nohup python3 /usr/local/sbin/serveprimes.py >/dev/null 2>&1 &
EOF

################################
# INSTANCE TEMPLATE
################################

if ! gcloud compute instance-templates describe primecalc &>/dev/null; then
  echo -e "${BLUE}Creating instance template...${NC}"

  retry gcloud compute instance-templates create primecalc \
    --metadata-from-file startup-script=backend.sh \
    --no-address \
    --tags backend \
    --machine-type=e2-medium
else
  echo -e "${GREEN}Instance template exists. Skipping.${NC}"
fi

################################
# FIREWALL BACKEND
################################

if ! gcloud compute firewall-rules describe http &>/dev/null; then
  echo -e "${BLUE}Creating firewall rule (backend)...${NC}"

  retry gcloud compute firewall-rules create http \
    --network default \
    --allow tcp:80 \
    --source-ranges 0.0.0.0/0 \
    --target-tags backend
else
  echo -e "${GREEN}Firewall rule exists. Skipping.${NC}"
fi

################################
# MIG
################################

if ! gcloud compute instance-groups managed describe backend \
  --zone=$ZONE &>/dev/null; then

  echo -e "${BLUE}Creating instance group...${NC}"

  retry gcloud compute instance-groups managed create backend \
    --size 3 \
    --template primecalc \
    --zone $ZONE
else
  echo -e "${GREEN}Instance group exists. Skipping.${NC}"
fi

################################
# HEALTH CHECK
################################

if ! gcloud compute health-checks describe ilb-health &>/dev/null; then
  echo -e "${BLUE}Creating health check...${NC}"

  retry gcloud compute health-checks create http ilb-health \
    --request-path /2
else
  echo -e "${GREEN}Health check exists. Skipping.${NC}"
fi

################################
# BACKEND SERVICE
################################

if ! gcloud compute backend-services describe prime-service \
  --region=$REGION &>/dev/null; then

  echo -e "${BLUE}Creating backend service...${NC}"

  retry gcloud compute backend-services create prime-service \
    --load-balancing-scheme internal \
    --region=$REGION \
    --protocol tcp \
    --health-checks ilb-health
else
  echo -e "${GREEN}Backend service exists. Skipping.${NC}"
fi

################################
# ADD BACKEND
################################

if ! gcloud compute backend-services get-health prime-service \
  --region=$REGION &>/dev/null; then

  echo -e "${BLUE}Attaching instance group...${NC}"

  retry gcloud compute backend-services add-backend prime-service \
    --instance-group backend \
    --instance-group-zone $ZONE \
    --region=$REGION
fi

################################
# FORWARDING RULE
################################

if ! gcloud compute forwarding-rules describe prime-lb \
  --region=$REGION &>/dev/null; then

  echo -e "${BLUE}Creating forwarding rule...${NC}"

  retry gcloud compute forwarding-rules create prime-lb \
    --load-balancing-scheme internal \
    --ports 80 \
    --network default \
    --region=$REGION \
    --backend-service prime-service
else
  echo -e "${GREEN}Forwarding rule exists. Skipping.${NC}"
fi

################################
# GET ILB IP
################################

ILB_IP=$(gcloud compute forwarding-rules describe prime-lb \
  --region=$REGION \
  --format="get(IPAddress)")

echo -e "${GREEN}Internal LB IP: $ILB_IP${NC}"

################################
# TEST VM
################################

if ! gcloud compute instances describe testinstance \
  --zone=$ZONE &>/dev/null; then

  echo -e "${BLUE}Creating test VM...${NC}"

  retry gcloud compute instances create testinstance \
    --machine-type=e2-standard-2 \
    --zone=$ZONE
else
  echo -e "${GREEN}Test VM exists. Skipping.${NC}"
fi

################################
# MANUAL CHECKPOINT
################################

echo
echo -e "${YELLOW}================ MANUAL STEP ================${NC}"
echo "SSH and test:"
echo "gcloud compute ssh testinstance --zone=$ZONE"
echo "curl $ILB_IP/2"
echo "curl $ILB_IP/4"
echo "curl $ILB_IP/5"
echo "exit"
echo "Then delete VM:"
echo "gcloud compute instances delete testinstance --zone=$ZONE"
echo
read -p "Complete this and press ENTER..."

################################
# FRONTEND SCRIPT
################################

cat > ~/frontend.sh << EOF
sudo chmod -R 777 /usr/local/sbin/
sudo cat << PYEOF > /usr/local/sbin/getprimes.py
import urllib.request
from multiprocessing.dummy import Pool as ThreadPool
import http.server

PREFIX="http://$ILB_IP/"

def get_url(number):
    return urllib.request.urlopen(PREFIX+str(number)).read().decode('utf-8')

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
      if not (x%10): s.wfile.write("<tr>".encode())
      if results[x]=="True":
        s.wfile.write("<td bgcolor='#00ff00'>".encode())
      else:
        s.wfile.write("<td bgcolor='#ff0000'>".encode())
      s.wfile.write(str(x+i).encode()+"</td>".encode())
      if not ((x+1)%10): s.wfile.write("</tr>".encode())
    s.wfile.write("</table></body></html>".encode())

http.server.HTTPServer(("",80),myHandler).serve_forever()
PYEOF

nohup python3 /usr/local/sbin/getprimes.py >/dev/null 2>&1 &
EOF

################################
# FRONTEND VM
################################

if ! gcloud compute instances describe frontend \
  --zone=$ZONE &>/dev/null; then

  echo -e "${BLUE}Creating frontend VM...${NC}"

  retry gcloud compute instances create frontend \
    --zone=$ZONE \
    --metadata-from-file startup-script=frontend.sh \
    --tags frontend \
    --machine-type=e2-standard-2
else
  echo -e "${GREEN}Frontend exists. Skipping.${NC}"
fi

################################
# FRONTEND FIREWALL
################################

if ! gcloud compute firewall-rules describe http2 &>/dev/null; then
  echo -e "${BLUE}Creating frontend firewall...${NC}"

  retry gcloud compute firewall-rules create http2 \
    --network default \
    --allow tcp:80 \
    --source-ranges 0.0.0.0/0 \
    --target-tags frontend
fi

################################
# FINAL
################################

FRONT_IP=$(gcloud compute instances describe frontend \
--zone=$ZONE \
--format="get(networkInterfaces[0].accessConfigs[0].natIP)")

echo
echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}LAB COMPLETED${NC}"
echo -e "${GREEN}==================================${NC}"
echo
echo "Frontend URL:"
echo "http://$FRONT_IP"
echo
echo "Click Check My Progress in lab."
echo
