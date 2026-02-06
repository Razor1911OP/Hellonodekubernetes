# APIs Explorer: Cloud SQL

This folder contains resources and examples for working with Google Cloud SQL APIs.

## About GSP423 Lab

**Lab Name:** APIs Explorer: Cloud SQL

This lab is part of the Google Cloud Skills Boost program and focuses on using the APIs Explorer to interact with Google Cloud SQL. The lab demonstrates how to:

- Use the Cloud SQL Admin API to create and manage Cloud SQL instances
- Create MySQL databases and tables programmatically
- Import data from Cloud Storage into Cloud SQL tables
- Perform database operations using REST API calls
- Manage Cloud SQL resources and permissions

**Learning Objectives:**
- Understand Google Cloud SQL Admin API
- Learn to make authenticated API calls to Cloud SQL
- Practice creating and managing MySQL instances via API
- Import CSV data into Cloud SQL databases
- Clean up and manage cloud resources properly

## GSP423.sh Automation Script

The [GSP423.sh](./GSP423.sh) script automates all tasks for the GSP423 lab, including Cloud SQL instance creation, database management, and data import operations.

### Quick Start (Download and Run)

You can download and run the script directly using curl:

```bash
curl -LO https://raw.githubusercontent.com/Razor1911OP/Hellonodekubernetes/main/APIs%20Explorer%3A%20Cloud%20SQL/GSP423.sh
sudo chmod +x GSP423.sh
./GSP423.sh
```

### Alternative: Local Execution

If you already have the repository cloned, navigate to the "APIs Explorer: Cloud SQL" directory and run:

**Option 1: Direct Execution**
```bash
./GSP423.sh
```

**Option 2: Using Bash**
```bash
bash GSP423.sh
```

### Prerequisites
- Google Cloud SDK installed and configured
- Active Google Cloud project with billing enabled
- Proper permissions to create Cloud SQL instances
- Authentication configured (`gcloud auth login`)

### What the Script Does
1. **Enables SQL Admin API** - Activates the Cloud SQL Admin API for your project
2. **Creates a Cloud SQL MySQL instance** - Deploys a MySQL 5.7 instance in us-central1
3. **Creates a database and table** - Sets up a database with an employee info table
4. **Generates sample CSV data** - Creates a CSV file with employee records
5. **Creates a Cloud Storage bucket** - Sets up a storage bucket for data import
6. **Imports CSV data into Cloud SQL** - Loads the CSV data into the database table
7. **Verifies the data import** - Confirms successful data insertion
8. **Cleans up resources** - Removes the database and temporary files

### Script Features
- ✅ Colorful output with progress indicators
- ✅ Uses Cloud SQL Admin API REST endpoints
- ✅ Automated waiting for resource provisioning
- ✅ Automatic cleanup of temporary resources
- ✅ Error handling with set -euo pipefail

### Important Notes
- Make sure you have the necessary permissions to create Cloud SQL instances in your project
- The script uses the Cloud SQL Admin API, so ensure it's enabled
- Ensure the Google Cloud SDK is properly authenticated before running
- The script will create billable resources (Cloud SQL instance)
- Resources are cleaned up automatically, but monitor your project to ensure proper cleanup
