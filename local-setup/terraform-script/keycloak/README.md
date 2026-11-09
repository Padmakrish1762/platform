# CREDEBL Keycloak Terraform Configuration

This directory contains Terraform Infrastructure as Code (IaC) for automatically configuring Keycloak identity and access management for the CREDEBL platform.

## What It Does

The Terraform configuration automates the complete setup of Keycloak for CREDEBL, including:

### Identity Infrastructure Setup
- **Realm Creation**: Creates a dedicated `credebl-platform` realm for the application
- **Client Configuration**: Sets up clients
- **Role Management**: Defines and assigns roles for access control
- **Service Account Setup**: Configures service accounts for inter-service authentication
- **Security Configuration**: Implements proper token lifespans and session management

### Clients Created
1. **adminClient** - Administrative access for platform management
2. **credeblClient** - Main platform client for user authentication
3. **trustClient** - Client for trust-based operations

### Role-Based Access Control (RBAC)
- **Realm Roles**: `holder` role for credential holders
- **Trust Roles**: `trust-client-role` for trust-based operations

## Prerequisites

### Required Software
- **Terraform** (>= 1.0)
- **Keycloak Server** (running and accessible)
- **Network Access** to Keycloak admin endpoints

## Configuration Files

### Core Terraform Files

#### `terraform.tfvars`
Contains actual configuration values:
```hcl
realm = "credebl-platform"
access_token_lifespan = "48h"
sso_session_idle_timeout = "48h"
realm_role = "holder"
root_url = "http://localhost:8080"
redirect_url = "http://localhost:3000/*"
username = "admin"
password = "admin"
trust_client_role = "trust-client-role"
```

## Usage Instructions

### Initial Setup
1. **Modify terraform.tfvars:**

2. **Initialize Terraform:**
   ```bash
   terraform init
   ```

3. **Plan Deployment:**
   ```bash
   terraform plan
   ```

4. **Apply Configuration:**
   ```bash
   terraform apply
   ```

This Terraform configuration provides a robust, automated foundation for CREDEBL's identity and access management, ensuring secure and scalable authentication for the entire platform.