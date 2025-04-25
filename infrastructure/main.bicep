@description('The location where all resources will be deployed')
param location string = resourceGroup().location

@description('The name of the Container App')
param containerAppName string = 'presidio-pii-app'

@description('The name of the Container App Environment')
param containerAppEnvName string = 'presidio-env'

@description('The name of the Azure Container Registry')
param acrName string = 'presidiotestacr'

@description('The name of the SQL Server')
param sqlServerName string = 'presidio-test-sql-server'

@description('The name of the SQL Database')
param sqlDbName string = 'presidio-test-db'

@description('The admin username for the SQL Server')
@secure()
param sqlAdminUser string

@description('The admin password for the SQL Server')
@secure()
param sqlAdminPassword string

@description('The name of the Application Insights instance')
param appInsightsName string = 'presidio-insights'

// Reference existing ACR
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// Reference existing Container App Environment
resource environment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: containerAppEnvName
}

// Create Log Analytics workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${appInsightsName}-workspace'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Create Application Insights for monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Container App with proper health probe and resource settings
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        transport: 'http'
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: '${acrName}.azurecr.io'
          username: acr.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name: 'acr-password'
          value: acr.listCredentials().passwords[0].value
        }
        {
          name: 'appinsights-connection-string'
          value: appInsights.properties.ConnectionString
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerAppName
          image: '${acrName}.azurecr.io/presidio-pii:latest'
          resources: {
            // Increase CPU and memory resources to accommodate the spacy model
            cpu: 1
            memory: '2Gi'
          }
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection-string'
            }
          ]
          // Configure proper probes
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: 80
              }
              initialDelaySeconds: 30
              periodSeconds: 15
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 80
              }
              initialDelaySeconds: 30
              periodSeconds: 15
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 80
              }
              initialDelaySeconds: 15
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
        rules: [
          {
            name: 'http-rule'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

// Update the SQL Stored Procedure with the Container App endpoint
module updateSqlEndpoint 'modules/sqlscript.bicep' = {
  name: 'update-sql-endpoint'
  params: {
    sqlServerName: sqlServerName
    sqlDatabaseName: sqlDbName
    sqlAdminUsername: sqlAdminUser
    sqlAdminPassword: sqlAdminPassword
    containerAppFqdn: containerApp.properties.configuration.ingress.fqdn
    location: location
  }
}

// Output the Container App endpoint and Application Insights instrumentation key
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output applicationInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
