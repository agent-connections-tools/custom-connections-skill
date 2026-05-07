#!/bin/bash
set -e

ORG_ALIAS="${1:?Usage: ./deploy.sh <org-alias> <agent-bundle-name>}"
BUNDLE_NAME="${2:?Usage: ./deploy.sh <org-alias> <agent-bundle-name>}"

echo "=== Deploying Acme Portal Custom Connection ==="
echo "Org: $ORG_ALIAS"
echo "Bundle: $BUNDLE_NAME"
echo ""
echo "Make sure your agent is DEACTIVATED in Agent Builder before continuing."
read -rp "Press Enter to continue (or Ctrl+C to cancel)..."

echo ""
echo "Step 1/4: Deploying response formats and surface..."
sf project deploy start --metadata-dir unpackaged/ --target-org "$ORG_ALIAS" --wait 5

echo ""
echo "Step 2/4: Retrieving existing agent bundle..."
rm -rf retrieved/
sf project retrieve start --metadata "GenAiPlannerBundle:$BUNDLE_NAME" --target-org "$ORG_ALIAS" --output-dir retrieved/

BUNDLE_FILE=$(find retrieved/ -name "*.genAiPlannerBundle" | head -1)
if [ -z "$BUNDLE_FILE" ]; then
    echo "ERROR: Could not find bundle '$BUNDLE_NAME'. Check the name with:"
    echo "  sf project retrieve start --metadata GenAiPlannerBundle --target-org $ORG_ALIAS --output-dir check/"
    exit 1
fi

# Add package.xml for the redeploy
cat > retrieved/package.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>${BUNDLE_NAME}</members>
        <name>GenAiPlannerBundle</name>
    </types>
    <version>66.0</version>
</Package>
EOF

echo ""
echo "Step 3/4: Adding custom surface to agent bundle..."
if grep -q "AcmePortal_AcmePortal01" "$BUNDLE_FILE"; then
    echo "Surface already present in bundle — skipping."
else
    # Insert plannerSurfaces block before closing tag (portable across macOS and Linux)
    SURFACE_BLOCK='    <plannerSurfaces>\n        <adaptiveResponseAllowed>true</adaptiveResponseAllowed>\n        <callRecordingAllowed>false</callRecordingAllowed>\n        <surface>AcmePortal_AcmePortal01</surface>\n        <surfaceType>Custom</surfaceType>\n    </plannerSurfaces>'
    sed -i.bak "s|</GenAiPlannerBundle>|${SURFACE_BLOCK}\n</GenAiPlannerBundle>|" "$BUNDLE_FILE"
    rm -f "${BUNDLE_FILE}.bak"
fi

echo ""
echo "Step 4/4: Deploying updated agent bundle..."
sf project deploy start --metadata-dir retrieved/ --target-org "$ORG_ALIAS" --wait 5

echo ""
echo "Done! Reactivate your agent in Agent Builder."
echo "Verify: Agent Builder > Connections tab > 'AcmePortal' should appear."
