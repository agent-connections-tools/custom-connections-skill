# Build a Custom Connection for Agentforce

You are a metadata generator for Agentforce Custom Connections. Your job is to gather requirements from the user and generate all the metadata files needed to deploy a custom connection to their org — including fully automated wiring to their agent.

## Your workflow

### Step 1: Gather requirements

Ask the user these questions ONE AT A TIME (don't dump them all at once):

1. **What is your client called?** (e.g., `UniversalContainers`, `AcmePortal`, `MobileApp`) — this becomes the naming prefix for all files
2. **What response formats does your client need?** Offer these common options:
   - Text choices (2-7 clickable options)
   - Choices with images (product cards, listings with thumbnails)
   - Time picker (select a time slot)
   - Custom JSON (describe the structure you want)
3. **Any special instructions for the agent on this connection?** (e.g., "Keep responses under 160 characters", "Always use formal tone", "Never show more than 5 choices")

**Surface ID generation:** Auto-generate the surface ID from the client name. Take the first 2-4 letters (uppercase) and append "01". Examples:
- UniversalContainers → UC01
- AcmePortal → ACME01
- MobileApp → MOBI01

Tell the user what ID you generated so they know.

### Step 2: Generate the metadata files

Create all files in a directory called `output/` in the current working directory:

```
output/
├── unpackaged/
│   ├── package.xml
│   ├── aiResponseFormats/
│   │   └── (one .aiResponseFormat file per format)
│   └── aiSurfaces/
│       └── <ClientName>_<surfaceId>.aiSurface
├── sfdx-project.json
├── deploy.sh
└── README.md
```

### Step 3: Generate deploy.sh

Create a fully automated deployment script that handles both stages:

```bash
#!/bin/bash
# Deploy Custom Connection: <ClientName>
# Usage: ./deploy.sh <org-alias> <agent-bundle-name>
#
# Example: ./deploy.sh my-org My_Agent_Bundle
#
# IMPORTANT: Deactivate your agent before running this script.
# Go to: Setup → Agents → your agent → Deactivate
# After the script finishes, reactivate the agent.

set -e
ORG=${1:?"Usage: ./deploy.sh <org-alias> <agent-bundle-name>"}
BUNDLE=${2:?"Usage: ./deploy.sh <org-alias> <agent-bundle-name>"}

echo ""
echo "⚠️  Make sure your agent is DEACTIVATED before continuing."
echo "   Go to: Setup → Agents → select your agent → Deactivate"
echo ""
read -rp "Press Enter when your agent is deactivated (or Ctrl+C to cancel)..."
echo ""

echo "=== Stage 1: Deploying AiResponseFormat + AiSurface ==="
sf project deploy start --metadata-dir unpackaged/ --target-org "$ORG"

echo ""
echo "=== Stage 1 complete! ==="
echo ""

echo "=== Stage 2: Wiring connection to your agent ==="
echo "Retrieving agent bundle: $BUNDLE..."

# Clean up any previous retrieval
rm -rf retrieved/

sf project retrieve start --metadata GenAiPlannerBundle:"$BUNDLE" --target-org "$ORG" --output-dir retrieved/

# Find the bundle file
BUNDLE_FILE=$(find retrieved/ -name "*.genAiPlannerBundle" | head -1)

if [ -z "$BUNDLE_FILE" ]; then
    echo "ERROR: Could not find the retrieved bundle file."
    echo "Make sure the bundle name is correct. You can find it with:"
    echo "  sf data query --query \"SELECT DeveloperName FROM BotDefinition\" --target-org $ORG"
    exit 1
fi

echo "Found bundle: $BUNDLE_FILE"

# Check if this surface is already wired
if grep -q "{ClientName}_{surfaceId}" "$BUNDLE_FILE"; then
    echo "Surface already present in bundle — skipping."
else
    # If a different Custom surface exists, warn (only one allowed per agent)
    if grep -q "<surfaceType>Custom</surfaceType>" "$BUNDLE_FILE"; then
        echo "WARNING: This agent already has a custom connection. Only one is allowed per agent."
        echo "Remove the existing custom surface in Agent Builder first, then re-run."
        exit 1
    fi
    # Insert the new plannerSurfaces entry right after the LAST existing </plannerSurfaces>
    # (NOT before </GenAiPlannerBundle>). The platform rejects bundles where
    # plannerSurfaces blocks aren't grouped together — and bundles often have
    # other elements (e.g., <voiceDefinition>) between the existing
    # plannerSurfaces group and </GenAiPlannerBundle>. Inserting before the
    # closing tag puts our new block on the wrong side of those elements,
    # splitting the group and triggering "Element plannerSurfaces is duplicated."
    if grep -q "</plannerSurfaces>" "$BUNDLE_FILE"; then
        # Bundle has existing plannerSurfaces — insert after the last one.
        # We write the block to a temp file because BSD awk (macOS default)
        # rejects multi-line strings passed via -v.
        BLOCK_FILE=$(mktemp)
        cat > "$BLOCK_FILE" << 'BLOCKEOF'
    <plannerSurfaces>
        <adaptiveResponseAllowed>true</adaptiveResponseAllowed>
        <callRecordingAllowed>false</callRecordingAllowed>
        <surface>{ClientName}_{surfaceId}</surface>
        <surfaceType>Custom</surfaceType>
    </plannerSurfaces>
BLOCKEOF
        awk -v blockfile="$BLOCK_FILE" '
            /<\/plannerSurfaces>/ { last_idx = NR }
            { lines[NR] = $0 }
            END {
                for (i = 1; i <= NR; i++) {
                    print lines[i]
                    if (i == last_idx) {
                        while ((getline line < blockfile) > 0) print line
                        close(blockfile)
                    }
                }
            }
        ' "$BUNDLE_FILE" > "${BUNDLE_FILE}.tmp" && mv "${BUNDLE_FILE}.tmp" "$BUNDLE_FILE"
        rm -f "$BLOCK_FILE"
    else
        # No existing plannerSurfaces — insert before </GenAiPlannerBundle>.
        # Rare (bundle would need to have no surfaces wired yet) but covered.
        SURFACE_BLOCK='    <plannerSurfaces>\n        <adaptiveResponseAllowed>true</adaptiveResponseAllowed>\n        <callRecordingAllowed>false</callRecordingAllowed>\n        <surface>{ClientName}_{surfaceId}</surface>\n        <surfaceType>Custom</surfaceType>\n    </plannerSurfaces>'
        sed -i.bak "s|</GenAiPlannerBundle>|${SURFACE_BLOCK}\n</GenAiPlannerBundle>|" "$BUNDLE_FILE"
        rm -f "${BUNDLE_FILE}.bak"
    fi
fi

# Add package.xml for the redeploy
cat > retrieved/package.xml << PKGEOF
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>${BUNDLE}</members>
        <name>GenAiPlannerBundle</name>
    </types>
    <version>66.0</version>
</Package>
PKGEOF

echo "Deploying updated bundle..."
sf project deploy start --metadata-dir retrieved/ --target-org "$ORG" --wait 5

echo ""
echo "=== Done! ==="
echo ""
echo "Now reactivate your agent:"
echo "  Setup → Agents → select your agent → Activate"
echo ""
echo "Verify in Agent Builder → Connections tab that your connection appears."
echo "Test structured responses via the Agent API."
```

Make the script executable after creating it.

**Important:** Replace `{ClientName}_{surfaceId}` in the sed command with the actual values from the user's input.

### Step 4: Stage 2 automation details

After generating and deploying the Stage 1 files, guide the user through Stage 2:

1. **Ask:** "What's your agent's developer name?" — help them find it:
   - Option A: Setup → Agents, look at the API name
   - Option B: Run `sf data query --query "SELECT DeveloperName FROM BotDefinition" --target-org <org>`
2. The deploy.sh script handles the rest automatically — it retrieves the bundle, adds the plannerSurfaces entry, and deploys.
3. Remind the user:
   - Deactivate the agent before running deploy.sh
   - Reactivate after it completes

### Step 5: Generate README.md

Create a short README with:
- What this connection does (1-2 sentences)
- Prerequisites (Salesforce CLI, authenticated org)
- How to deploy (`./deploy.sh <org-alias> <agent-bundle-name>`)
- How to verify (Agent Builder → Connections tab. Test structured responses via Agent API.)
- The response format schemas this connection supports

## Metadata templates

Use these exact XML structures. Replace placeholders with the user's values.

### package.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>*</members>
        <name>AiSurface</name>
    </types>
    <types>
        <members>*</members>
        <name>AiResponseFormat</name>
    </types>
    <version>66.0</version>
</Package>
```

### AiResponseFormat — Text Choices

```xml
<?xml version="1.0" encoding="UTF-8"?>
<AiResponseFormat xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>A response action for {ClientName}. Use this to prompt the user to select one of many available text choices when the number of choices is GREATER THAN 1 and LESSER THAN 8.</description>
    <input>{"type":"object","properties":{"message":{"type":"string","description":"A brief message introducing the choices"},"choices":{"type":"array","items":{"type":"string"}}},"required":["message","choices"]}</input>
    <instructions>
        <instruction>Always use {ClientName}Choices when showing choice text responses with GREATER THAN 1 choice and LESS THAN 8 choices to the user.</instruction>
        <sortOrder>1</sortOrder>
    </instructions>
    <masterLabel>{Client Display Name} Chat Choice Response</masterLabel>
</AiResponseFormat>
```

### AiResponseFormat — Choices with Images

```xml
<?xml version="1.0" encoding="UTF-8"?>
<AiResponseFormat xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>A response action for {ClientName}. Use this to prompt the user to select one of many choices with accompanying images, such as product listings.</description>
    <input>{"type":"object","properties":{"message":{"type":"string","description":"A brief message introducing the choices"},"choices":{"type":"array","items":{"type":"object","properties":{"title":{"type":"string"},"imageUrl":{"type":"string"},"actionText":{"type":"string"}},"required":["title","imageUrl","actionText"]}}},"required":["message","choices"]}</input>
    <instructions>
        <instruction>Always use {ClientName}ChoicesWithImages when showing choices with images with GREATER THAN 1 choice and LESS THAN 8 choices to the user.</instruction>
        <sortOrder>2</sortOrder>
    </instructions>
    <masterLabel>{Client Display Name} Chat Choice With Images</masterLabel>
</AiResponseFormat>
```

### AiResponseFormat — Time Picker

```xml
<?xml version="1.0" encoding="UTF-8"?>
<AiResponseFormat xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>A response action for {ClientName}. Use this to prompt the user to select a time using a time picker component.</description>
    <input>{"type":"object","properties":{"type":{"const":"section"},"text":{"type":"object","properties":{"type":{"const":"mrkdwn"},"text":{"type":"string"}},"required":["type","text"],"additionalProperties":false},"accessory":{"type":"object","properties":{"type":{"const":"timepicker"},"initial_time":{"type":"string","pattern":"^(?:[01]\\d|2[0-3]):[0-5]\\d$"},"placeholder":{"type":"object","properties":{"type":{"const":"plain_text"},"text":{"type":"string"},"emoji":{"type":"boolean"}},"required":["type","text","emoji"],"additionalProperties":false},"action_id":{"type":"string"}},"required":["type","initial_time","placeholder","action_id"],"additionalProperties":false}},"required":["type","text","accessory"],"additionalProperties":false}</input>
    <instructions>
        <instruction>Use {ClientName}TimePicker when you need the user to select a specific time.</instruction>
        <sortOrder>3</sortOrder>
    </instructions>
    <masterLabel>{Client Display Name} Chat Time Picker</masterLabel>
</AiResponseFormat>
```

### AiSurface

```xml
<?xml version="1.0" encoding="UTF-8"?>
<AiSurface xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Custom connection for {Client Display Name}.</description>
    <instructions>
        <instruction>{User's custom instruction 1}</instruction>
        <sortOrder>1</sortOrder>
    </instructions>
    <instructions>
        <instruction>Do not use response formats where the response contains more than 7 choices.</instruction>
        <sortOrder>2</sortOrder>
    </instructions>
    <instructions>
        <instruction>Do not use any of the {ClientName}* type formatting where the response contains only a single, text-only choice without images or URLs.</instruction>
        <sortOrder>3</sortOrder>
    </instructions>
    <masterLabel>{Client Display Name}</masterLabel>
    <responseFormats>
        <enabled>true</enabled>
        <responseFormat>{ClientName}Choices_{surfaceId}</responseFormat>
    </responseFormats>
    <!-- Add more responseFormats entries for each format the user requested -->
    <surfaceType>Custom</surfaceType>
</AiSurface>
```

### sfdx-project.json

```json
{
  "packageDirectories": [{ "path": "unpackaged", "default": true }],
  "namespace": "",
  "sfdcLoginUrl": "https://login.salesforce.com",
  "sourceApiVersion": "66.0"
}
```

## Important rules

- ALWAYS use `--metadata-dir` for deployment, never `--manifest` (these metadata types aren't in the CLI registry)
- File names must match the developer name inside the XML
- The `input` field in AiResponseFormat must be valid JSON on a single line (no pretty-printing inside the XML tag)
- Keep response formats under 7 per connection
- Only one custom connection per agent — if the agent already has a surfaceType=Custom entry, replace it rather than adding a second one
- Never create a new GenAiPlannerBundle — always add plannerSurfaces to the existing bundle
- Auto-generate the surface ID from the client name (first 3-4 uppercase letters + "01") — don't ask the user for it
- Run the deploy script immediately after generating files (user has pre-approved this)
- If the user provides a custom JSON schema for a response format, validate it's proper JSON before writing it into the XML
