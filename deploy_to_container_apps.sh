#!/bin/bash

# Script to deploy the Presidio PII application to Azure Container Apps
# This replaces the previous Function App deployment

# Check if Azure CLI is installed
if ! command -v az &> /dev/null
then
    echo "Azure CLI could not be found. Please install it before running this script."
    exit
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null
then
    echo "Docker could not be found. Please install it before running this script."
    echo "You can still continue using token-based authentication for ACR."
    SKIP_DOCKER_STEPS=true
else
    # Check if Docker is running and accessible
    echo "Checking Docker connectivity..."
    if ! docker info &> /dev/null
    then
        echo "⚠️ Docker daemon is not running or not accessible."
        echo "On Windows, please make sure that:"
        echo " - Docker Desktop is installed and running"
        echo " - You are running this script with administrator privileges"
        echo " - The Docker service has been started (check with 'sc query docker')"
        
        echo "You have the following options:"
        echo "1. Exit script and fix Docker issues"
        echo "2. Continue without Docker support (skip container builds and deployments)"
        echo "3. Use 'az acr login --expose-token' to authenticate to ACR without Docker"
        
        read -p "Choose an option (1/2/3): " DOCKER_OPTION
        case $DOCKER_OPTION in
            1)
                echo "Exiting script. Please start Docker and try again."
                exit 1
                ;;
            2)
                echo "Continuing without Docker support. Container-related steps will be skipped."
                SKIP_DOCKER_STEPS=true
                USE_ACR_TOKEN=false
                ;;
            3)
                echo "Will use token-based authentication for ACR."
                SKIP_DOCKER_STEPS=true
                USE_ACR_TOKEN=true
                ;;
            *)
                echo "Invalid option. Exiting script."
                exit 1
                ;;
        esac
    else
        SKIP_DOCKER_STEPS=false
        USE_ACR_TOKEN=false
        echo "✓ Docker is running and accessible."
    fi
fi

# Initialize DEPLOY_EXISTING to false by default
DEPLOY_EXISTING=false

# Add a switch to determine whether to deploy to existing infrastructure or create new
while getopts "e" opt; do
  case $opt in
    e)
      echo "Deploying to existing infrastructure..."
      DEPLOY_EXISTING=true
      ;;
    *)
      # This case doesn't get hit without arguments
      ;;
  esac
done

# Set default values
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
echo "Note: In a production environment, credentials should be stored securely in Azure Key Vault"
echo "============================================="

# Prompt for all resource values
read -p "Enter Azure region for deployment [$DEFAULT_LOCATION]: " LOCATION_INPUT
LOCATION=${LOCATION_INPUT:-$DEFAULT_LOCATION}
echo "Deploying to region: $LOCATION"

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
if [ "$SKIP_DOCKER_STEPS" = true ]; then
    if [ "$USE_ACR_TOKEN" = true ]; then
        echo "Docker Status: NOT AVAILABLE (using ACR token-based authentication)"
    else
        echo "Docker Status: NOT AVAILABLE (skipping container steps)"
    fi
else
    echo "Docker Status: ENABLED"
fi
echo "============================================="

# Confirm before proceeding
read -p "Do you want to proceed with deployment? (y/n): " CONFIRM
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
        echo "You can continue with the deployment, but some resources may not be properly configured."
        read -p "Continue anyway? (y/n): " CONTINUE
        if [[ $CONTINUE != "y" && $CONTINUE != "Y" ]]; then
            echo "Deployment canceled."
            exit $exit_code
        fi
        echo "Continuing deployment..."
    else
        echo "✓ Success: $error_message"
    fi
}

if [ "$DEPLOY_EXISTING" = false ]; then
  # Create Resource Group
  echo "Creating resource group..."
  az group create --name $RESOURCE_GROUP --location $LOCATION
  handle_error $? "Resource group creation"

  # Create Azure SQL Server and Database
  echo "Creating SQL server..."
  az sql server create --name $SQL_SERVER_NAME --resource-group $RESOURCE_GROUP --location $LOCATION --admin-user $SQL_ADMIN_USER --admin-password $SQL_ADMIN_PASSWORD
  handle_error $? "SQL Server creation"
  
  echo "Creating SQL database..."
  az sql db create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name $SQL_DB_NAME --service-objective S0
  handle_error $? "SQL Database creation"

  # Configure Firewall Rules for Azure SQL Server
  echo "Configuring SQL server firewall rules..."
  local_ip=$(curl -s ifconfig.me)
  az sql server firewall-rule create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowYourIP --start-ip-address $local_ip --end-ip-address $local_ip
  handle_error $? "SQL Firewall rule creation"

  # Create Azure Container Registry with admin enabled
  echo "Creating Azure Container Registry..."
  az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true
  handle_error $? "Azure Container Registry creation"

  # Get ACR admin credentials
  echo "Getting ACR admin credentials..."
  ACR_ADMIN_USER=$(az acr credential show --resource-group $RESOURCE_GROUP --name $ACR_NAME --query username -o tsv)
  ACR_ADMIN_PASSWORD=$(az acr credential show --resource-group $RESOURCE_GROUP --name $ACR_NAME --query passwords[0].value -o tsv)
  handle_error $? "Getting ACR admin credentials"
  
  # Get ACR login server
  ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer -o tsv)
  handle_error $? "Getting ACR login server"

  # Create Container App Environment
  echo "Creating Container App Environment..."
  az containerapp env create --name $CONTAINER_APP_ENV --resource-group $RESOURCE_GROUP --location $LOCATION
  handle_error $? "Container App Environment creation"

else
  # For existing infrastructure, ensure ACR has admin enabled and get credentials
  echo "Checking existing ACR and enabling admin if needed..."
  # Check if admin is enabled, if not, enable it
  ADMIN_ENABLED=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query adminUserEnabled -o tsv)
  if [ "$ADMIN_ENABLED" = "false" ]; then
    echo "Enabling admin user on ACR..."
    az acr update --name $ACR_NAME --resource-group $RESOURCE_GROUP --admin-enabled true
    handle_error $? "Enabling admin user on ACR"
  fi

  # Get ACR admin credentials and login server for existing infrastructure
  echo "Getting ACR admin credentials..."
  ACR_ADMIN_USER=$(az acr credential show --resource-group $RESOURCE_GROUP --name $ACR_NAME --query username -o tsv)
  ACR_ADMIN_PASSWORD=$(az acr credential show --resource-group $RESOURCE_GROUP --name $ACR_NAME --query passwords[0].value -o tsv)
  handle_error $? "Getting ACR admin credentials"
  
  # Get ACR login server
  ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer -o tsv)
  handle_error $? "Getting ACR login server"
  
  # Check if Container App Environment exists
  ENV_EXISTS=$(az containerapp env list --resource-group $RESOURCE_GROUP --query "[?name=='$CONTAINER_APP_ENV']" -o tsv)
  if [ -z "$ENV_EXISTS" ]; then
    echo "Creating Container App Environment..."
    az containerapp env create --name $CONTAINER_APP_ENV --resource-group $RESOURCE_GROUP --location $LOCATION
    handle_error $? "Container App Environment creation"
  else
    echo "Container App Environment already exists."
  fi
fi

# Deploy SQL scripts to the database - first create tables, then insert data, then other scripts
echo "Deploying database tables..."
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/create_tbl.sql
handle_error $? "Database table creation"

echo "Inserting dummy data..."
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/insert_dummy_data.sql
handle_error $? "Database data insertion"

echo "Deploying database objects (stored procedures and triggers)..."
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/deploy_all_objects.sql
handle_error $? "Database objects deployment"

# Handle Docker-related steps
if [ "$SKIP_DOCKER_STEPS" = false ]; then
  # Build and Push Docker Image to ACR using Docker
  echo "Building Docker image..."
  docker build --no-cache -t $ACR_NAME.azurecr.io/presidio-pii:latest ./app
  handle_error $? "Docker image build"
  
  echo "Logging in to Azure Container Registry using admin credentials..."
  echo "Using ACR admin credentials for Docker login to $ACR_LOGIN_SERVER"
  docker login $ACR_LOGIN_SERVER --username $ACR_ADMIN_USER --password $ACR_ADMIN_PASSWORD
  handle_error $? "ACR login with admin credentials"
  
  echo "Pushing Docker image to ACR..."
  docker push $ACR_NAME.azurecr.io/presidio-pii:latest
  handle_error $? "Docker image push"

  # Create/Update the Container App
  echo "Checking if Container App exists..."
  APP_EXISTS=$(az containerapp list --resource-group $RESOURCE_GROUP --query "[?name=='$CONTAINER_APP_NAME']" -o tsv)
  
  if [ -z "$APP_EXISTS" ]; then
    echo "Creating Container App..."
    az containerapp create \
      --name $CONTAINER_APP_NAME \
      --resource-group $RESOURCE_GROUP \
      --environment $CONTAINER_APP_ENV \
      --image $ACR_LOGIN_SERVER/presidio-pii:latest \
      --registry-server $ACR_LOGIN_SERVER \
      --registry-username $ACR_ADMIN_USER \
      --registry-password $ACR_ADMIN_PASSWORD \
      --target-port 80 \
      --ingress external
    handle_error $? "Container App creation"
  else
    echo "Updating Container App..."
    az containerapp update \
      --name $CONTAINER_APP_NAME \
      --resource-group $RESOURCE_GROUP \
      --image $ACR_LOGIN_SERVER/presidio-pii:latest
    handle_error $? "Container App update"
  fi
  
elif [ "$USE_ACR_TOKEN" = true ]; then
  # Token-based authentication flow without requiring Docker
  echo "Using admin credentials for manual image push instructions..."
  
  # Instructions for manual image push (since we can't do it without Docker)
  echo "====== Manual Image Push Instructions ======"
  echo "Since Docker is not available, you'll need to manually push your container image."
  echo "Use these admin credentials on a machine with Docker installed:"
  echo ""
  echo "1. Build your image: docker build -t $ACR_LOGIN_SERVER/presidio-pii:latest ./app"
  echo "2. Log in using admin credentials: docker login $ACR_LOGIN_SERVER --username $ACR_ADMIN_USER --password $ACR_ADMIN_PASSWORD"
  echo "3. Push your image: docker push $ACR_LOGIN_SERVER/presidio-pii:latest"
  echo "============================================"
  
  # Save credentials and instructions to a file for later use
  echo "# ACR Admin Credentials for $ACR_NAME" > acr_admin_instructions.txt
  echo "ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER" >> acr_admin_instructions.txt
  echo "ACR_ADMIN_USER=$ACR_ADMIN_USER" >> acr_admin_instructions.txt
  echo "ACR_ADMIN_PASSWORD=$ACR_ADMIN_PASSWORD" >> acr_admin_instructions.txt
  echo "" >> acr_admin_instructions.txt
  echo "# Instructions:" >> acr_admin_instructions.txt
  echo "# 1. Build your image: docker build -t $ACR_LOGIN_SERVER/presidio-pii:latest ./app" >> acr_admin_instructions.txt
  echo "# 2. Log in using admin credentials: docker login $ACR_LOGIN_SERVER --username $ACR_ADMIN_USER --password $ACR_ADMIN_PASSWORD" >> acr_admin_instructions.txt
  echo "# 3. Push your image: docker push $ACR_LOGIN_SERVER/presidio-pii:latest" >> acr_admin_instructions.txt
  
  echo "Admin credentials and instructions saved to acr_admin_instructions.txt"
  
  echo "Would you like to create the Container App with the container image URL even though the image hasn't been pushed yet?"
  read -p "Create Container App with container image URL? (y/n): " CREATE_CONTAINER_APP
  if [[ $CREATE_CONTAINER_APP == "y" || $CREATE_CONTAINER_APP == "Y" ]]; then
    echo "Creating Container App..."
    az containerapp create \
      --name $CONTAINER_APP_NAME \
      --resource-group $RESOURCE_GROUP \
      --environment $CONTAINER_APP_ENV \
      --image $ACR_LOGIN_SERVER/presidio-pii:latest \
      --registry-server $ACR_LOGIN_SERVER \
      --registry-username $ACR_ADMIN_USER \
      --registry-password $ACR_ADMIN_PASSWORD \
      --target-port 80 \
      --ingress external
    handle_error $? "Container App creation"
    echo "Container App created, but it won't work until you push the image to ACR."
  fi
else
  echo "Skipping Docker build and deployment steps..."
fi

# Get the Container App URL
CONTAINER_APP_URL=$(az containerapp show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null)
if [ -n "$CONTAINER_APP_URL" ]; then
  echo "Container App deployed at: https://$CONTAINER_APP_URL"
  
  # Update the stored procedure to use the new endpoint URL
  echo "Updating stored procedure to use the new Container App endpoint..."
  NEW_ENDPOINT="https://$CONTAINER_APP_URL/analyze"
  
  # Use sed to replace the placeholder in the template file with the actual endpoint URL
  sed "s|{{ENDPOINT_URL}}|$NEW_ENDPOINT|g" db/update_endpoint_template.sql > db/update_endpoint.sql
  
  # Deploy the updated stored procedure
  sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/update_endpoint.sql
  handle_error $? "Updating stored procedure with new endpoint"
  
  echo "Endpoint URL successfully updated in the database to: $NEW_ENDPOINT"
fi

echo "Deployment completed!"