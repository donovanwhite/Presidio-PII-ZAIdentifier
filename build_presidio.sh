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

# If DEPLOY_EXISTING is false, print message indicating we're creating new infrastructure
if [ "$DEPLOY_EXISTING" = false ]; then
  echo "Creating new infrastructure..."
fi

# Set default values
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP="presidio-test-rg"
DEFAULT_SQL_SERVER_NAME="presidio-test-sql-server"
DEFAULT_SQL_DB_NAME="presidio-test-db"
DEFAULT_SQL_ADMIN_USER="sqladmin"
DEFAULT_SQL_ADMIN_PASSWORD="P@ssw0rd1234"
DEFAULT_FUNCTION_APP_NAME="presidio-test-function-app"
DEFAULT_ACR_NAME="presidiotestacr"
DEFAULT_STORAGE_ACCOUNT="presidioteststorage"

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

read -p "Enter Function App name [$DEFAULT_FUNCTION_APP_NAME]: " FUNCTION_APP_NAME_INPUT
FUNCTION_APP_NAME=${FUNCTION_APP_NAME_INPUT:-$DEFAULT_FUNCTION_APP_NAME}

read -p "Enter Azure Container Registry name [$DEFAULT_ACR_NAME]: " ACR_NAME_INPUT
ACR_NAME=${ACR_NAME_INPUT:-$DEFAULT_ACR_NAME}

read -p "Enter Storage Account name for Function App [$DEFAULT_STORAGE_ACCOUNT]: " STORAGE_ACCOUNT_INPUT
STORAGE_ACCOUNT=${STORAGE_ACCOUNT_INPUT:-$DEFAULT_STORAGE_ACCOUNT}

# Display configuration summary
echo "====== Deployment Configuration Summary ======"
echo "Region: $LOCATION"
echo "Resource Group: $RESOURCE_GROUP"
echo "SQL Server: $SQL_SERVER_NAME"
echo "SQL Database: $SQL_DB_NAME"
echo "SQL Admin Username: $SQL_ADMIN_USER"
echo "Function App: $FUNCTION_APP_NAME"
echo "Azure Container Registry: $ACR_NAME"
echo "Storage Account: $STORAGE_ACCOUNT"
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

  # Create Azure Container Registry regardless of Docker availability
  echo "Creating Azure Container Registry..."
  az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic
  handle_error $? "Azure Container Registry creation"

  # Create Storage Account for Function App
  echo "Creating storage account for Function App..."
  az storage account create --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --location $LOCATION --sku Standard_LRS --kind StorageV2
  handle_error $? "Storage Account creation"

  # Create Azure Function App with Docker Container
  echo "Creating Function App..."
  az functionapp create --resource-group $RESOURCE_GROUP --consumption-plan-location $LOCATION --name $FUNCTION_APP_NAME --storage-account $STORAGE_ACCOUNT --runtime python --functions-version 4 --os-type Linux
  handle_error $? "Function App creation"
fi

# Deploy SQL scripts to the database - first create tables, then insert data, then other scripts
echo "Deploying database tables..."
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/create_tbl.sql
handle_error $? "Database table creation"

echo "Inserting dummy data..."
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/insert_dummy_data.sql
handle_error $? "Database data insertion"

echo "Deploying other database scripts..."
for script in db/trg_before_insert.sql db/usp_call_rest_endpoint.sql db/usp_insert_comments.sql; do
  echo "Deploying $script..."
  sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i $script
  handle_error $? "Deployment of $script"
done

# Handle Docker-related steps
if [ "$SKIP_DOCKER_STEPS" = false ]; then
  # Build and Push Docker Image to ACR using Docker
  echo "Building Docker image..."
  docker build --no-cache -t $ACR_NAME.azurecr.io/presidio-pii:latest ./app
  handle_error $? "Docker image build"
  
  echo "Logging in to Azure Container Registry..."
  az acr login --name $ACR_NAME
  handle_error $? "ACR login"
  
  echo "Pushing Docker image to ACR..."
  docker push $ACR_NAME.azurecr.io/presidio-pii:latest
  handle_error $? "Docker image push"

  # Configure Function App to use the container
  echo "Configuring Function App to use container..."
  az functionapp config container set --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --docker-custom-image-name $ACR_NAME.azurecr.io/presidio-pii:latest
  handle_error $? "Function App container configuration"
  
elif [ "$USE_ACR_TOKEN" = true ]; then
  # Token-based authentication flow without requiring Docker
  echo "Using token-based authentication to ACR..."
  
  # Get ACR login server
  ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv)
  handle_error $? "Retrieving ACR login server"
  
  echo "ACR Login Server: $ACR_LOGIN_SERVER"
  
  # Get access token for ACR (without requiring Docker)
  echo "Getting ACR access token..."
  TOKEN_RESPONSE=$(az acr login --name $ACR_NAME --expose-token --output json)
  handle_error $? "Getting ACR access token"
  
  # Extract token from response
  ACR_TOKEN=$(echo $TOKEN_RESPONSE | grep -o '"accessToken": "[^"]*' | grep -o '[^"]*$')
  ACR_TOKEN_EXPIRY=$(echo $TOKEN_RESPONSE | grep -o '"expiresIn": [0-9]*' | grep -o '[0-9]*')
  
  echo "Successfully retrieved ACR token. Token expires in $ACR_TOKEN_EXPIRY seconds."
  
  # Instructions for manual image push (since we can't do it without Docker)
  echo "====== Manual Image Push Instructions ======"
  echo "Since Docker is not available, you'll need to manually push your container image."
  echo "Use these credentials on a machine with Docker installed:"
  echo ""
  echo "1. Build your image: docker build -t $ACR_LOGIN_SERVER/presidio-pii:latest ./app"
  echo "2. Log in using token: docker login $ACR_LOGIN_SERVER --username 00000000-0000-0000-0000-000000000000 --password $ACR_TOKEN"
  echo "3. Push your image: docker push $ACR_LOGIN_SERVER/presidio-pii:latest"
  echo "============================================"
  
  # Save token and instructions to a file for later use
  echo "# ACR Token for $ACR_NAME" > acr_token_instructions.txt
  echo "ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER" >> acr_token_instructions.txt
  echo "ACR_USERNAME=00000000-0000-0000-0000-000000000000" >> acr_token_instructions.txt
  echo "ACR_TOKEN=$ACR_TOKEN" >> acr_token_instructions.txt
  echo "TOKEN_EXPIRY_SECONDS=$ACR_TOKEN_EXPIRY" >> acr_token_instructions.txt
  echo "" >> acr_token_instructions.txt
  echo "# Instructions:" >> acr_token_instructions.txt
  echo "# 1. Build your image: docker build -t $ACR_LOGIN_SERVER/presidio-pii:latest ./app" >> acr_token_instructions.txt
  echo "# 2. Log in using token: docker login $ACR_LOGIN_SERVER --username 00000000-0000-0000-0000-000000000000 --password $ACR_TOKEN" >> acr_token_instructions.txt
  echo "# 3. Push your image: docker push $ACR_LOGIN_SERVER/presidio-pii:latest" >> acr_token_instructions.txt
  
  echo "Token and instructions saved to acr_token_instructions.txt"
  
  echo "Would you like to configure the Function App with the container image URL even though the image hasn't been pushed yet?"
  read -p "Configure Function App with container image URL? (y/n): " CONFIGURE_FUNCTION_APP
  if [[ $CONFIGURE_FUNCTION_APP == "y" || $CONFIGURE_FUNCTION_APP == "Y" ]]; then
    echo "Configuring Function App to use container..."
    az functionapp config container set --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --docker-custom-image-name $ACR_LOGIN_SERVER/presidio-pii:latest
    handle_error $? "Function App container configuration"
    echo "Function App configured, but it won't work until you push the image to ACR."
  fi
else
  echo "Skipping Docker build and deployment steps..."
fi

# Test the Function App Endpoint
FUNCTION_APP_URL=$(az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --query defaultHostName -o tsv)
echo "Function App deployed at: https://$FUNCTION_APP_URL"
echo "Deployment completed!"
