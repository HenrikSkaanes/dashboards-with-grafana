# Grafana Dashboard Deployment - Quick Reference

## 🎯 Copy-Paste Commands

### Initial Repository Setup
```bash
# Clone and navigate
git clone <your-repo-url>
cd dashboards-with-grafana

# Verify structure
ls -R dashboards/
cat active-manifest.json
```

### Configure GitHub Secrets (Required)
```bash
# Set via GitHub CLI
gh secret set GRAFANA_URL --body "https://your-workspace.grafana.azure.com"
gh secret set GRAFANA_API_KEY --body "your-api-key-here"

# Or via UI: Settings → Secrets and variables → Actions → New repository secret
```

### Create Dashboard API Key (Azure CLI)
```bash
# For Azure Managed Grafana
az grafana api-key create \
  --name "github-actions-deploy" \
  --key <grafana-workspace-name> \
  --resource-group <resource-group> \
  --role Editor \
  --time-to-live 365d
```

### Test Locally (Optional)
```bash
# Validate manifest JSON
jq empty active-manifest.json && echo "✓ Valid"

# Validate all dashboards
jq -r '.dashboards[].path' active-manifest.json | while read path; do
  jq empty "$path" && echo "✓ $path valid"
done

# Test API connection
curl -H "Authorization: Bearer $GRAFANA_API_KEY" \
  "$GRAFANA_URL/api/org"
```

## 🔄 Common Operations

### Deploy New Dashboard Version
```bash
# 1. Create new version file
cp dashboards/my-dash/v1.0.json dashboards/my-dash/v1.1.json
# Edit v1.1.json with changes

# 2. Update manifest
jq '.dashboards[] |= if .uid == "my-dash-uid" then .path = "dashboards/my-dash/v1.1.json" | .version = "v1.1" else . end' \
  active-manifest.json > tmp.json && mv tmp.json active-manifest.json

# 3. Commit and push
git add dashboards/my-dash/v1.1.json active-manifest.json
git commit -m "Deploy my-dash v1.1"
git push
```

### Rollback to Previous Version
```bash
# Change manifest path only
jq '.dashboards[] |= if .uid == "my-dash-uid" then .path = "dashboards/my-dash/v1.0.json" | .version = "v1.0" else . end' \
  active-manifest.json > tmp.json && mv tmp.json active-manifest.json

git commit -am "Rollback my-dash to v1.0"
git push
```

### Add Brand New Dashboard
```bash
# 1. Export from Grafana UI (Share → Export → Save JSON)
# 2. Save to dashboards/new-dash/v1.0.json

# 3. Add to manifest
jq '.dashboards += [{
  "uid": "new-dash-uid",
  "path": "dashboards/new-dash/v1.0.json",
  "folder": "Production",
  "version": "v1.0"
}]' active-manifest.json > tmp.json && mv tmp.json active-manifest.json

git add dashboards/new-dash/v1.0.json active-manifest.json
git commit -m "Add new-dash v1.0"
git push
```

## 🔍 Validation Commands

### Check UID Consistency
```bash
jq -r '.dashboards[] | "\(.uid)|\(.path)"' active-manifest.json | while IFS='|' read uid path; do
  file_uid=$(jq -r '.dashboard.uid' "$path")
  if [ "$uid" != "$file_uid" ]; then
    echo "❌ UID mismatch: $path (manifest=$uid, file=$file_uid)"
  else
    echo "✓ $path"
  fi
done
```

### List All Deployed Dashboards
```bash
jq -r '.dashboards[] | "\(.uid) → \(.path) (\(.version)) → \(.folder)"' active-manifest.json
```

### Check Dashboard Exists in Grafana
```bash
DASHBOARD_UID="your-dashboard-uid"
curl -s -H "Authorization: Bearer $GRAFANA_API_KEY" \
  "$GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID" | jq '.meta'
```

## 🛠️ OIDC Setup (Recommended for Production)

### 1. Create Azure App Registration
```bash
az ad app create --display-name "GitHub-Grafana-Deploy"
az ad sp create --id <app-id>
```

### 2. Configure Federated Credential
```bash
az ad app federated-credential create \
  --id <app-id> \
  --parameters '{
    "name": "github-main-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR-ORG/YOUR-REPO:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### 3. Grant Grafana Permissions
```bash
az grafana update \
  --name <grafana-workspace> \
  --resource-group <rg> \
  --service-account <app-id>:Editor
```

### 4. Store API Key in Key Vault
```bash
az keyvault create --name <vault-name> --resource-group <rg>
az keyvault secret set \
  --vault-name <vault-name> \
  --name grafana-api-key \
  --value "<your-grafana-api-key>"
```

### 5. Uncomment OIDC Steps in Workflow
Edit `.github/workflows/deploy-manifest.yml` and uncomment:
- `id-token: write` permission
- Azure Login step
- Key Vault retrieval step

## 📊 Manifest JSON Schema Reference

```json
{
  "version": "1.0",
  "dashboards": [
    {
      "uid": "string (1-40 chars, alphanumeric + _ -)",
      "path": "string (must start with dashboards/)",
      "folder": "string (Grafana folder name or 'General')",
      "version": "string (optional, for docs)"
    }
  ]
}
```

## 🚨 Emergency Procedures

### Disable All Deployments
```bash
# Remove all dashboards from manifest temporarily
jq '.dashboards = []' active-manifest.json > tmp.json && mv tmp.json active-manifest.json
git commit -am "Emergency: disable all deployments"
git push
```

### Force Redeploy (No Changes)
```bash
# Trigger workflow manually
gh workflow run deploy-manifest.yml --ref main

# Or make empty commit
git commit --allow-empty -m "Redeploy all dashboards"
git push
```

### Export Current Live Dashboard
```bash
DASHBOARD_UID="your-dashboard-uid"
curl -s -H "Authorization: Bearer $GRAFANA_API_KEY" \
  "$GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID" \
  | jq '.dashboard' > backup-$(date +%Y%m%d-%H%M%S).json
```

## 📞 Support

**CI Failures**: Check Actions tab → failed workflow → step logs  
**UID Errors**: Run local validation commands above  
**Auth Issues**: Verify secrets are set correctly in repository settings  
**OIDC Issues**: Check Azure App Registration federated credentials and permissions
