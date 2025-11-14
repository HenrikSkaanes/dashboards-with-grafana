# Grafana Dashboards as Code

**Version-controlled Grafana dashboards with manifest-based deployment for Azure "Dashboards with Grafana" preview.**

## 📁 Repository Structure

```
dashboards-with-grafana/
├── .github/
│   └── workflows/
│       └── deploy-manifest.yml       # CI/CD pipeline
├── dashboards/
│   ├── service-health/
│   │   ├── v1.1.json                 # Older version (preserved)
│   │   └── v1.2.json                 # Current version
│   └── api-performance/
│       └── v2.0.json
├── active-manifest.json              # Controls which versions deploy
└── manifest-schema.json              # JSON schema for validation
```

## 🚀 Quick Start

### 1. Configure GitHub Secrets

Add these secrets to your repository (Settings → Secrets and variables → Actions):

**For Azure Managed Grafana (Recommended):**
- `AZURE_CLIENT_ID` - App Registration client ID
- `AZURE_TENANT_ID` - Azure tenant ID  
- `AZURE_SUBSCRIPTION_ID` - Azure subscription ID
- `GRAFANA_URL` - Your Grafana instance URL (e.g., `https://grafana-workspace-abc.eus.grafana.azure.com`)

**Authentication:** Uses Azure OIDC (no API keys required). See **[AZURE_SETUP.md](AZURE_SETUP.md)** for complete setup.

**For Self-Hosted Grafana (Alternative):**
- `GRAFANA_URL` - Your Grafana instance URL
- `GRAFANA_API_KEY` - Service account token with Editor/Admin permissions

See **[SETUP_SECRETS.md](SETUP_SECRETS.md)** for detailed configuration steps.

### 2. Initial Setup for Azure Managed Grafana

```bash
# Create App Registration
az ad app create --display-name "github-grafana-deploy"

# Configure federated credential for OIDC
az ad app federated-credential create --id <app-id> --parameters '{
  "name": "github-main",
  "subject": "repo:YOUR-ORG/YOUR-REPO:ref:refs/heads/main",
  "issuer": "https://token.actions.githubusercontent.com",
  "audiences": ["api://AzureADTokenExchange"]
}'

# Grant Grafana Admin role
az role assignment create \
  --assignee <app-id> \
  --role "Grafana Admin" \
  --scope <grafana-resource-id>

# See AZURE_SETUP.md for complete step-by-step guide
```

## 🔄 Developer Workflow: Switching Dashboard Versions

### Scenario: Roll back service-health dashboard from v1.2 to v1.1

1. **Edit the manifest** to point to the target version:
   ```bash
   # Edit active-manifest.json
   # Change: "path": "dashboards/service-health/v1.2.json"
   # To:     "path": "dashboards/service-health/v1.1.json"
   ```

2. **Create a PR** with the manifest change:
   ```bash
   git checkout -b rollback-service-health-v1.1
   git add active-manifest.json
   git commit -m "Rollback service-health dashboard to v1.1"
   git push origin rollback-service-health-v1.1
   ```

3. **CI validation runs automatically** - validates JSON structure, UIDs, and paths

4. **Review the PR** - GitHub bot comments with deployment preview showing exactly what will deploy

5. **Merge to deploy** - Dashboard automatically deploys to Grafana on merge to `main`

6. **Verify in Grafana** - Check the deployed dashboard at the URL shown in CI logs

### Adding a New Dashboard Version

1. **Export current dashboard** from Grafana UI (Share → Export → Save JSON)
2. **Save as new version** in `dashboards/your-dashboard/vX.Y.json`
3. **Update manifest** to reference new version
4. **Open PR** → CI validates → Merge to deploy

## 📋 Manifest File Format

### active-manifest.json Schema

```json
{
  "version": "1.0",
  "dashboards": [
    {
      "uid": "unique-dashboard-id",
      "path": "dashboards/folder-name/vX.Y.json",
      "folder": "Production",
      "version": "vX.Y"
    }
  ]
}
```

**Fields:**
- `uid` - Grafana dashboard unique ID (must match `dashboard.uid` in JSON file)
- `path` - Relative path from repo root to dashboard JSON
- `folder` - Grafana folder name (use `"General"` for root folder)
- `version` - Human-readable label (optional, for documentation)

### Important: UID Consistency

The **same `uid`** across versions ensures deployment overwrites the existing dashboard:
```json
// dashboards/service-health/v1.1.json
{"dashboard": {"uid": "service-health-dashboard", ...}}

// dashboards/service-health/v1.2.json  
{"dashboard": {"uid": "service-health-dashboard", ...}}  // Same UID = overwrites
```

## 🤖 CI/CD Pipeline Behavior

**Triggers:**
- Push to `main` → Validates + Deploys
- Pull requests → Validates only (no deployment)
- Only runs when `dashboards/**` or `active-manifest.json` change

**Validation Steps:**
1. Manifest JSON structure
2. All referenced dashboard files exist
3. Dashboard JSON structure is valid
4. UID in manifest matches UID in dashboard file
5. Required Grafana API fields present

**Deployment:**
- Deploys **only** dashboards listed in `active-manifest.json`
- Enforces manifest UID in the payload (manifest wins if file UID differs)
- Uses `overwrite: true` to update existing dashboards
- Creates folders if they don't exist
- Logs deployment URL for each dashboard

## 📖 6-Step Day-to-Day Runbook

1. **Switch version**: Edit `active-manifest.json` → change `path` to target version file
2. **Open PR**: `git checkout -b change-dashboard && git commit -am "Deploy v1.3" && git push`
3. **CI validation**: Automatic checks run → see results in PR checks tab
4. **Review**: Check PR comment showing what will deploy → confirm UIDs and folders
5. **Merge**: Deploy happens automatically to Grafana on merge to `main`
6. **Quick-fix from UI**: Export JSON → save as new version → update manifest → PR

## 🛡️ Rollback Strategy

**Instant rollback** - Change manifest path back to previous version → merge PR
```json
// Before (current)
{"uid": "my-dash", "path": "dashboards/my-dash/v2.0.json"}

// After (rollback)
{"uid": "my-dash", "path": "dashboards/my-dash/v1.9.json"}
```

All versions are preserved in the repo - no data loss.

## 🔧 Troubleshooting

### "UID mismatch" error in CI
- Manifest `uid` must exactly match `dashboard.uid` in the JSON file
- Fix: Update the manifest or dashboard file to use consistent UID

### "Dashboard file not found"
- Path in manifest is relative from repo root (must start with `dashboards/`)
- Check for typos in filename or path

### Deployment succeeds but dashboard not visible
- Check folder name in manifest matches Grafana folder (case-sensitive)
- Use `"General"` for root folder (not `""` or `null`)

### Azure Authentication Issues (Managed Grafana)
1. **"Failed to get access token"**: Verify federated credential subject matches `repo:ORG/REPO:ref:refs/heads/main`
2. **"Insufficient permissions"**: Ensure service principal has `Grafana Admin` role on Grafana resource
3. **"401 Unauthorized"**: Check token scope is `https://grafana.azure.com`

See **[AZURE_SETUP.md](AZURE_SETUP.md)** for detailed Azure troubleshooting.

### Self-Hosted Grafana Issues
1. **API key expired**: Generate new key in Grafana UI
2. **Insufficient permissions**: Ensure API key has `Editor` or `Admin` role
3. **GRAFANA_URL incorrect**: Verify URL is accessible and has no trailing slash

## 📚 Additional Resources

- [Azure Managed Grafana Documentation](https://learn.microsoft.com/azure/managed-grafana/)
- [Grafana Dashboard JSON Model](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/view-dashboard-json-model/)
- [GitHub Actions OIDC with Azure](https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)

## 🎯 Key Benefits

✅ **Full version history** - All dashboard iterations preserved in Git  
✅ **Controlled deployments** - Manifest explicitly declares what's live  
✅ **Instant rollbacks** - Change manifest path → merge  
✅ **Automated validation** - CI prevents broken JSON/mismatched UIDs  
✅ **Audit trail** - PR history shows who changed what and when  
✅ **Multi-environment** - Use different manifests per environment/branch
