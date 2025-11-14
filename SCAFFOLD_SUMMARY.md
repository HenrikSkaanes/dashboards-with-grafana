# 🎯 Repository Scaffold - Complete File Tree

## Generated Structure

```
dashboards-with-grafana/
│
├── .github/
│   └── workflows/
│       └── deploy-manifest.yml          # CI/CD pipeline (validates + deploys)
│
├── dashboards/
│   ├── service-health/
│   │   ├── v1.1.json                    # Older version (preserved)
│   │   └── v1.2.json                    # Current active version
│   └── api-performance/
│       └── v2.0.json                    # Active version
│
├── .gitignore                           # Git ignore rules
├── README.md                            # Main documentation
├── QUICK_REFERENCE.md                   # Copy-paste commands
├── active-manifest.json                 # ⭐ DEPLOYMENT CONTROL FILE
├── manifest-schema.json                 # JSON schema for validation
└── validate-dashboards.sh               # Local validation script

```

## 📋 File Purposes

| File | Purpose | Who Edits |
|------|---------|-----------|
| `active-manifest.json` | **Controls which dashboard versions deploy** | Developers (primary edit point) |
| `dashboards/**/*.json` | Dashboard definitions (all versions preserved) | Created from Grafana exports |
| `deploy-manifest.yml` | GitHub Actions workflow (validation + deployment) | DevOps/Initial setup |
| `manifest-schema.json` | JSON schema for manifest validation | Reference only |
| `README.md` | Developer documentation | Documentation updates |
| `QUICK_REFERENCE.md` | Copy-paste commands and runbook | Quick reference |
| `validate-dashboards.sh` | Local pre-commit validation script | Run locally |

## 🚀 Getting Started Checklist

### 1. Initial Setup (One-Time)
- [ ] Copy all files to your repository root
- [ ] Initialize git: `git init && git add . && git commit -m "Initial scaffold"`
- [ ] Create GitHub repository and push
- [ ] Configure GitHub secrets:
  - [ ] `GRAFANA_URL` - Your Grafana instance URL
  - [ ] `GRAFANA_API_KEY` - Service account token
- [ ] Test workflow: Make a PR changing `active-manifest.json`

### 2. Add Your First Dashboard
- [ ] Export dashboard from Grafana UI (Share → Export → Save JSON)
- [ ] Save to `dashboards/your-dashboard/v1.0.json`
- [ ] Add entry to `active-manifest.json`
- [ ] Run `./validate-dashboards.sh` locally
- [ ] Commit and push
- [ ] Verify deployment in Grafana

### 3. Daily Operations
- [ ] Edit dashboard in Grafana UI
- [ ] Export as new version file
- [ ] Update manifest path to new version
- [ ] Create PR → Merge → Auto-deploy

## 🔄 Version Management Strategy

### Active Version (Deployed)
```json
// active-manifest.json
{
  "uid": "service-health-dashboard",
  "path": "dashboards/service-health/v1.2.json",  ← Currently deployed
  "folder": "Production",
  "version": "v1.2"
}
```

### All Versions (Preserved)
```
dashboards/service-health/
├── v1.0.json  ← Historical (preserved)
├── v1.1.json  ← Previous (preserved)
└── v1.2.json  ← Active (deployed)
```

**To deploy v1.1**: Change manifest `path` from `v1.2.json` → `v1.1.json`

## 🎯 Key Design Decisions

### Why UID Consistency Matters
- **Same UID** across versions = dashboard updates in-place (no duplicate)
- Grafana uses UID as the primary key for dashboard identity
- Manifest validates UID matches between manifest and file

### Why Manifest-Based Deployment
- **Explicit control**: Only manifested dashboards deploy
- **Version selection**: Pick any historical version instantly
- **Rollback**: Change one line in manifest, merge PR
- **Audit**: Git history shows exactly what's deployed and when

### Why Preserve All Versions
- **Zero data loss**: Never delete dashboard iterations
- **A/B testing**: Deploy different versions to different environments
- **Compliance**: Full audit trail of all changes
- **Rollback**: Instant rollback to any previous state

## 🔐 Security Recommendations

### Production Setup
1. **Use OIDC** (uncomment OIDC steps in workflow)
2. **Store API keys in Azure Key Vault**
3. **Use service accounts**, not personal tokens
4. **Rotate keys** every 90 days
5. **Restrict branch protection** on `main`

### Branch Protection Rules
```
Settings → Branches → Add rule for 'main':
☑ Require pull request reviews (1 approval)
☑ Require status checks to pass (GitHub Actions)
☑ Require branches to be up to date
☑ Include administrators
```

## 📊 Expected Workflow Output

### PR Validation (Non-main branch)
```
✅ Validate manifest JSON structure
✅ Extract and validate dashboard files
✅ Validate manifest UIDs match dashboard UIDs
✅ PR Comment with deployment preview
❌ Deployment (skipped - not main branch)
```

### Main Branch Deployment
```
✅ Validate manifest JSON structure
✅ Extract and validate dashboard files
✅ Validate manifest UIDs match dashboard UIDs
✅ Deploy dashboards to Grafana
   → service-health-dashboard: ✅ Deployed
   → api-performance-dashboard: ✅ Deployed
```

## 🛠️ Customization Points

### Add Environment-Specific Manifests
```
active-manifest.json          → Production
active-manifest-staging.json  → Staging
active-manifest-dev.json      → Development
```

Update workflow to use different manifests per branch:
```yaml
env:
  MANIFEST_FILE: ${{ github.ref == 'refs/heads/main' && 'active-manifest.json' || 'active-manifest-dev.json' }}
```

### Add Dashboard Validation Rules
Extend `validate-and-deploy` job in workflow:
```yaml
- name: Custom validation
  run: |
    # Ensure all dashboards have required tags
    jq -r '.dashboards[].path' active-manifest.json | while read path; do
      if ! jq -e '.dashboard.tags | contains(["production"])' "$path" >/dev/null; then
        echo "ERROR: Missing 'production' tag in $path"
        exit 1
      fi
    done
```

### Add Slack Notifications
```yaml
- name: Notify Slack
  if: always()
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "Dashboard deployment ${{ job.status }}"
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

## 📞 Support & Next Steps

1. **Test the scaffold**: `./validate-dashboards.sh`
2. **Review workflow**: `.github/workflows/deploy-manifest.yml`
3. **Configure secrets**: GitHub Settings → Secrets
4. **Create first PR**: Change manifest and test CI
5. **Monitor deployments**: GitHub Actions tab

## 🎓 Learning Resources

- [Grafana Dashboard JSON Model](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/view-dashboard-json-model/)
- [Azure Managed Grafana](https://learn.microsoft.com/azure/managed-grafana/)
- [GitHub Actions Workflows](https://docs.github.com/actions/using-workflows)
- [jq JSON Processor](https://stedolan.github.io/jq/manual/)

---

**✅ Scaffold is complete and ready to use!**

All files are production-ready - commit and push to start using dashboards-as-code.
