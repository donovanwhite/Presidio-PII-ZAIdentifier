@description('The name of the SQL Server')
param sqlServerName string

@description('The name of the SQL Database')
param sqlDatabaseName string

@description('The admin username for the SQL Server')
@secure()
param sqlAdminUsername string

@description('The admin password for the SQL Server')
@secure()
param sqlAdminPassword string

@description('The FQDN of the Container App')
param containerAppFqdn string

@description('The location for resources')
param location string = resourceGroup().location

// Get environment suffix for cloud agnostic deployment
var sqlServerHostName = environment().suffixes.sqlServerHostname

// Deploy a template deployment resource that executes T-SQL script
resource sqlScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'updateSqlEndpointScript'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.37.0'
    retentionInterval: 'P1D' // Retain the script resource for 1 day
    timeout: 'PT30M' // Timeout after 30 minutes
    environmentVariables: [
      {
        name: 'SQL_SERVER'
        value: sqlServerName
      }
      {
        name: 'SQL_DB'
        value: sqlDatabaseName
      }
      {
        name: 'SQL_USERNAME'
        secureValue: sqlAdminUsername
      }
      {
        name: 'SQL_PASSWORD'
        secureValue: sqlAdminPassword
      }
      {
        name: 'ENDPOINT_URL'
        value: 'https://${containerAppFqdn}/analyze'
      }
      {
        name: 'SQL_SERVER_SUFFIX'
        value: sqlServerHostName
      }
    ]
    scriptContent: '''
      #!/bin/bash
      
      # Install sqlcmd
      echo "Installing sqlcmd..."
      curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
      curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list > /etc/apt/sources.list.d/mssql-release.list
      apt-get update
      ACCEPT_EULA=Y apt-get install -y msodbcsql17 mssql-tools
      echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
      export PATH="$PATH:/opt/mssql-tools/bin"
      
      # Create SQL script file with updated endpoint
      cat > update_endpoint.sql << EOF
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
          DECLARE @url NVARCHAR(MAX) = '$ENDPOINT_URL';
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
      PRINT 'Stored procedure created/updated with endpoint: $ENDPOINT_URL';
      GO
      EOF
      
      # Replace variable placeholders with actual values
      sed -i "s|\$ENDPOINT_URL|${ENDPOINT_URL}|g" update_endpoint.sql
      
      # Execute SQL script
      echo "Updating SQL stored procedure with endpoint URL: ${ENDPOINT_URL}"
      /opt/mssql-tools/bin/sqlcmd -S ${SQL_SERVER}.${SQL_SERVER_SUFFIX} -d ${SQL_DB} -U ${SQL_USERNAME} -P ${SQL_PASSWORD} -i update_endpoint.sql -o output.txt
      
      # Check execution result
      if [ $? -ne 0 ]; then
        echo "Error updating SQL stored procedure. Details:"
        cat output.txt
        exit 1
      else
        echo "SQL stored procedure updated successfully!"
        cat output.txt
      fi

      # Add result to the deployment script output
      echo "{ \"result\": \"SQL procedure updated successfully with endpoint ${ENDPOINT_URL}\" }" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
  }
}

// Output the deployment status message using string interpolation instead of direct object reference
output scriptStatus string = 'SQL stored procedure updated with endpoint URL: https://${containerAppFqdn}/analyze'
