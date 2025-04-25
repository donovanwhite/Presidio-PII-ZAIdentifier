#!/bin/bash

# Script to rebuild the Docker image with spaCy model and deploy using Bicep
# This script fixes the Container App deployment errors

# Check if Azure CLI is installed
if ! command -v az &> /dev/null
then
    echo "Azure CLI could not be found. Please install it before running this script."
    exit 1
fi

# Check if Docker is installed and running
if ! command -v docker &> /dev/null
then
    echo "Docker could not be found. Please install it before running this script."
    exit 1
else
    echo "Checking Docker connectivity..."
    if ! docker info &> /dev/null
    then
        echo "⚠️ Docker daemon is not running or not accessible."
        exit 1
    else
        echo "✓ Docker is running and accessible."
    fi
fi

# Ask for deployment type
echo "====== Deployment Type Selection ======"
echo "1. Full Deployment (Creates all infrastructure resources)"
echo "2. Partial Deployment (Updates existing resources only)"
echo "============================================="

read -p "Select deployment type (1/2): " DEPLOYMENT_TYPE

IS_FULL_DEPLOYMENT=true
if [[ "$DEPLOYMENT_TYPE" == "2" ]]; then
    IS_FULL_DEPLOYMENT=false
    echo "Selected: Partial Deployment - will update existing resources only."
else
    echo "Selected: Full Deployment - will create all necessary infrastructure."
fi

# Default values
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP="presidio-test-rg"
DEFAULT_SQL_SERVER_NAME="presidio-test-sql-server"
DEFAULT_SQL_DB_NAME="presidio-test-db"
DEFAULT_SQL_ADMIN_USER="sqladmin"
DEFAULT_SQL_ADMIN_PASSWORD="P@ssw0rd1234"
DEFAULT_CONTAINER_APP_NAME="presidio-pii-app"
DEFAULT_CONTAINER_APP_ENV="presidio-env"
DEFAULT_ACR_NAME="presidiotestacr"

echo "====== Azure Deployment Configuration ======"
echo "Please provide values for the following resources or press Enter to use defaults"
echo "============================================="

# Always prompt for resource group and location
read -p "Enter Azure region for deployment [$DEFAULT_LOCATION]: " LOCATION_INPUT
LOCATION=${LOCATION_INPUT:-$DEFAULT_LOCATION}

read -p "Enter Resource Group name [$DEFAULT_RESOURCE_GROUP]: " RESOURCE_GROUP_INPUT
RESOURCE_GROUP=${RESOURCE_GROUP_INPUT:-$DEFAULT_RESOURCE_GROUP}

# Common parameters for both deployment types
read -p "Enter Container App name [$DEFAULT_CONTAINER_APP_NAME]: " CONTAINER_APP_NAME_INPUT
CONTAINER_APP_NAME=${CONTAINER_APP_NAME_INPUT:-$DEFAULT_CONTAINER_APP_NAME}

read -p "Enter SQL Database name [$DEFAULT_SQL_DB_NAME]: " SQL_DB_NAME_INPUT
SQL_DB_NAME=${SQL_DB_NAME_INPUT:-$DEFAULT_SQL_DB_NAME}

read -p "Enter SQL Admin username [$DEFAULT_SQL_ADMIN_USER]: " SQL_ADMIN_USER_INPUT
SQL_ADMIN_USER=${SQL_ADMIN_USER_INPUT:-$DEFAULT_SQL_ADMIN_USER}

read -p "Enter SQL Admin password [$DEFAULT_SQL_ADMIN_PASSWORD]: " SQL_ADMIN_PASSWORD_INPUT
SQL_ADMIN_PASSWORD=${SQL_ADMIN_PASSWORD_INPUT:-$DEFAULT_SQL_ADMIN_PASSWORD}

# For partial deployment, resources must exist
if [[ "$IS_FULL_DEPLOYMENT" == "false" ]]; then
    echo "====== Existing Resources Information ======"
    echo "Since you selected partial deployment, please provide details of existing resources."
    
    # Prompt for ACR details
    read -p "Enter existing Azure Container Registry name [$DEFAULT_ACR_NAME]: " ACR_NAME_INPUT
    ACR_NAME=${ACR_NAME_INPUT:-$DEFAULT_ACR_NAME}
    
    # Check if ACR exists
    echo "Verifying Container Registry $ACR_NAME exists..."
    az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ Error: Azure Container Registry $ACR_NAME not found in resource group $RESOURCE_GROUP."
        echo "Please provide a valid ACR name or switch to Full Deployment."
        exit 1
    fi
    
    # Prompt for Container App Environment
    read -p "Enter existing Container App Environment name [$DEFAULT_CONTAINER_APP_ENV]: " CONTAINER_APP_ENV_INPUT
    CONTAINER_APP_ENV=${CONTAINER_APP_ENV_INPUT:-$DEFAULT_CONTAINER_APP_ENV}
    
    # Check if Container App Environment exists
    echo "Verifying Container App Environment $CONTAINER_APP_ENV exists..."
    az containerapp env show --name $CONTAINER_APP_ENV --resource-group $RESOURCE_GROUP > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ Error: Container App Environment $CONTAINER_APP_ENV not found in resource group $RESOURCE_GROUP."
        echo "Please provide a valid environment name or switch to Full Deployment."
        exit 1
    fi
    
    # Prompt for SQL Server details
    read -p "Enter existing SQL Server name [$DEFAULT_SQL_SERVER_NAME]: " SQL_SERVER_NAME_INPUT
    SQL_SERVER_NAME=${SQL_SERVER_NAME_INPUT:-$DEFAULT_SQL_SERVER_NAME}
    
    # Check if SQL Server exists
    echo "Verifying SQL Server $SQL_SERVER_NAME exists..."
    az sql server show --name $SQL_SERVER_NAME --resource-group $RESOURCE_GROUP > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ Error: SQL Server $SQL_SERVER_NAME not found in resource group $RESOURCE_GROUP."
        echo "Please provide a valid SQL Server name or switch to Full Deployment."
        exit 1
    fi
else
    # For full deployment, prompt for remaining infrastructure names
    read -p "Enter SQL Server name [$DEFAULT_SQL_SERVER_NAME]: " SQL_SERVER_NAME_INPUT
    SQL_SERVER_NAME=${SQL_SERVER_NAME_INPUT:-$DEFAULT_SQL_SERVER_NAME}

    read -p "Enter Container App Environment name [$DEFAULT_CONTAINER_APP_ENV]: " CONTAINER_APP_ENV_INPUT
    CONTAINER_APP_ENV=${CONTAINER_APP_ENV_INPUT:-$DEFAULT_CONTAINER_APP_ENV}

    read -p "Enter Azure Container Registry name [$DEFAULT_ACR_NAME]: " ACR_NAME_INPUT
    ACR_NAME=${ACR_NAME_INPUT:-$DEFAULT_ACR_NAME}
fi

# Display configuration summary
echo "====== Deployment Configuration Summary ======"
echo "Deployment Type: $([ "$IS_FULL_DEPLOYMENT" == "true" ] && echo "Full" || echo "Partial")"
echo "Region: $LOCATION"
echo "Resource Group: $RESOURCE_GROUP"
echo "SQL Server: $SQL_SERVER_NAME"
echo "SQL Database: $SQL_DB_NAME"
echo "SQL Admin Username: $SQL_ADMIN_USER"
echo "Container App: $CONTAINER_APP_NAME"
echo "Container App Environment: $CONTAINER_APP_ENV"
echo "Azure Container Registry: $ACR_NAME"
echo "============================================="

# Confirm before proceeding
read -p "Do you want to proceed with the deployment? (y/n): " CONFIRM
if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
    echo "Deployment canceled."
    exit 0
fi

# Create a function to handle errors
handle_error() {
    local exit_code=$1
    local error_message=$2
    if [ $exit_code -ne 0 ]; then
        echo "❌ Error: $error_message (Exit code: $exit_code)"
        echo "Deployment failed."
        exit $exit_code
    else
        echo "✓ Success: $error_message"
    fi
}

# Create infrastructure resources if this is a full deployment
if [[ "$IS_FULL_DEPLOYMENT" == "true" ]]; then
    # Create Resource Group if it doesn't exist
    echo "==== Creating/Checking Resource Group ===="
    az group show --name $RESOURCE_GROUP > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Creating Resource Group $RESOURCE_GROUP..."
        az group create --name $RESOURCE_GROUP --location $LOCATION
        handle_error $? "Resource Group creation"
    else
        echo "Resource Group $RESOURCE_GROUP already exists."
    fi

    # Create Azure Container Registry if it doesn't exist
    echo "==== Creating/Checking Azure Container Registry ===="
    az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Creating Azure Container Registry $ACR_NAME..."
        az acr create --name $ACR_NAME --resource-group $RESOURCE_GROUP --location $LOCATION --sku Basic --admin-enabled true
        handle_error $? "Azure Container Registry creation"
    else
        echo "Azure Container Registry $ACR_NAME already exists."
        # Ensure admin is enabled
        az acr update --name $ACR_NAME --resource-group $RESOURCE_GROUP --admin-enabled true
        handle_error $? "Enabling admin on Azure Container Registry"
    fi

    # Create Container App Environment if it doesn't exist
    echo "==== Creating/Checking Container App Environment ===="
    az containerapp env show --name $CONTAINER_APP_ENV --resource-group $RESOURCE_GROUP > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Creating Container App Environment $CONTAINER_APP_ENV..."
        az containerapp env create --name $CONTAINER_APP_ENV --resource-group $RESOURCE_GROUP --location $LOCATION
        handle_error $? "Container App Environment creation"
    else
        echo "Container App Environment $CONTAINER_APP_ENV already exists."
    fi

    # Create SQL Server and Database if they don't exist
    echo "==== Creating/Checking SQL Server and Database ===="
    az sql server show --name $SQL_SERVER_NAME --resource-group $RESOURCE_GROUP > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Creating SQL Server $SQL_SERVER_NAME..."
        az sql server create --name $SQL_SERVER_NAME --resource-group $RESOURCE_GROUP --location $LOCATION --admin-user $SQL_ADMIN_USER --admin-password $SQL_ADMIN_PASSWORD
        handle_error $? "SQL Server creation"
        
        # Configure Firewall Rules - allow Azure services
        echo "Configuring SQL Server firewall rules..."
        az sql server firewall-rule create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowAllAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
        handle_error $? "SQL Server firewall rule creation for Azure Services"
        
        # Allow current IP for deployment
        echo "Allowing current IP for SQL Server access..."
        MY_IP=$(curl -s ifconfig.me)
        az sql server firewall-rule create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowDeployIP --start-ip-address $MY_IP --end-ip-address $MY_IP
        handle_error $? "SQL Server firewall rule creation for current IP"
    else
        echo "SQL Server $SQL_SERVER_NAME already exists."
        # Update firewall rule for current IP
        echo "Updating firewall rule for current IP..."
        MY_IP=$(curl -s ifconfig.me)
        az sql server firewall-rule create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowDeployIP --start-ip-address $MY_IP --end-ip-address $MY_IP --output none || \
        az sql server firewall-rule update --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowDeployIP --start-ip-address $MY_IP --end-ip-address $MY_IP --output none
    fi

    # Check if database exists
    az sql db show --name $SQL_DB_NAME --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Creating SQL Database $SQL_DB_NAME..."
        az sql db create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name $SQL_DB_NAME --service-objective S0
        handle_error $? "SQL Database creation"
        
        # Deploy database tables
        echo "Deploying database tables..."
        sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/create_tbl.sql
        handle_error $? "Database table creation"
        
        # Deploy dummy data
        echo "Deploying dummy data..."
        sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/insert_dummy_data.sql
        handle_error $? "Database data insertion"
    else
        echo "SQL Database $SQL_DB_NAME already exists."
    fi
else
    # For partial deployment, just update firewall rule for SQL server
    echo "==== Updating Firewall Rules for SQL Server ===="
    MY_IP=$(curl -s ifconfig.me)
    az sql server firewall-rule create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowDeployIP --start-ip-address $MY_IP --end-ip-address $MY_IP --output none || \
    az sql server firewall-rule update --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowDeployIP --start-ip-address $MY_IP --end-ip-address $MY_IP --output none
    handle_error $? "SQL Server firewall rule update"
fi

# Build and push the fixed Docker image - for both full and partial deployment
echo "==== Building fixed Docker image with spaCy model ===="
echo "This will take some time as it needs to download the language model..."
docker build --no-cache -t $ACR_NAME.azurecr.io/presidio-pii:latest ./app
handle_error $? "Docker image build"

# Get credentials for ACR
echo "Getting ACR credentials and logging in..."
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query passwords[0].value -o tsv)
handle_error $? "Getting ACR credentials"

# Login to ACR with Docker
echo "Logging in to ACR with Docker..."
echo $ACR_PASSWORD | docker login $ACR_NAME.azurecr.io --username $ACR_USERNAME --password-stdin
handle_error $? "Docker login to ACR"

# Push the image to ACR
echo "Pushing Docker image to ACR..."
docker push $ACR_NAME.azurecr.io/presidio-pii:latest
handle_error $? "Docker image push"

# Create/update the sqlscript.bicep module directory if it doesn't exist
mkdir -p infrastructure/modules

# Deploy using Bicep template with what-if validation
echo "==== Deploying with Bicep template (validation) ===="
az deployment group what-if \
  --resource-group $RESOURCE_GROUP \
  --template-file ./infrastructure/main.bicep \
  --parameters \
    location=$LOCATION \
    containerAppName=$CONTAINER_APP_NAME \
    containerAppEnvName=$CONTAINER_APP_ENV \
    acrName=$ACR_NAME \
    sqlServerName=$SQL_SERVER_NAME \
    sqlDbName=$SQL_DB_NAME \
    sqlAdminUser=$SQL_ADMIN_USER \
    sqlAdminPassword=$SQL_ADMIN_PASSWORD
handle_error $? "Bicep template validation"

# Confirm before proceeding with actual deployment
read -p "Do you want to proceed with the actual deployment? (y/n): " CONFIRM
if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
    echo "Deployment canceled after validation."
    exit 0
fi

# Execute the deployment
echo "==== Deploying resources with Bicep ===="
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file ./infrastructure/main.bicep \
  --parameters \
    location=$LOCATION \
    containerAppName=$CONTAINER_APP_NAME \
    containerAppEnvName=$CONTAINER_APP_ENV \
    acrName=$ACR_NAME \
    sqlServerName=$SQL_SERVER_NAME \
    sqlDbName=$SQL_DB_NAME \
    sqlAdminUser=$SQL_ADMIN_USER \
    sqlAdminPassword=$SQL_ADMIN_PASSWORD
handle_error $? "Bicep deployment"

# Get the Container App URL
CONTAINER_APP_URL=$(az containerapp show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)
handle_error $? "Getting Container App URL"
echo "✅ Container App deployed successfully at: https://$CONTAINER_APP_URL"

# Create a SQL script to update the stored procedure with the correct endpoint URL
echo "==== Updating SQL stored procedure with Container App endpoint URL ===="
cat > update_sp_endpoint.sql << EOF
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Check if procedure exists before creating or updating
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_call_rest_endpoint')
BEGIN
    -- Update existing stored procedure with the new endpoint URL
    DROP PROCEDURE [dbo].[usp_call_rest_endpoint]
END
GO

-- Create the stored procedure with the new endpoint URL
CREATE PROCEDURE [dbo].[usp_call_rest_endpoint]
    @input_data NVARCHAR(MAX),
    @response NVARCHAR(MAX) OUTPUT
AS
BEGIN
    -- The endpoint URL from Container App
    DECLARE @url NVARCHAR(MAX) = 'https://$CONTAINER_APP_URL/analyze';
    DECLARE @headers NVARCHAR(MAX) = '{"Content-Type": "application/json"}';
    DECLARE @payload NVARCHAR(MAX) = '{"text": "' + @input_data + '"}';

    -- Call the external REST endpoint
    EXEC sp_invoke_external_rest_endpoint
        @url = @url,
        @method = 'POST',
        @headers = @headers,
        @payload = @payload,
        @response = @response OUTPUT;
END
GO

-- Print confirmation message
PRINT 'Stored procedure updated with endpoint: https://$CONTAINER_APP_URL/analyze';
GO
EOF

# Execute the SQL script to update the stored procedure
echo "Updating SQL stored procedure with endpoint URL: https://$CONTAINER_APP_URL/analyze"
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i update_sp_endpoint.sql
handle_error $? "SQL stored procedure update"
echo "✅ SQL stored procedure updated successfully with Container App endpoint"

# Deploy database objects for both full and partial deployment
echo "==== Deploying database objects ===="
echo "Running database objects deployment script..."
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/deploy_all_objects.sql
handle_error $? "Database objects deployment"

# Verify the deployment by checking logs
echo "==== Checking Container App logs ===="
echo "Waiting 30 seconds for the container to start up..."
sleep 30
az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow --tail 100