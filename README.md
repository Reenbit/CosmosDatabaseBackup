# Reenbit.CosmosDBBackup
This repository contains a set of PowerShell and ARM template scripts for deploying resources on Azure for automatic backups of Cosmos Database. 
Also, it contains ARM templates for creating simple web application with with service plan, key vault and application insights. That web app using Cosmos databse for storing simple documents.
Note: web application divided into two applications one for UI and another one for API and they both deployed to the same service plan.

## Project Architecture
![Project Architecture](/Images/projarch.png)


## Technology stack
ASP.NET Core, Azure Cosmos DB, Azure Data Factory, Azure Key Vault, Azure Application Insights.

## Demo

- ### To deploy application with backup we need to run CosmosDbBackup/Deploy-App.ps1 PowerShell script with provided parameters:
        1 AadAdmin - Active Directory admin user name
        2 AadPassword - Active Directory admin AadPassword
        3 ResourceGroupLocation - Azure region where all resources will be deployed
        4 ResourceGroupName - Azure resource group name to contains all resources
        5 ResourceNamePrefix - prefix which be added to resource names (could be used to separate environments - testing, staging, prod etc.)
        6 TemplateFile - main template file name where all resources added (default value - 'azuredeploy.json') 
        7 IsDevelopment - parameter to separate whether that's DEV (dev, staging, etc) or Prod (default value - 'true')
        8 CosmosDbName - name of Cosmos database 
        9 CosmosDbDefaultRu - count of request units for Cosmos Database (default value - 400)
        10 AppServicePlanSKUTier - name of pricing tier for Azure App service plan
        11 AppServicePlanSKUName - name of SKU of pricing tier for Azure App service plan

- ### Backup solution architecture 
  ![Backup solution](/Images/solutionarch.png)
 
## Notes
After successful deploy of CosmosDbBackup/Deploy-App.ps1 script Azure resource group will be deployed with all resources.
Azure Data Factory will be deployed and default trigger will be added for running backup of Cosmos database's documents. 
All documents are storing to Azure Blob storage.
