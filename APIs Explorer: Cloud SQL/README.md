# APIs Explorer: Cloud SQL

This folder contains resources and examples for working with Google Cloud SQL APIs.

## Running the GSP423.sh Script

The [GSP423.sh](./GSP423.sh) script automates Cloud SQL instance creation, database management, and data import tasks.

### Prerequisites
- Google Cloud SDK installed and configured
- Active Google Cloud project
- Proper permissions to create Cloud SQL instances

### How to Run

**Option 1: Direct Execution**
```bash
./GSP423.sh
```

**Option 2: Using Bash**
```bash
bash GSP423.sh
```

**Option 3: With Bash (explicit path)**
```bash
bash ./GSP423.sh
```

### What the Script Does
1. Enables SQL Admin API
2. Creates a Cloud SQL MySQL instance
3. Creates a database and table
4. Generates sample CSV data
5. Creates a Cloud Storage bucket
6. Imports CSV data into Cloud SQL
7. Verifies the data import
8. Cleans up resources

### Note
Make sure you have the necessary permissions and that the Google Cloud SDK is properly authenticated before running this script.
