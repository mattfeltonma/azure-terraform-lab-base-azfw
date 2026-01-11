# API Management as an AI Gateway using Classic SKU APIM
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.8.3-blue)](https://www.terraform.io/)
[![Azure](https://img.shields.io/badge/Azure-Cloud-blue)](https://azure.microsoft.com/)

## Table of Contents
- [Updates](#updates)
- [TODOS](#TODOS)
- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment](#deployment)
- [Post-Deployment](#post-deployment)

## TODOS
  * 1/9/2026 Need to get list of required FQDNs through Azure Firewall

## Updates

### 2026
* **January 9th, 2026**
  * Added support for API Management v2 SKUs

### 2025

* **November 14th, 2025**
  * Initial release

## Overview
This Terraform code provisions an APIM (Azure API Management) into the base lab environment included in this repository to demonstrate the AI Gateway capabilities of APIM. It can deployed to one of the workload spokes using the Classic Developer or Premium SKUs deployed in [internal mode](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet). It can also be deployed using the [Premium v2 SKU in internal mode](https://learn.microsoft.com/en-us/azure/api-management/inject-vnet-v2). The base lab includes the necessary NSG (Network Security Group), routes, and Azure Firewall rules required for Classic internal mode API Management instances. Some of these rules and routes are unnecessary with the v2 SKU so ensure you check the latest documentation for specific requirements.

![AI Gateway Features](./images/lab-ai-gateway-features.svg)

## Architecture

The items pictured below in blue are deployed as part of this lab.

![Overall architecture](./images/lab-ai-gateway-architecture.svg)

### API Management Setup
APIs are created for the [2024-10-21 Azure OpenAI inferencing and authoring APIs](https://github.com/Azure/azure-rest-api-specs/tree/main/specification/cognitiveservices/OpenAI.Authoring) and the [Azure OpenAI v1 API](https://github.com/Azure/azure-rest-api-specs/blob/main/specification/ai/data-plane/OpenAI.v1/azure-v1-v1-generated.json). A sample APIM policy is deployed for each API with commonly used API policy snippets.

Two AI Foundry instances are deployed with the OpenAI 4o model. These are deployed to West US and East US 2. These instances are configured as backends for the APIs with circuit breaker logic. A pooled backend is created to contain these two backends. This configuration is used to demonstrate load balancing capabilities.

![APIM Resources](./images/lab-ai-gateway-apim-setup.svg)

### RBAC
Azure RBAC is configured so multiple types of authentication flows can be tested including authentication offloading, OAuth client credentials flow, and OAuth on-behalf-of.

![RBAC](./images/lab-ai-gateway-rbac.svg)

## Features

### Security
- **APIM in Internal Mode**: Traffic to and from APIM remains within virtual network
- **Entra ID Authentication**: APIM policy snippet is used to enforce Entra ID authentication to AI Foundry backends
- **Private Endpoints**: Private connectivity to PaaS services
- **Key Vault Integration**: APIM uses certificate sourced from Azure Key Vault for configuration of custom domains

### Network & Connectivity
- [Azure Firewall application and network rules](https://learn.microsoft.com/en-us/azure/api-management/virtual-network-reference) and [Network Security Groups](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet#configure-nsg-rules) security rules are pre-configured in the base lab to support internal mode APIM deployed to the snet-apim subnet in the workload virtual network. Reference those templates to see the required rules. Note that many of these rules are only required for Classic and not v2. Ensure you review the latest documentation if you want to establish a minimum set of rules.
- Access to the APIM instance is restricted to the virtual network. You should use the jump host from the base lab to interact with the instance.

### Monitoring & Logging
- **Azure Monitor Integration**: Logs and diagnostics are turned on for all resources and are set to an Azure Log Analytics Workspace.
- **Prompt and Response Logging**: [APIM prompt and response logging is enabled](https://journeyofthegeek.com/2025/05/27/generative-ai-in-azure-for-the-generalist-prompt-and-response-logging-with-api-management/)

## Prerequisites

### Azure Requirements
1. **Azure Subscription**: Active subscription with sufficient permissions
2. **Azure Permissions**: `Owner` role or equivalent delegated permissions for:
   - Resource group creation and management
   - Role assignment creation
   - Network resource provisioning

3. **Base Lab**: You must have already deployed the [base lab](../../README.md).

### V2 SKU Requirements
1. **Route Table** You will need to remove the user-defined route pointing to ApiManagement with next hop of Internet on the custom route table assigned to snet-apim in the workload virtual network.
2. **Subnet** You will need to delegate the snet-apim subnet to Microsoft.Web/hostingEnvironments.
3. **Azure Firewall** You can remove most of the Application and Network rules in the MyWorkloadApimRuleCollectionGroup and MyWorkloadApimRuleCollectionGroup Rule Collection Groups. My testing shows the egress firewall needs to support flows to Azure Monitor and Azure Key Vault. The [documentation states that Azure Storage is also required](https://learn.microsoft.com/en-us/azure/api-management/inject-vnet-v2#network-security-group). Need to confirm with Product Group.
4. **DNS** The V2 SKU requires the [custom domain you use to be a public DNS namespace](https://learn.microsoft.com/en-us/azure/api-management/configure-custom-domain?tabs=custom#limitation-for-custom-domain-name-in-v2-tiers). This means you'll need to create a split-brain DNS scenarios even for an internal mode APIM. You will also need to create a CNAME pointing to the out-of-the-box FQDN of the API Management to prove ownership.

### Local Development Environment
1. **Terraform**: Version 1.8.3 or higher
   ```bash
   terraform version
   ```

2. **Azure CLI**: Latest version recommended
   ```bash
   az version
   ```

3. **Git**: For cloning the repository
   ```bash
   git --version
   ```

### Required Information
Before deployment, gather the following:

1. **APIM DNS Namespace**: You must choose a custom DNS namespace for your APIM. This will be used to configure the custom domains for the APIM.

2. **Certificate in PFX format**: You must upload a certificate to the workload Key Vault that will be used to configure the [APIM custom domains](https://learn.microsoft.com/en-us/azure/api-management/configure-custom-domain?tabs=custom).

3. **Entra ID Tenant ID**: This is used by APIM policy to validate Entra ID access tokens sent to the AI Gateway.

4. **Service Principal Principal ID**: This is the principal id (object id) of the service principal you have already created. This will allow for testing of the client credentials flow.

5. **User Entra ID object ID**: This user is granted the Cognitive Services OpenAI User role on the AI Foundry instances to allow for testing on-behalf-of flows.

## Quick Start

### 1. Clone Repository
```bash
git clone <repository-url>
cd azure-terraform-lab-base-azfw/workloads/ai-gateway
```

### 2. Configure Variables
Copy the example configuration:
```bash
cp terraform.tfvars-example terraform.tfvars
```

Edit `terraform.tfvars` with your values. Ensure you read the description of the variables to understand the use. Many of these variables will draw from values of existing resources you delpoyed with the base lab.

### 3. Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Deploy with limited parallelism to avoid API limits. You can tweak this however you want.
terraform apply -parallelism=3
```

## Deployment

### Standard Deployment
For deployment:
```bash
terraform apply
```

## Post-Deployment

Once fully deployed you can use the [Jupyter notebook code sample](./sample-code/notebook.ipynb) provided in this repository. You need to manually import the authoring API for now. When I get around to it, I'll merge the two API specs.
