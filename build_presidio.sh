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
    exit
fi

# Add a switch to determine whether to deploy to existing infrastructure or create new
while getopts "e" opt; do
  case $opt in
    e)
      echo "Deploying to existing infrastructure..."
      DEPLOY_EXISTING=true
      ;;
    *)
      echo "Creating new infrastructure..."
      DEPLOY_EXISTING=false
      ;;
  esac
done

# Set variables for Azure resources
RESOURCE_GROUP="presidio-test-rg"
LOCATION="eastus"
SQL_SERVER_NAME="presidio-test-sql-server"
SQL_DB_NAME="presidio-test-db"
SQL_ADMIN_USER="sqladmin"
SQL_ADMIN_PASSWORD="P@ssw0rd1234"
FUNCTION_APP_NAME="presidio-test-function-app"
ACR_NAME="presidiotestacr"

if [ "$DEPLOY_EXISTING" = false ]; then
  # Create Resource Group
  az group create --name $RESOURCE_GROUP --location $LOCATION

  # Create Azure SQL Server and Database
  az sql server create --name $SQL_SERVER_NAME --resource-group $RESOURCE_GROUP --location $LOCATION --admin-user $SQL_ADMIN_USER --admin-password $SQL_ADMIN_PASSWORD
  az sql db create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name $SQL_DB_NAME --service-objective S0

  # Configure Firewall Rules for Azure SQL Server
  az sql server firewall-rule create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name AllowYourIP --start-ip-address $(curl -s ifconfig.me) --end-ip-address $(curl -s ifconfig.me)

  # Create Azure Container Registry
  az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic

  # Create Azure Function App with Docker Container
  az functionapp create --resource-group $RESOURCE_GROUP --consumption-plan-location $LOCATION --name $FUNCTION_APP_NAME --storage-account $ACR_NAME --deployment-container-image-name $ACR_NAME.azurecr.io/presidio-pii:latest
fi

# Deploy SQL scripts to the database - first create tables, then insert data, then other scripts
echo "Deploying database tables..."
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/create_tbl.sql

echo "Inserting dummy data..."
sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i db/insert_dummy_data.sql

echo "Deploying other database scripts..."
for script in db/trg_before_insert.sql db/usp_call_rest_endpoint.sql db/usp_insert_comments.sql; do
  echo "Deploying $script..."
  sqlcmd -S tcp:$SQL_SERVER_NAME.database.windows.net -d $SQL_DB_NAME -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASSWORD -i $script
done

# Build and Push Docker Image to ACR
docker build --no-cache -t $ACR_NAME.azurecr.io/presidio-pii:latest ./app
az acr login --name $ACR_NAME
docker push $ACR_NAME.azurecr.io/presidio-pii:latest

# Configure Function App to use the container
az functionapp config container set --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --docker-custom-image-name $ACR_NAME.azurecr.io/presidio-pii:latest

# Test the Function App Endpoint
FUNCTION_APP_URL=$(az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --query defaultHostName -o tsv)
echo "Function App deployed at: https://$FUNCTION_APP_URL"
