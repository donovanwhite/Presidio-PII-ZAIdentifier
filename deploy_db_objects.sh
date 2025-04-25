#!/bin/bash

# Script to deploy all database objects to Azure SQL Database
# This script runs deploy_all_objects.sql to create stored procedures and triggers

# Default values (same as in build_presidio.sh)
DEFAULT_RESOURCE_GROUP="presidio-test-rg"
DEFAULT_SQL_SERVER_NAME="presidio-test-sql-server"
DEFAULT_SQL_DB_NAME="presidio-test-db"
DEFAULT_SQL_ADMIN_USER="sqladmin"
DEFAULT_SQL_ADMIN_PASSWORD="P@ssw0rd1234"

echo "====== Azure SQL Connection Configuration ======"
echo "Please provide values for the following resources or press Enter to use defaults"
echo "============================================="

# Prompt for resource values
read -p "Enter Resource Group name [$DEFAULT_RESOURCE_GROUP]: " RESOURCE_GROUP_INPUT
RESOURCE_GROUP=${RESOURCE_GROUP_INPUT:-$DEFAULT_RESOURCE_GROUP}

read -p "Enter SQL Server name [$DEFAULT_SQL_SERVER_NAME]: " SQL_SERVER_NAME_INPUT
SQL_SERVER_NAME=${SQL_SERVER_NAME_INPUT:-$DEFAULT_SQL_SERVER_NAME}

read -p "Enter SQL Database name [$DEFAULT_SQL_DB_NAME]: " SQL_DB_NAME_INPUT
SQL_DB_NAME=${SQL_DB_NAME_INPUT:-$DEFAULT_SQL_DB_NAME}

read -p "Enter SQL Admin username [$DEFAULT_SQL_ADMIN_USER]: " SQL_ADMIN_USER_INPUT
SQL_ADMIN_USER=${SQL_ADMIN_USER_INPUT:-$DEFAULT_SQL_ADMIN_USER}

read -p "Enter SQL Admin password [$DEFAULT_SQL_ADMIN_PASSWORD]: " SQL_ADMIN_PASSWORD_INPUT
SQL_ADMIN_PASSWORD=${SQL_ADMIN_PASSWORD_INPUT:-$DEFAULT_SQL_ADMIN_PASSWORD}

# Display configuration summary
echo "====== Connection Configuration Summary ======"
echo "Resource Group: $RESOURCE_GROUP"
echo "SQL Server: $SQL_SERVER_NAME"
echo "SQL Database: $SQL_DB_NAME"
echo "SQL Admin Username: $SQL_ADMIN_USER"
echo "==============================================="

# Ensure firewall allows current IP for connection
echo "Ensuring firewall allows your current IP..."
MY_IP=$(curl -s ifconfig.me)
az sql server firewall-rule create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowDeployIP --start-ip-address $MY_IP --end-ip-address $MY_IP --output none || \
az sql server firewall-rule update --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowDeployIP --start-ip-address $MY_IP --end-ip-address $MY_IP --output none

echo "====== Deploying Database Objects ======"
echo "Running SQL deployment script..."
echo ""

# Execute the deployment script
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/deploy_all_objects.sql

echo ""
echo "Deployment completed!"
echo "Running verification to confirm objects were created..."

# Run verification script to confirm objects were created
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/verify_objects.sql

echo ""
echo "All done! You can now run the test_anonymization.sql script to test functionality."