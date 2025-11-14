# Authentication Comparison: Azure vs Self-Hosted Grafana

## 🎯 Quick Answer

**You have Azure Managed Grafana** → Use **Azure RBAC with OIDC** (no API keys needed)

**You have self-hosted Grafana** → Use **API keys** from Grafana UI

---

## Azure Managed Grafana (Your Setup)

### ✅ What You Need
- Azure App Registration with federated credential
- Service Principal with `Grafana Admin` role on Grafana resource
- GitHub secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `GRAFANA_URL`

### How It Works
```yaml
# Workflow authenticates to Azure via OIDC
- Azure Login (no password/secret needed)
- Get Grafana token: az account get-access-token --resource https://grafana.azure.com
- Deploy using Azure AD token
```

### Setup Guide
📖 **[AZURE_SETUP.md](AZURE_SETUP.md)** - Complete step-by-step instructions

### Where to Find Your Grafana URL
```bash
# Via Azure CLI
az grafana show \
  --name grafana-container-apps \
  --resource-group rg-grafana \
  --query properties.endpoint -o tsv

# Output: https://grafana-container-apps-abc123.eus.grafana.azure.com
```

Or from Azure Portal:
1. Go to your Grafana resource
2. Look for **"Endpoint"** in the Overview pane
3. Copy the full HTTPS URL

---

## Self-Hosted Grafana (Alternative)

### ✅ What You Need
- Grafana service account token (API key)
- GitHub secrets: `GRAFANA_URL`, `GRAFANA_API_KEY`

### How It Works
```yaml
# Workflow uses static API key
- Deploy using: Authorization: Bearer glsa_xxxxx
```

### Where to Get API Key
**Grafana UI:**
1. Configuration → Service Accounts
2. Add service account → Create token
3. Copy token (shown once)

**Azure CLI** (if Azure Managed Grafana supports it):
```bash
az grafana api-key create \
  --name github-actions \
  --key <workspace-name> \
  --resource-group <rg> \
  --role Editor
```

### Setup Guide
📖 **[SETUP_SECRETS.md](SETUP_SECRETS.md)** - API key configuration

---

## Side-by-Side Comparison

| Feature | Azure Managed Grafana | Self-Hosted Grafana |
|---------|----------------------|-------------------|
| **Authentication** | Azure RBAC + OIDC | API Keys |
| **Token Management** | Automatic (short-lived) | Manual rotation needed |
| **Security** | ✅ Federated identity | ⚠️ Long-lived secrets |
| **Setup Complexity** | Medium (Azure-specific) | Low (just API key) |
| **GitHub Secrets** | 4 secrets (Azure IDs) | 2 secrets (URL + key) |
| **Access Control** | Azure IAM roles | Grafana roles |
| **Audit Trail** | Azure Activity Log | Grafana audit logs |
| **Workflow Changes** | OIDC steps enabled | Use API key auth |

---

## 🔍 How to Identify Your Grafana Type

### You Have Azure Managed Grafana If:
- ✅ URL contains `.grafana.azure.com`
- ✅ Found under Azure Portal → "Azure Managed Grafana" service
- ✅ IAM roles shown in Access Control (screenshot you shared)
- ✅ No "Settings → API Keys" section in Grafana UI

### You Have Self-Hosted Grafana If:
- URL is your own domain (not `*.grafana.azure.com`)
- Running on your own infrastructure (VM, Docker, Kubernetes)
- "Configuration → API Keys" or "Service Accounts" available in UI

---

## 🚀 Quick Start for Your Setup (Azure Managed Grafana)

```bash
# 1. Create App Registration
APP_ID=$(az ad app create --display-name "github-grafana" --query appId -o tsv)

# 2. Configure federated credential
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-main",
  "subject": "repo:HenrikSkaanes/dashboards-with-grafana:ref:refs/heads/main",
  "issuer": "https://token.actions.githubusercontent.com",
  "audiences": ["api://AzureADTokenExchange"]
}'

# 3. Grant Grafana Admin role
GRAFANA_ID=$(az grafana show \
  --name grafana-container-apps \
  --resource-group rg-grafana \
  --query id -o tsv)

az role assignment create \
  --assignee $APP_ID \
  --role "Grafana Admin" \
  --scope $GRAFANA_ID

# 4. Set GitHub secrets
gh secret set AZURE_CLIENT_ID --body "$APP_ID"
gh secret set AZURE_TENANT_ID --body "$(az account show --query tenantId -o tsv)"
gh secret set AZURE_SUBSCRIPTION_ID --body "$(az account show --query id -o tsv)"
gh secret set GRAFANA_URL --body "$(az grafana show --name grafana-container-apps --resource-group rg-grafana --query properties.endpoint -o tsv)"
```

**✅ That's it! No API keys needed. The workflow is already configured for Azure OIDC.**

---

## 📚 Documentation Files

| File | Purpose |
|------|---------|
| **[AZURE_SETUP.md](AZURE_SETUP.md)** | ⭐ **Start here for Azure Managed Grafana** |
| [SETUP_SECRETS.md](SETUP_SECRETS.md) | For self-hosted Grafana with API keys |
| [README.md](README.md) | General dashboard workflow documentation |
| [QUICK_REFERENCE.md](QUICK_REFERENCE.md) | Copy-paste commands for daily use |

---

## ❓ Still Unsure?

Run this command to check your Grafana type:

```bash
# If this works, you have Azure Managed Grafana:
az grafana show \
  --name grafana-container-apps \
  --resource-group rg-grafana

# If command fails, you likely have self-hosted Grafana
```

Or check your Grafana URL in browser:
- `https://*.grafana.azure.com` → **Azure Managed** ✅
- Any other URL → Self-hosted

---

**🎯 For your setup (based on screenshot): Follow [AZURE_SETUP.md](AZURE_SETUP.md)**
