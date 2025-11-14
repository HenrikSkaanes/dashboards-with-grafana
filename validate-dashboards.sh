#!/bin/bash
# validate-dashboards.sh - Local validation script for dashboard manifest
# Usage: ./validate-dashboards.sh

set -e

MANIFEST_FILE="active-manifest.json"
EXIT_CODE=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Grafana Dashboard Manifest Validator"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check jq is installed
if ! command -v jq &> /dev/null; then
    echo "❌ ERROR: jq is not installed"
    echo "   Install: sudo apt-get install jq (Linux) or brew install jq (Mac)"
    exit 1
fi

# Check manifest exists
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "❌ ERROR: $MANIFEST_FILE not found"
    exit 1
fi

# Validate manifest JSON
echo "🔍 Validating manifest JSON structure..."
if ! jq empty "$MANIFEST_FILE" 2>/dev/null; then
    echo "❌ ERROR: Invalid JSON in $MANIFEST_FILE"
    exit 1
fi
echo "✅ Manifest JSON is valid"
echo ""

# Extract dashboard count
DASHBOARD_COUNT=$(jq '.dashboards | length' "$MANIFEST_FILE")
echo "📊 Found $DASHBOARD_COUNT dashboard(s) in manifest"
echo ""

# Validate each dashboard
echo "🔍 Validating dashboard files..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

jq -c '.dashboards[] | @json' "$MANIFEST_FILE" | while read -r dashboard_json; do
    dashboard=$(echo "$dashboard_json" | jq -r '.')
    
    MANIFEST_UID=$(echo "$dashboard" | jq -r '.uid')
    DASHBOARD_PATH=$(echo "$dashboard" | jq -r '.path')
    FOLDER_NAME=$(echo "$dashboard" | jq -r '.folder')
    VERSION_LABEL=$(echo "$dashboard" | jq -r '.version // "unversioned"')
    
    echo ""
    echo "📄 Validating: $DASHBOARD_PATH"
    echo "   UID: $MANIFEST_UID"
    echo "   Version: $VERSION_LABEL"
    echo "   Folder: $FOLDER_NAME"
    
    # Check file exists
    if [ ! -f "$DASHBOARD_PATH" ]; then
        echo "   ❌ ERROR: File not found"
        EXIT_CODE=1
        continue
    fi
    
    # Validate JSON structure
    if ! jq empty "$DASHBOARD_PATH" 2>/dev/null; then
        echo "   ❌ ERROR: Invalid JSON"
        EXIT_CODE=1
        continue
    fi
    
    # Check required fields
    if ! jq -e '.dashboard.uid' "$DASHBOARD_PATH" >/dev/null 2>&1; then
        echo "   ❌ ERROR: Missing .dashboard.uid field"
        EXIT_CODE=1
        continue
    fi
    
    if ! jq -e '.dashboard.title' "$DASHBOARD_PATH" >/dev/null 2>&1; then
        echo "   ⚠️  WARNING: Missing .dashboard.title field"
    fi
    
    # Check UID consistency
    FILE_UID=$(jq -r '.dashboard.uid' "$DASHBOARD_PATH")
    if [ "$MANIFEST_UID" != "$FILE_UID" ]; then
        echo "   ❌ ERROR: UID mismatch"
        echo "      Manifest UID: $MANIFEST_UID"
        echo "      File UID: $FILE_UID"
        EXIT_CODE=1
        continue
    fi
    
    # Check dashboard structure
    PANEL_COUNT=$(jq '.dashboard.panels | length' "$DASHBOARD_PATH" 2>/dev/null || echo "0")
    echo "   ✅ Valid ($PANEL_COUNT panels)"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "❌ VALIDATION FAILED"
    echo "   Fix the errors above before committing"
    exit 1
fi

echo ""
echo "✅ ALL VALIDATIONS PASSED"
echo ""
echo "📦 Summary:"
jq -r '.dashboards[] | "   • \(.uid) (\(.version // "unversioned")) → \(.folder)"' "$MANIFEST_FILE"
echo ""
echo "✨ Ready to commit and deploy!"
