# Custom Connections — Full Technical Reference

> **Note:** This is the full technical reference. If you're using the Claude Code skill (`/project:build-custom-connection`), you don't need to read this — the skill handles everything automatically.

---

## What is a Custom Connection?

A connection is the layer between an agent and the channel or client where it's deployed. Custom Connections let you define your own connection type with structured response formats — so your client can render agent responses as carousels, forms, buttons, time pickers, or any UI component you design.

---

## Before You Start

Make sure you have:

1. **Agent API connectivity** — Your client can start sessions and receive responses via the Agent API.
2. **External Client App (ECA)** — Configured to allow secure connection to the Agent API.
3. **Metadata API version 66.0 or later** — Required for retrieval and deployment.

---

## Step 1: Plan Your Connection

Answer these questions before writing any metadata:

1. **What is your client called?** (e.g., `AcmeChatClient`, `PartnerPortal`, `MobileApp`)
2. **What response formats does your client need?** Common patterns:
   - **Text choices** — Present 2-7 clickable options to the user
   - **Choices with images** — Product cards, listings with thumbnails
   - **Time picker** — Let users select a time slot
   - **Custom JSON** — Any structured output your client can parse
3. **What instructions should guide the agent's behavior on this connection?** (e.g., "Keep responses under 160 characters", "Don't use response formats for single text-only choices")

---

## Step 2: Create the Directory Structure

Organize your metadata files like this:

```
unpackaged/
├── package.xml
├── aiResponseFormats/
│   ├── <YourClient>Choices_<surfaceId>.aiResponseFormat
│   ├── <YourClient>ChoicesWithImages_<surfaceId>.aiResponseFormat
│   └── <YourClient>TimePicker_<surfaceId>.aiResponseFormat
├── aiSurfaces/
│   └── <YourClient>_<surfaceId>.aiSurface
└── genAiPlannerBundles/
    └── <YourPlannerBundle>/
        └── <YourPlannerBundle>.genAiPlannerBundle
```

The `<surfaceId>` is a unique identifier for your custom connection. You can choose your own alphanumeric string (e.g., `MyCustomSurface_01`) or use the surfaceId generated during a metadata export.

---

## Step 3: Configure package.xml

This file declares which metadata types to deploy.

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
    <!-- Include GenAiPlannerBundle only if you also want to deploy the agent config -->
    <types>
        <members>*</members>
        <name>GenAiPlannerBundle</name>
    </types>
    <version>66.0</version>
</Package>
```

---

## Step 4: Create AiResponseFormat Files

Each `AiResponseFormat` defines a structured output schema the agent uses to format responses for your client. Create one per output type your client supports.

**Key rules:**
- Keep it under 7 response formats per connection
- All fields (description, instructions, input schema) are soft guidance — the agent uses them to reason about format selection but the platform does not enforce strict adherence
- Build your client to handle both well-formed structured responses AND plain text fallbacks

### Example: Text Choices

File: `aiResponseFormats/<YourClient>Choices_<surfaceId>.aiResponseFormat`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<AiResponseFormat xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>A response action for <YourClient>. Use this to prompt the user to select one of many available text choices when the number of choices is GREATER THAN 1 and LESSER THAN 8.</description>

    <input>{"type":"object","properties":{"message":{"type":"string","description":"A brief message introducing the choices"},"choices":{"type":"array","items":{"type":"string"}}},"required":["message","choices"]}</input>

    <instructions>
        <instruction>Always use <YourClient>Choices when showing choice text responses with GREATER THAN 1 choice and LESS THAN 8 choices to the user.</instruction>
        <sortOrder>1</sortOrder>
    </instructions>

    <masterLabel><Your Client> Chat Choice Response</masterLabel>
</AiResponseFormat>
```

### Example: Choices with Images

File: `aiResponseFormats/<YourClient>ChoicesWithImages_<surfaceId>.aiResponseFormat`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<AiResponseFormat xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>A response action for <YourClient>. Use this to prompt the user to select one of many choices with accompanying images, such as product listings.</description>

    <input>{"type":"object","properties":{"message":{"type":"string","description":"A brief message introducing the choices"},"choices":{"type":"array","items":{"type":"object","properties":{"title":{"type":"string"},"imageUrl":{"type":"string"},"actionText":{"type":"string"}},"required":["title","imageUrl","actionText"]}}},"required":["message","choices"]}</input>

    <instructions>
        <instruction>Always use <YourClient>ChoicesWithImages when showing choices with images with GREATER THAN 1 choice and LESS THAN 8 choices to the user.</instruction>
        <sortOrder>2</sortOrder>
    </instructions>

    <masterLabel><Your Client> Chat Choice With Images</masterLabel>
</AiResponseFormat>
```

### Example: Time Picker

File: `aiResponseFormats/<YourClient>TimePicker_<surfaceId>.aiResponseFormat`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<AiResponseFormat xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>A response action for <YourClient>. Use this to prompt the user to select a time using a time picker component.</description>

    <input>
{
  "type": "object",
  "properties": {
    "type": { "const": "section" },
    "text": {
      "type": "object",
      "properties": {
        "type": { "const": "mrkdwn" },
        "text": { "type": "string" }
      },
      "required": ["type", "text"],
      "additionalProperties": false
    },
    "accessory": {
      "type": "object",
      "properties": {
        "type": { "const": "timepicker" },
        "initial_time": { "type": "string", "pattern": "^(?:[01]\\d|2[0-3]):[0-5]\\d$" },
        "placeholder": {
          "type": "object",
          "properties": {
            "type": { "const": "plain_text" },
            "text": { "type": "string" },
            "emoji": { "type": "boolean" }
          },
          "required": ["type", "text", "emoji"],
          "additionalProperties": false
        },
        "action_id": { "type": "string" }
      },
      "required": ["type", "initial_time", "placeholder", "action_id"],
      "additionalProperties": false
    }
  },
  "required": ["type", "text", "accessory"],
  "additionalProperties": false
}
    </input>

    <instructions>
        <instruction>Use <YourClient>TimePicker when you need the user to select a specific time. The response must conform to Slack Block Kit timepicker syntax.</instruction>
        <sortOrder>3</sortOrder>
    </instructions>

    <masterLabel><Your Client> Chat Time Picker</masterLabel>
</AiResponseFormat>
```

---

## Step 5: Create the AiSurface

The `AiSurface` defines the custom connection itself and references the response formats available to it.

File: `aiSurfaces/<YourClient>_<surfaceId>.aiSurface`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<AiSurface xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Custom <YourClient> surface.</description>

    <instructions>
        <instruction>Always reply with brief, friendly, clear response under 160 characters.</instruction>
        <sortOrder>1</sortOrder>
    </instructions>
    <instructions>
        <instruction>Do not use response formats where the response contains more than 7 choices.</instruction>
        <sortOrder>2</sortOrder>
    </instructions>
    <instructions>
        <instruction>Do not use any of the <YourClient>* type formatting where the response contains only a single, text-only choice without images or URLs.</instruction>
        <sortOrder>3</sortOrder>
    </instructions>

    <masterLabel><YourClient></masterLabel>

    <responseFormats>
        <enabled>true</enabled>
        <responseFormat><YourClient>Choices_<surfaceId></responseFormat>
    </responseFormats>
    <responseFormats>
        <enabled>true</enabled>
        <responseFormat><YourClient>ChoicesWithImages_<surfaceId></responseFormat>
    </responseFormats>
    <responseFormats>
        <enabled>true</enabled>
        <responseFormat><YourClient>TimePicker_<surfaceId></responseFormat>
    </responseFormats>

    <surfaceType>Custom</surfaceType>
</AiSurface>
```

### AiSurface Field Reference

| Field | Type | Description |
|---|---|---|
| `description` | String | A description of the custom connection |
| `instructions` | instructions[] | Ordered instructions that guide agent behavior for this connection. Each has an `instruction` (String) and `sortOrder` (Integer) |
| `masterLabel` | String | The display label for the connection |
| `responseFormats` | AiResponseFormat[] | References to response formats. Each has `enabled` (Boolean) and `responseFormat` (String — the format's developer name) |
| `surfaceType` | String | Set to `Custom` for custom connections. Other valid values: `Messaging`, `Telephony`, `NextGenChat` |

---

## Step 6: Add the Connection to a GenAiPlannerBundle

You don't create a new bundle — you add a `plannerSurfaces` entry to your **existing** agent's bundle. Retrieve the current bundle first, then add the surface reference.

### Retrieve the existing bundle

```bash
sf project retrieve start --metadata GenAiPlannerBundle:<YourAgentBundleName> --target-org <your-org> --output-dir retrieved/
```

### Add the plannerSurfaces entry

Open the retrieved `.genAiPlannerBundle` file and add this inside the root element:

```xml
<plannerSurfaces>
    <adaptiveResponseAllowed>true</adaptiveResponseAllowed>
    <callRecordingAllowed>false</callRecordingAllowed>
    <surface><YourClient>_<surfaceId></surface>
    <surfaceType>Custom</surfaceType>
</plannerSurfaces>
```

### Required fields in GenAiPlannerBundle

The bundle must include:
- `<masterLabel>` — Display name for the bundle (required, deploy fails without it)
- `<plannerType>` — Must match the existing agent's planner type (e.g., `Atlas__VoiceAgent`, `Service`). Don't guess — copy from the retrieved bundle.

### Common mistake

Do NOT create a new GenAiPlannerBundle for the custom connection. The bundle represents the agent itself. Creating a second bundle creates a second agent. Instead, add the `plannerSurfaces` entry to the existing agent's bundle.

---

## Step 7: Deploy

Deploy using the Salesforce CLI with `--metadata-dir` (mdapi format):

```bash
sf project deploy start --metadata-dir unpackaged/
```

**Why `--metadata-dir` instead of `--manifest`?** The `AiSurface` and `AiResponseFormat` types are metadata not yet in the CLI's type registry. Using `--manifest` (source format) will throw a `RegistryError`. The `--metadata-dir` flag deploys raw metadata API format and bypasses the registry check.

**Important deployment notes:**

1. **Deploy in two stages if updating an existing agent:**
   - First deploy: `AiResponseFormat` + `AiSurface` (without GenAiPlannerBundle)
   - Second deploy: `GenAiPlannerBundle` with the new `plannerSurfaces` entry
   - Why: If the bundle deploy fails (e.g., agent is active), it rolls back the entire package including your surface/format files.

2. **Deactivate the agent before updating its bundle.** Active agents reject metadata updates with: `"Cannot update record as Agent is Active"`. Deactivate in Agent Builder, deploy, then reactivate.

3. **You need an `sfdx-project.json` in your working directory** for the CLI to run. Minimal file:
   ```json
   {
     "packageDirectories": [{ "path": "unpackaged", "default": true }],
     "namespace": "",
     "sfdcLoginUrl": "https://login.salesforce.com",
     "sourceApiVersion": "66.0"
   }
   ```

To update an existing connection or response format, redeploy the metadata with the same developer name. The updated definition replaces the previous one.

---

## Step 8: Use the Custom Connection via Agent API

### Prerequisites

1. **External Client App (ECA)** — create one in Setup → External Client Apps Manager
2. **OAuth scopes** — enable all four:
   - `api` (Access and manage your data)
   - `refresh_token, offline_access` (Perform requests at any time)
   - `chatbot_api` (Access chatbot services)
   - `sfap_api` (Salesforce API Platform access)
3. **OAuth settings** — enable these two:
   - "Client Credentials Flow"
   - "JWT-based access tokens for named users"
4. **OAuth settings** — deselect these three:
   - "Require Secret for Web Server Flow"
   - "Require Secret for Refresh Token Flow"
   - "Require Proof Key for Code Exchange (PKCE) Extension for Supported Authorization Flows"
5. **Policy tab** — enable Client Credentials Flow and set "Run As (Username)" to a user with **API Only access** permission
6. **Agent API routing** available on your org (production and sandbox orgs have this by default)
7. **Agent is active** in Agent Builder

### Get an access token

```bash
curl -X POST "https://<your-org>.my.salesforce.com/services/oauth2/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=<consumer_key>" \
  -d "client_secret=<consumer_secret>"
```

The response includes `api_instance_url` — use that as the base URL for Agent API calls.

### Start a session with your custom connection

```bash
curl -X POST "<api_instance_url>/einstein/ai-agent/v1/agents/<agentId>/sessions" \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "externalSessionKey": "unique-session-id",
    "instanceConfig": {
      "endpoint": "https://<your-org>.my.salesforce.com"
    },
    "streamingCapabilities": {
      "chunkTypes": ["Text"]
    },
    "surfaceConfig": {
      "surfaceType": "Custom"
    }
  }'
```

The `agentId` is the `BotDefinition` record ID (starts with `0Xx`). Query it:
```bash
sf data query --query "SELECT Id, DeveloperName FROM BotDefinition WHERE DeveloperName='<YourAgent>'" --target-org <org>
```

### Send a message

```bash
curl -X POST "<api_instance_url>/einstein/ai-agent/v1/sessions/<sessionId>/messages" \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "sequenceId": 1,
      "type": "Text",
      "text": "I need help choosing a product"
    }
  }'
```

The response will contain structured output matching your AiResponseFormat schemas when the agent determines a response format is appropriate.

---

## Step 9: Test

### Verify deployment in Agent Builder

1. Open Agent Builder for your agent
2. Go to the **Connections** tab
3. Confirm your custom connection appears in the list (e.g., "UniversalContainers")

This confirms the metadata deployed correctly and the connection is wired to your agent.

**Important:** The Agent Builder preview pane does NOT support custom connections. The preview always uses the default channel — response formats and surface instructions are not injected. You must test via the Agent API.

### Test via Agent API (end-to-end)

1. Deploy metadata to a sandbox or production org
2. Create an ECA with `chatbot_api` scope
3. Get a token and start a session with `"surfaceType": "Custom"`
4. Send messages that should trigger your response formats
5. Verify the response payload includes structured format data
6. Test fallback: send a message that doesn't match any format — agent should respond with plain text

When the session is started with `"surfaceType": "Custom"`, the platform injects your AiResponseFormat definitions as callable tools in the LLM context, and the AiSurface instructions are added to the system prompt. This only happens through the Agent API — not in the Agent Builder preview.

### What to validate

- Agent selects the correct response format based on context
- JSON output matches your defined `input` schema
- Fallback to plain text works when no format applies
- Your client renders structured responses correctly
- Your client handles unexpected/malformed responses gracefully

---

## Step 10: Diagnosing connections when something's wrong

When a custom connection isn't working — the agent ignores it, responses come back as plain text, or a deploy failed — the fastest way to figure out what's broken is the diagnostic skill:

```
/project:diagnose-connection
```

It's read-only (never changes anything in your org) and produces a health report telling you exactly what's wrong and how to fix it. Safe to run on production orgs.

### What it checks

The diagnostic groups checks into three layers — environment, agent, and connection. Each is explained below in plain language so you can interpret the report without needing to know the underlying metadata.

**Environment checks (run first):**
- The Salesforce CLI is installed and your org alias is logged in
- The org's API version is high enough to support custom connections (≥ v62.0)
- Your user can retrieve metadata from the org

If any of these fail, the skill stops here and tells you what to fix. The main checks don't run with a broken environment.

**Agent-level checks:**
- The agent's bundle exists and could be retrieved
- Whether the agent is currently active (you'll need to deactivate it before changing anything)
- How many versions exist (multiple versions can mean changes you made aren't being checked — the report says which version it's looking at)

**Connection-level checks (run for each connection on the agent):**
- For standard connections (Telephony, Web Chat, Email, Messaging): just confirms they're present. These are built into the platform — there's not much that can go wrong.
- For your custom connection:
  - Is the AiSurface deployed in the org?
  - Is `adaptiveResponseAllowed` set to true? (Required for structured responses.)
  - Is there only one custom connection on this agent? (Platform limit.)
  - Are there any duplicate connection entries? (A common deploy mistake.)
  - Are the response formats it references actually deployed in the org?
  - Are the JSON schemas in your local response format files valid? (Only checked if you have the source files in your current directory.)

### Reading the report

The report has four sections:

| Section | What it means |
|---|---|
| **Top priority** | The single most important fix. If you're going to do one thing, do this. |
| **YOUR CONNECTIONS** | Every connection on the agent, with its checks listed underneath. |
| **WARNINGS** | Things that won't break the connection but are worth knowing (e.g., agent is active, multiple versions exist). |
| **ISSUES** | Things that are broken and need fixing (e.g., a referenced response format isn't deployed, adaptive responses are off). |

Every warning and issue includes:
- **What this means:** plain-English explanation of the problem
- **How to fix:** the exact step to take (Setup → navigation path, or a specific command)

A summary line at the bottom gives the final counts: `N passed, N warnings, N issues`. A copy of the same report is saved as JSON to `/tmp/diagnose-report.json` for use in CI/CD.

### What it can't tell you

The diagnostic catches misconfiguration, not platform corruption. A few specific things it doesn't detect:
- **Phantom formats:** rarely, a response format can deploy with "Unchanged" status without actually being created in the org. The diagnostic's dry-run validation will say it exists when it doesn't. If everything passes but the connection still doesn't work, redeploy the format with a fresh name.
- **Runtime issues:** the diagnostic checks the metadata, not the live Agent API behavior. To confirm end-to-end, use the `verify-connection.sh` script in [`examples/`](./examples/verify-connection.sh) or test via the Agent API directly.
- **External Client App / OAuth setup:** the diagnostic doesn't verify your ECA configuration. If the Agent API rejects your token, that's a separate issue — see [Step 8](#step-8-use-the-custom-connection-via-agent-api) for ECA setup.

### When to run it

- **First thing when something stops working.** The diagnostic catches the common issues fast.
- **After a deploy.** Confirm the wiring is correct.
- **Before activating an agent in production.** Catch problems before users hit them.
- **In CI/CD pipelines.** Use the JSON output to fail builds when checks regress.

---

## Troubleshooting

| Issue | Resolution |
|---|---|
| `RegistryError` on deploy | Use `--metadata-dir` flag instead of `--manifest`. These metadata types aren't in the CLI registry. |
| `Cannot update record as Agent is Active` | Deactivate the agent in Agent Builder before deploying bundle changes. Reactivate after. |
| `Surface does not exist in org` | Deploy AiSurface + AiResponseFormat in a separate package first, then deploy the GenAiPlannerBundle update. |
| Invalid enum for `plannerType` | Don't guess the planner type. Retrieve the existing bundle and copy the value exactly. |
| Missing `masterLabel` on bundle | GenAiPlannerBundle requires a `<masterLabel>` element. Deploy fails silently without it. |
| Invalid JSON schema | Verify that the `input` field in your AiResponseFormat contains valid, properly escaped JSON. |
| Missing references | All response formats referenced in AiSurface must exist as deployed AiResponseFormat entities. |
| Surface type mismatch | Ensure `surfaceType` in AiSurface matches `surfaceType` in your plannerSurfaces entry. |
| Responses not properly formatted | Verify your Agent API session call includes `"surfaceConfig": {"surfaceType": "Custom"}` in the request body. |
| Agent Builder preview returns plain text | The Agent Builder preview does NOT support custom connections. Response formats are only injected via the Agent API with `surfaceConfig`. The preview always uses the default channel. |
| `duplicate value found: PlannerId` | Only one `surfaceType: Custom` connection is allowed per agent. Remove the existing custom surface entry before adding a new one. |
| Response formats deploy as "Unchanged" but surface says "does not exist" | Ensure response format files are in an `aiResponseFormats/` subdirectory (not at the package root). Flat file structure causes silent no-ops. |

---

## Tips

- **Keep response formats under 7 per connection** — more than that and the agent struggles to select the right one
- **Test your JSON schemas** — Use an LLM to generate the schema from the output structure your client expects
- **Instructions are soft guidance** — The agent uses natural language reasoning to select formats. There's no strict enforcement. Build your client to handle unexpected output gracefully.
- **Start simple** — Begin with 1-2 response formats. Add more once you've validated the agent selects correctly.
- **Use description and instructions together** — `description` on AiResponseFormat tells the agent WHEN to use this format. `instructions` tell it HOW to use it.
