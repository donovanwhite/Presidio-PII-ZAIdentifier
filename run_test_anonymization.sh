#!/bin/bash

# Script to test South African ID anonymization
# This script connects to your Azure SQL database and runs the test_anonymization.sql script

# Default values (same as in build_presidio.sh)
DEFAULT_RESOURCE_GROUP="presidio-test-rg"
DEFAULT_SQL_SERVER_NAME="presidio-test-sql-server"
DEFAULT_SQL_DB_NAME="presidio-test-db"
DEFAULT_SQL_ADMIN_USER="sqladmin"
DEFAULT_SQL_ADMIN_PASSWORD=""C:\Program Files\Git\bin\bash.exe" -c "./verify_db_objects.sh""

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

# Ensure firewall allows current IP (for running tests remotely)
echo "Ensuring firewall allows your current IP..."
MY_IP=$(curl -s ifconfig.me)
az sql server firewall-rule create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowTestIP --start-ip-address $MY_IP --end-ip-address $MY_IP --output none || \
az sql server firewall-rule update --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowTestIP --start-ip-address $MY_IP --end-ip-address $MY_IP --output none

echo "====== Running Anonymization Test ======"
echo "Executing SQL test script to verify South African ID anonymization..."
echo "This will insert a test record and display the anonymized result."
echo ""

# Execute the test script
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/test_anonymization.sql

echo ""
echo "Test execution completed!"