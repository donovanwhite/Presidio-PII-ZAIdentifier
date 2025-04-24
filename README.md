# Presidio PII ZA Identifier

This project involves deploying a web application that uses the Presidio SDK for PII detection and anonymization of the South African ID number including being able to handle input errors using a custom class, secondary to this is the built-in recognizer to handle credit card numbers.

## Refactor Branch Improvements

The refactor branch includes several modernization improvements to the codebase:

### 1. Application Enhancements
- **Updated Dockerfile**:
  - Upgraded to Python 3.11-slim (from 3.9)
  - Added non-root user for improved security
  - Optimized container build process
  
- **Improved Python Application**:
  - Added proper logging for better observability
  - Implemented comprehensive type hints for better code quality
  - Enhanced error handling with detailed logging
  
- **Development Environment**:
  - Added development dependencies (pytest, black, isort, mypy) to requirements.txt

### 2. Database Enhancements
- **Added sample data script**: Created `insert_dummy_data.sql` with realistic South African ID numbers
- **Modified database setup**: Structured deployment steps to ensure proper sequencing of scripts execution

### 3. Deployment Improvements
- **Modernized build script**:
  - Added prerequisite checks for Azure CLI and Docker
  - Added `-e` flag to toggle between creating new infrastructure or deploying to existing infrastructure
  - Improved deployment organization with clear steps and verbose output
  
- **Azure Functions Integration**:
  - Added support for deploying as Azure Functions
  - Configured Container Registry integration
  - Set up proper resource naming and organization

## Original Project Documentation

This project involves deploying a web application that uses the Presidio SDK for PII detection and anonymization of the South Africa African ID number including being able to handle input errors using a custom class, secondary to this is the builtin recognizer to handle credit card numbers. The deployment process includes building a Docker image, pushing it to Azure Container Registry (ACR), deploying it to Azure App Service, setting up an Azure SQL Database, and creating necessary stored procedures and triggers. 

Below are the key steps involved, please refer to the app and db folder for the artefacts as well as the build_presidio.sh for the az commands:

### 1. Azure Container Registry (ACR) Setup
- Login to ACR: Authenticate to the Azure Container Registry using the az acr login command.
- Build and Push Docker Image: Build the Docker image with the application, tag it, and push it to ACR.

### 2. Azure Resource Setup
- Create Resource Group and App Service Plan: Use the az group create and az appservice plan create commands to set up the necessary Azure resources.
- Create Managed Identity: Create a managed identity to handle permissions for pulling images from ACR.

### 3. Permissions and Role Assignments
- Grant ACR Pull Permissions: Assign the "AcrPull" role to the managed identity to allow it to pull images from ACR.

### 4. Azure SQL Database Setup
- Create SQL Server and Database: Use the az sql server create and az sql db create commands to set up the SQL Server and Database.
- Configure Firewall Rules: Set up firewall rules to allow access to the SQL Server.
- Create Table: Define and create the callcentre_comments table (SQL code available in the repository).
- Create Stored Procedures: Define and create the necessary stored procedures in the database (SQL code available in the repository).
- Create Trigger: Define and create the trigger to handle PII anonymization before inserting data (SQL code available in the repository).

### 5. Deploy Web Application
- Create Web App: Deploy the web application using the az webapp create command, specifying the Docker image from ACR.
- Update Web App Configuration: Update the web app configuration to use the latest Docker image version.

### 6. Testing the Deployment
- Test Endpoints: Use curl commands to test the web application's endpoints and ensure it correctly detects and anonymizes PII.
