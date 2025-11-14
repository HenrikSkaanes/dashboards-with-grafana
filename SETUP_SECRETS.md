# Setup Instructions - GitHub Secrets

## Required GitHub Secrets

Your workflow requires these secrets to be configured in your GitHub repository.

### Quick Setup via GitHub CLI

```bash
# Install GitHub CLI if not already installed
# https://cli.github.com/

# Authenticate
gh auth login

# Set secrets (replace values with your actual credentials)
gh secret set GRAFANA_URL --body "https://your-workspace.grafana.azure.com"
gh secret set GRAFANA_API_KEY --body "glsa_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Verify secrets were set
gh secret list
```

### Setup via GitHub Web UI

1. Navigate to your repository on GitHub
2. Go to **Settings** → **Secrets and variables** → **Actions**
3. Click **"New repository secret"**
4. Add each secret:

#### GRAFANA_URL
- **Name**: `GRAFANA_URL`
- **Value**: Your Grafana instance URL
- **Example**: `https://my-workspace-abc123.grafana.azure.com`
- **Note**: No trailing slash

#### GRAFANA_API_KEY
- **Name**: `GRAFANA_API_KEY`
- **Value**: Your Grafana service account token
- **Example**: `glsa_1234567890abcdefghijklmnopqrstuvwxyz`
- **Note**: Keep this secure - it grants API access

## How to Generate a Grafana API Key

### Option 1: Azure CLI (Azure Managed Grafana)

```bash
# Create API key with Editor role (valid for 1 year)
az grafana api-key create \
  --name "github-actions-deploy" \
  --key <your-grafana-workspace-name> \
  --resource-group <your-resource-group> \
  --role Editor \
  --time-to-live 365d

# Output will include the API key - save it immediately!
# Example output:
# {
#   "key": "glsa_xxxxxxxxxxxxxx",
#   "name": "github-actions-deploy",
#   ...
# }
```

### Option 2: Grafana UI (Any Grafana Instance)

1. Log into your Grafana instance
2. Navigate to **Configuration** → **Service Accounts** (or **API Keys** in older versions)
3. Click **"Add service account"** (or **"Add API key"**)
4. Configure:
   - **Name**: `github-actions-deploy`
   - **Role**: `Editor` or `Admin`
   - **Expiration**: Set based on your rotation policy
5. Click **"Create"**
6. **Copy the generated key immediately** - it won't be shown again!
7. Save to GitHub secrets as shown above

## 🔐 OIDC Setup (Recommended for Production)

For enhanced security using Azure Managed Identity instead of static API keys:

### Step 1: Create Azure App Registration

```bash
# Create app registration
APP_ID=$(az ad app create \
  --display-name "GitHub-Grafana-Deploy" \
  --query appId -o tsv)

echo "Created App ID: $APP_ID"

# Create service principal
az ad sp create --id $APP_ID
```

### Step 2: Configure Federated Identity Credential

```bash
# Replace with your GitHub org/repo
GITHUB_ORG="your-org"
GITHUB_REPO="your-repo"

az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-main-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### Step 3: Grant Grafana Permissions

```bash
# Get Grafana resource ID
GRAFANA_ID=$(az grafana show \
  --name <your-grafana-workspace> \
  --resource-group <your-resource-group> \
  --query id -o tsv)

# Assign Grafana Admin role to app
az role assignment create \
  --assignee $APP_ID \
  --role "Grafana Admin" \
  --scope $GRAFANA_ID
```

### Step 4: Store Grafana API Key in Key Vault

```bash
# Create Key Vault (if you don't have one)
az keyvault create \
  --name <your-keyvault-name> \
  --resource-group <your-resource-group> \
  --location <your-location>

# Grant app access to Key Vault
az keyvault set-policy \
  --name <your-keyvault-name> \
  --object-id $(az ad sp show --id $APP_ID --query id -o tsv) \
  --secret-permissions get list

# Store Grafana API key in Key Vault
az keyvault secret set \
  --vault-name <your-keyvault-name> \
  --name grafana-api-key \
  --value "<your-grafana-api-key>"
```

### Step 5: Configure GitHub Secrets for OIDC

```bash
# Get tenant and subscription IDs
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Set GitHub secrets
gh secret set AZURE_CLIENT_ID --body "$APP_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
gh secret set AZURE_KEYVAULT_NAME --body "<your-keyvault-name>"

# Verify
gh secret list
```

### Step 6: Enable OIDC in Workflow

Edit `.github/workflows/deploy-manifest.yml` and:

1. Uncomment the `id-token: write` permission:
```yaml
permissions:
  id-token: write    # ← Uncomment this
  contents: read
```

2. Uncomment the Azure Login step:
```yaml
- name: Azure Login via OIDC
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

3. Uncomment the Key Vault retrieval step:
```yaml
- name: Get Grafana API Key from Azure Key Vault
  id: get-grafana-key
  run: |
    GRAFANA_API_KEY=$(az keyvault secret show \
      --vault-name ${{ secrets.AZURE_KEYVAULT_NAME }} \
      --name grafana-api-key \
      --query value -o tsv)
    echo "::add-mask::$GRAFANA_API_KEY"
    echo "GRAFANA_API_KEY=$GRAFANA_API_KEY" >> $GITHUB_OUTPUT
```

4. Update the deployment step to use OIDC credentials:
```yaml
env:
  GRAFANA_URL: ${{ secrets.GRAFANA_URL }}
  GRAFANA_API_KEY: ${{ steps.get-grafana-key.outputs.GRAFANA_API_KEY }}
```

## Verification

### Test Secret Configuration

```bash
# Test via GitHub CLI (won't show values, just confirms existence)
gh secret list

# Expected output:
# GRAFANA_URL         Updated YYYY-MM-DD
# GRAFANA_API_KEY     Updated YYYY-MM-DD
```

### Test Grafana Connection Locally

```bash
# Set environment variables
export GRAFANA_URL="https://your-workspace.grafana.azure.com"
export GRAFANA_API_KEY="your-api-key"

# Test connection
curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
  "$GRAFANA_URL/api/org"

# Expected output: JSON with organization details
# {"id":1,"name":"Main Org.","address":{...}}
```

### Test Full Workflow

```bash
# Make a small change to trigger workflow
echo "# Test change" >> README.md
git add README.md
git commit -m "Test: verify GitHub Actions secrets"
git push

# Monitor workflow
gh run watch
```

## 🔄 Secret Rotation Schedule

| Secret | Rotation Frequency | Method |
|--------|-------------------|--------|
| `GRAFANA_API_KEY` | Every 90 days | Regenerate in Grafana UI/CLI |
| `AZURE_CLIENT_ID` | Only if compromised | Recreate app registration |
| Key Vault secrets | Every 90 days | Update via `az keyvault secret set` |

## 📋 Checklist

- [ ] `GRAFANA_URL` configured in GitHub secrets
- [ ] `GRAFANA_API_KEY` configured in GitHub secrets
- [ ] API key has `Editor` or `Admin` role in Grafana
- [ ] Test connection successful
- [ ] Workflow runs without authentication errors
- [ ] (Optional) OIDC configured for enhanced security
- [ ] Secret rotation schedule documented
- [ ] Access permissions reviewed and restricted

## 🚨 Troubleshooting

### "GRAFANA_URL secret not set" error
- Verify secret name exactly matches `GRAFANA_URL` (case-sensitive)
- Ensure URL has no trailing slash
- Check secret is set at repository level (not organization)

### "GRAFANA_API_KEY secret not set" error
- Verify secret name exactly matches `GRAFANA_API_KEY`
- Ensure API key is valid and not expired
- Check API key has sufficient permissions

### "401 Unauthorized" from Grafana API
- API key may be expired - generate a new one
- API key may lack permissions - ensure `Editor` or `Admin` role
- Verify GRAFANA_URL is correct and accessible

### OIDC "Failed to login" error
- Check federated credential `subject` matches your repo exactly
- Verify app has `Grafana Admin` role assignment
- Ensure Key Vault access policy is configured

---

**✅ Once secrets are configured, your CI/CD pipeline is ready to deploy!**
