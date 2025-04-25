# Presidio PII ZA Identifier

This project provides a comprehensive solution for PII (Personally Identifiable Information) detection and anonymization, with a specific focus on South African ID numbers and credit card information. It leverages Microsoft's Presidio SDK for sensitive information detection and implements custom recognizers for South African ID validation.

## Project Overview

The application is designed to:
- Detect and anonymize South African ID numbers using a custom recognizer with Luhn checksum validation
- Identify and mask credit card numbers using Presidio's built-in recognizers
- Provide a REST API endpoint for text analysis
- Integrate with Azure SQL Database using triggers and stored procedures for automated anonymization
- Deploy as a containerized solution on Azure Container Apps (modern approach) or Azure Functions

## Architecture

![Architecture Diagram](https://via.placeholder.com/800x400?text=Presidio+PII+Architecture)

The system consists of the following components:

1. **Presidio PII Service (FastAPI Application)**:
   - Custom South African ID recognizer with validation logic
   - REST API endpoint for text analysis
   - Containerized with Docker

2. **Azure SQL Database**:
   - Tables for storing call center comments
   - Triggers for intercepting inserts and anonymizing PII
   - Stored procedures for communicating with the Presidio service

3. **Azure Container Apps / Azure Functions**:
   - Hosts the containerized Presidio service
   - Provides scalability and managed infrastructure
   - Exposes HTTP endpoints for text analysis

## Refactor Branch Improvements

The refactor branch includes several modernization improvements to the codebase:

### 1. Application Enhancements
- **Updated Dockerfile** (Latest Changes):
  - Upgraded to Python 3.11-slim (from 3.9)
  - Added non-root user for improved security
  - Optimized container build process
  - Added proper health check via curl commands
  - Separate layers for better caching and smaller image
  - Explicit port 8080 exposure for Container Apps integration
  
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
  
- **Container Apps Integration** (Latest Changes):
  - Added Application Insights integration for comprehensive monitoring
  - Improved container probes (startup, liveness, readiness) for better reliability
  - Proper resource allocation (1 CPU, 2GB memory) for SpaCy models
  - Enhanced autoscaling configuration based on concurrent requests
  - Secure registry integration with Azure Container Registry
  - Automated SQL endpoint updates through Bicep modules
  
- **Azure Functions Integration (Original)**:
  - Support for deploying as Azure Functions with `build_presidio.sh`
  - Configured Container Registry integration
  - Set up proper resource naming and organization

## Prerequisites

- Azure CLI (latest version)
- Docker Desktop (for local builds and testing)
- SQL Command Line Tools (sqlcmd)
- Git Bash or WSL (for running bash scripts on Windows)
- Azure Subscription with permissions to create resources

## Deployment Options

### Option 1: Deploy to Azure Container Apps (Recommended)

The modern approach using Azure Container Apps provides better scalability, security, and management:

```bash
# Run the deployment script
./deploy_to_container_apps.sh

# To deploy to existing infrastructure
./deploy_to_container_apps.sh -e
```

During the deployment process, you'll be prompted to provide:
- Azure region
- Resource group name
- SQL Server configuration
- Container App configuration
- Azure Container Registry details

### Option 2: Deploy to Azure Functions (Original)

The original deployment approach using Azure Functions:

```bash
# Run the deployment script
./build_presidio.sh

# To deploy to existing infrastructure
./build_presidio.sh -e
```

### Testing the Deployment

After deployment, you can verify the installation using:

```bash
# Verify database objects
./verify_db_objects.sh

# Test anonymization functionality
./run_test_anonymization.sh
```

## Workflow

1. When text containing PII (like South African ID numbers) is inserted into the database:
   - The database trigger intercepts the insertion
   - The trigger calls the stored procedure to send the text to the Presidio service
   - The service analyzes and anonymizes the text
   - The anonymized text is stored in the database

2. The Presidio service:
   - Detects South African IDs using custom pattern recognition and validation
   - Masks detected PII with placeholder characters
   - Returns the anonymized text preserving the original format

## Development and Testing

For local development:

1. Build and run the Docker container locally:
   ```bash
   cd app
   docker build -t presidio-pii:dev .
   docker run -p 8080:8080 presidio-pii:dev
   ```

2. Test the API endpoint:
   ```bash
   curl -X POST http://localhost:8080/analyze \
     -H "Content-Type: application/json" \
     -d '{"text": "Customer ID: 9010205584087"}'
   ```

3. Test container health:
   ```bash
   curl http://localhost:8080/health
   ```

## Azure Best Practices

This project follows Azure best practices including:

- Container-based deployment for isolation and scalability
- Proper error handling and logging with Application Insights
- Comprehensive health checks and container probes
- Non-root user in container for improved security
- Secure deployment with parameter-based configuration
- Auto-scaling based on concurrent requests
- Azure Container Registry with secure integration
- Database security with trigger-based anonymization
- Infrastructure as Code (Bicep) for consistent deployments

## Original Project Documentation

This project involves deploying a web application that uses the Presidio SDK for PII detection and anonymization of the South African ID number including being able to handle input errors using a custom class, secondary to this is the built-in recognizer to handle credit card numbers. The deployment process includes building a Docker image, pushing it to Azure Container Registry (ACR), deploying it to Azure App Service or Azure Container Apps, setting up an Azure SQL Database, and creating necessary stored procedures and triggers. 

Below are the key steps involved, please refer to the app and db folder for the artefacts as well as the deployment scripts for the az commands:

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

## License

This project is licensed under the MIT License - see the LICENSE file for details.
