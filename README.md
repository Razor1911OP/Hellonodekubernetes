# Google Cloud Skills

A tutorial project for deploying a Hello World Node.js application to Google Kubernetes Engine (GKE).

## Quick Start

To download and execute the automated deployment script, run:

```bash
curl -LO https://raw.githubusercontent.com/Razor1911OP/Hellonodekubernetes/main/test.sh
sudo chmod +x test.sh
./test.sh
```

## Running the Test Script

If you already have the script, you can execute it directly:

```bash
bash test.sh
```

or

```bash
./test.sh
```

**Note:** Make sure the script has execute permissions. If needed, run:
```bash
chmod +x test.sh
```

## What the Script Does

The `test.sh` script automates the following steps:
1. Creates a simple Node.js "Hello World" application
2. Builds a Docker image
3. Tests the container locally
4. Pushes the image to Google Container Registry
5. Creates a GKE cluster
6. Deploys the application to Kubernetes
7. Exposes the service with a LoadBalancer
8. Scales the deployment to 4 replicas

## Prerequisites

- Google Cloud SDK (`gcloud`) installed and configured
- Docker installed
- `kubectl` installed
- Active GCP project with billing enabled
- Compute zone configured in gcloud