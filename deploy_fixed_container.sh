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

# Default values from original script
DEFAULT_RESOURCE_GROUP="presidio-test-rg"
DEFAULT_SQL_SERVER_NAME="presidio-test-sql-server"
DEFAULT_SQL_DB_NAME="presidio-test-db"
DEFAULT_SQL_ADMIN_USER="sqladmin"
DEFAULT_SQL_ADMIN_PASSWORD="P@ssw0rd1234"
DEFAULT_CONTAINER_APP_NAME="presidio-pii-app"
DEFAULT_CONTAINER_APP_ENV="presidio-env"
DEFAULT_ACR_NAME="presidiotestacr"
DEFAULT_LOCATION="eastus"

echo "====== Azure Deployment Configuration ======"
echo "Please provide values for the following resources or press Enter to use defaults"
echo "============================================="

# Prompt for resource values
read -p "Enter Azure region for deployment [$DEFAULT_LOCATION]: " LOCATION_INPUT
LOCATION=${LOCATION_INPUT:-$DEFAULT_LOCATION}

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

read -p "Enter Container App name [$DEFAULT_CONTAINER_APP_NAME]: " CONTAINER_APP_NAME_INPUT
CONTAINER_APP_NAME=${CONTAINER_APP_NAME_INPUT:-$DEFAULT_CONTAINER_APP_NAME}

read -p "Enter Container App Environment name [$DEFAULT_CONTAINER_APP_ENV]: " CONTAINER_APP_ENV_INPUT
CONTAINER_APP_ENV=${CONTAINER_APP_ENV_INPUT:-$DEFAULT_CONTAINER_APP_ENV}

read -p "Enter Azure Container Registry name [$DEFAULT_ACR_NAME]: " ACR_NAME_INPUT
ACR_NAME=${ACR_NAME_INPUT:-$DEFAULT_ACR_NAME}

# Display configuration summary
echo "====== Deployment Configuration Summary ======"
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
read -p "Do you want to proceed with the fixed deployment? (y/n): " CONFIRM
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

# Build and push the fixed Docker image
echo "==== Building fixed Docker image with spaCy model ===="
echo "This will take some time as it needs to download the language model..."
docker build --no-cache -t $ACR_NAME.azurecr.io/presidio-pii:latest ./app
handle_error $? "Docker image build"

# Get credentials for ACR
echo "Getting ACR credentials..."
az acr login --name $ACR_NAME
handle_error $? "ACR login"

# Push the image to ACR
echo "Pushing Docker image to ACR..."
docker push $ACR_NAME.azurecr.io/presidio-pii:latest
handle_error $? "Docker image push"

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
echo "✅ Container App deployed successfully at: https://$CONTAINER_APP_URL"

# Verify the deployment by checking logs
echo "==== Checking Container App logs ===="
echo "Waiting 30 seconds for the container to start up..."
sleep 30
az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow --tail 100