# Azure Managed Grafana Setup Guide

## 🎯 Azure Monitor Dashboards with Grafana Authentication

Azure Managed Grafana uses **Azure RBAC (Role-Based Access Control)** instead of traditional Grafana API keys. The workflow authenticates using Azure identity and obtains tokens dynamically.

## 📋 Required GitHub Secrets

Set these secrets in your GitHub repository (Settings → Secrets and variables → Actions):

### Core Secrets

| Secret Name | Description | Example Value |
|------------|-------------|---------------|
| `AZURE_CLIENT_ID` | App Registration Client ID | `12345678-1234-1234-1234-123456789abc` |
| `AZURE_TENANT_ID` | Azure AD Tenant ID | `87654321-4321-4321-4321-cba987654321` |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID | `abcdef12-3456-7890-abcd-ef1234567890` |
| `GRAFANA_URL` | Your Grafana endpoint | `https://grafana-container-apps-abc123.eus.grafana.azure.com` |

**Note:** `GRAFANA_API_KEY` is **NOT** required for Azure Managed Grafana with OIDC.

## 🔧 Complete Setup Steps

### Step 1: Create Azure App Registration

```bash
# Create app registration for GitHub Actions
APP_NAME="github-grafana-deploy"
APP_ID=$(az ad app create \
  --display-name "$APP_NAME" \
  --query appId -o tsv)

echo "✓ Created App Registration"
echo "  App ID (Client ID): $APP_ID"

# Create service principal
az ad sp create --id $APP_ID
echo "✓ Created Service Principal"
```

### Step 2: Configure Federated Identity Credential

```bash
# Set your GitHub organization and repository
GITHUB_ORG="HenrikSkaanes"
GITHUB_REPO="dashboards-with-grafana"

# Create federated credential for main branch
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-main-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':ref:refs/heads/main",
    "description": "GitHub Actions deployment from main branch",
    "audiences": ["api://AzureADTokenExchange"]
  }'

echo "✓ Created federated credential for: repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main"
```

### Step 3: Grant Grafana Permissions

```bash
# Set your Grafana resource details
GRAFANA_NAME="grafana-container-apps"
RESOURCE_GROUP="rg-grafana"

# Get Grafana resource ID
GRAFANA_ID=$(az grafana show \
  --name "$GRAFANA_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query id -o tsv)

echo "✓ Found Grafana: $GRAFANA_ID"

# Get service principal object ID
SP_OBJECT_ID=$(az ad sp show --id $APP_ID --query id -o tsv)

# Assign Grafana Admin role (use "Grafana Editor" for less permissions)
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Grafana Admin" \
  --scope "$GRAFANA_ID"

echo "✓ Granted 'Grafana Admin' role to service principal"
```

**Available Roles:**
- `Grafana Admin` - Full access (recommended for CI/CD)
- `Grafana Editor` - Create/edit dashboards
- `Grafana Viewer` - Read-only access

### Step 4: Get Azure IDs

```bash
# Get tenant and subscription IDs
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Get your Grafana URL from Azure Portal or CLI
GRAFANA_URL=$(az grafana show \
  --name "$GRAFANA_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.endpoint -o tsv)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Copy these values to GitHub Secrets:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "AZURE_CLIENT_ID:        $APP_ID"
echo "AZURE_TENANT_ID:        $TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID:  $SUBSCRIPTION_ID"
echo "GRAFANA_URL:            $GRAFANA_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

### Step 5: Configure GitHub Secrets

#### Option A: Via GitHub CLI

```bash
gh secret set AZURE_CLIENT_ID --body "$APP_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
gh secret set GRAFANA_URL --body "$GRAFANA_URL"

# Verify
gh secret list
```

#### Option B: Via GitHub Web UI

1. Go to your repository on GitHub
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **"New repository secret"**
4. Add each secret with the values from Step 4

### Step 6: Verify Setup

```bash
# Test Azure authentication locally
az login --service-principal \
  --username $APP_ID \
  --tenant $TENANT_ID \
  --password <create-a-client-secret-for-testing>

# Get Grafana access token (same as workflow does)
TOKEN=$(az account get-access-token \
  --resource https://grafana.azure.com \
  --query accessToken -o tsv)

# Test Grafana API access
curl -H "Authorization: Bearer $TOKEN" \
  "$GRAFANA_URL/api/org"

# Expected: JSON response with organization details
```

## 🔐 How Azure Authentication Works

### Traditional Grafana (Self-Hosted)
```bash
# Uses static API key
curl -H "Authorization: Bearer glsa_xxxxx" \
  https://grafana.example.com/api/dashboards/db
```

### Azure Managed Grafana (This Setup)
```bash
# 1. GitHub Actions obtains Azure AD token via OIDC
# 2. Exchanges token for Grafana-scoped token
TOKEN=$(az account get-access-token --resource https://grafana.azure.com --query accessToken -o tsv)

# 3. Uses Azure AD token for Grafana API
curl -H "Authorization: Bearer $TOKEN" \
  https://your-workspace.grafana.azure.com/api/dashboards/db
```

**Benefits:**
- ✅ No static API keys to rotate
- ✅ Azure RBAC controls access
- ✅ Audit via Azure Activity Log
- ✅ Works with Conditional Access policies
- ✅ Automatic token refresh

## 🎯 Updated Workflow Behavior

The GitHub Actions workflow now:

1. **Authenticates to Azure** using OIDC (no secrets/passwords)
2. **Obtains Grafana access token** via `az account get-access-token --resource https://grafana.azure.com`
3. **Deploys dashboards** using Azure AD token (not API key)

```yaml
# Workflow steps:
- Azure Login (OIDC) ✓
- Get Grafana Token ✓
- Deploy Dashboards ✓
```

## 🚨 Troubleshooting

### "Failed to get access token" error

**Cause:** Federated credential subject doesn't match  
**Fix:** Verify federated credential subject exactly matches:
```
repo:<GITHUB_ORG>/<GITHUB_REPO>:ref:refs/heads/main
```

```bash
# Check existing federated credentials
az ad app federated-credential list --id $APP_ID
```

### "Insufficient permissions" error

**Cause:** Service principal lacks Grafana role  
**Fix:** Verify role assignment:

```bash
# List role assignments on Grafana resource
az role assignment list \
  --scope $GRAFANA_ID \
  --assignee $APP_ID \
  --output table
```

Should show `Grafana Admin` or `Grafana Editor`.

### "401 Unauthorized" from Grafana API

**Cause:** Token scope incorrect  
**Fix:** Ensure token is for `https://grafana.azure.com` resource:

```bash
# Correct:
az account get-access-token --resource https://grafana.azure.com

# Incorrect (default Azure resource):
az account get-access-token  # ❌ Wrong scope
```

### "GRAFANA_URL not found" error

**Cause:** Grafana endpoint format incorrect  
**Fix:** Use full HTTPS URL from Azure Portal:

```bash
# Correct format:
https://grafana-container-apps-abc123.eus.grafana.azure.com

# Incorrect (missing https://):
grafana-container-apps-abc123.eus.grafana.azure.com  # ❌
```

## 📊 Access Token Details

```bash
# Decode your Grafana token (for debugging)
TOKEN=$(az account get-access-token --resource https://grafana.azure.com --query accessToken -o tsv)

# View token claims (install jwt-cli: npm install -g jwt-cli)
jwt decode $TOKEN

# Key claims:
# - aud: https://grafana.azure.com (resource)
# - iss: https://sts.windows.net/<tenant-id>/ (Azure AD)
# - appid: <your-app-registration-id>
# - roles: ["Grafana Admin"] (if using app roles)
```

## 🔄 Multi-Environment Setup

### Deploy to Different Grafana Instances

Create environment-specific federated credentials:

```bash
# Production (main branch)
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-prod",
  "subject": "repo:ORG/REPO:ref:refs/heads/main",
  "issuer": "https://token.actions.githubusercontent.com",
  "audiences": ["api://AzureADTokenExchange"]
}'

# Staging (staging branch)
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-staging",
  "subject": "repo:ORG/REPO:ref:refs/heads/staging",
  "issuer": "https://token.actions.githubusercontent.com",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

Use GitHub Environments to store different `GRAFANA_URL` per environment.

## 📚 Additional Resources

- [Azure Managed Grafana RBAC](https://learn.microsoft.com/azure/managed-grafana/how-to-share-grafana-workspace)
- [GitHub Actions OIDC with Azure](https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Azure Grafana API Access](https://learn.microsoft.com/azure/managed-grafana/how-to-api-calls)

## ✅ Quick Checklist

Before deploying:

- [ ] App Registration created with federated credential
- [ ] Service Principal has `Grafana Admin` role on Grafana resource
- [ ] Federated credential subject matches `repo:ORG/REPO:ref:refs/heads/main`
- [ ] All 4 GitHub secrets configured (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `GRAFANA_URL`)
- [ ] Test workflow triggered (create PR to validate)
- [ ] Verify deployment in Azure Activity Log

---

**🚀 Your Azure Managed Grafana deployment is now configured with secure OIDC authentication!**
