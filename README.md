# Custom Connections Skill for Agentforce

A Claude Code skill that generates all the metadata you need to deploy a Custom Connection to your Agentforce agent. Answer 3 questions, get a deploy-ready package.

## What problem does this solve?

**Before:** You want your agent to respond with rich UI (buttons, image cards, time pickers) instead of plain text. But setting this up means writing XML metadata files by hand, understanding Salesforce deployment commands, and wiring things together across multiple config layers. Even experienced developers find this tedious.

**After:** You run one skill, answer 3 plain-English questions, and get a fully automated deploy script that handles everything — including wiring the connection to your agent. No XML editing, no manual steps.

## Is this for me?

This tool is for you if your agent responds through the **Agent API** to a custom app — like your own website, mobile app, or portal. If you're only using Salesforce's built-in chat widget or Messaging channels, you don't need a custom connection (those are already handled for you).

## What are Custom Connections?

Custom Connections let you define your own connection type with structured response formats — so your agent can respond with carousels, buttons, image cards, time pickers, or any UI component your client app supports. Instead of plain text, your app gets structured JSON it can render however it wants.

## Quick Start

### Prerequisites

You need three things installed. You only do this once:

1. **Claude Code** — the AI tool that runs the skill
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```
   Don't have npm? [Install Node.js first](https://nodejs.org/) (it includes npm).

2. **Salesforce CLI** — the command-line tool that deploys to your org
   - [Download and install here](https://developer.salesforce.com/tools/salesforcecli)

3. **An existing agent** — you need an agent already created in Agent Builder that you want to add the custom connection to.

### First time setup

After installing the Salesforce CLI, log in to your org (you only do this once):

```bash
sf org login web --alias my-org
```

This opens a browser window where you sign in with your Salesforce credentials. The `--alias` flag gives your org a short name (like "my-org") that you'll use in deploy commands later.

### Usage

```bash
git clone https://github.com/agent-connections-tools/custom-connections-skill.git
cd custom-connections-skill
claude
```

Then type:

```
/project:build-custom-connection
```

Claude will ask you:
1. What is your client called?
2. What response formats do you need?
3. Any special instructions for the agent?

It generates a complete deploy-ready package in `output/` with a fully automated deploy script.

### Deploy

```bash
cd output
./deploy.sh <your-org-alias> <your-agent-bundle-name>
```

**Finding your agent bundle name:** This is the developer name of your agent — not the display name you see in the UI. To find it, run:

```bash
sf data query --query "SELECT DeveloperName, MasterLabel FROM BotDefinition" --target-org my-org
```

This shows a table like:

```
DeveloperName              MasterLabel
─────────────────────────  ─────────────────────
Customer_Support_Agent     Customer Support Agent
```

Use the value from the `DeveloperName` column. Append `_v1` to it (e.g., `Customer_Support_Agent_v1`) — that's your bundle name.

> **If the deploy script says it can't find the bundle:** Your agent may have been versioned (`_v2`, `_v3`, etc.). Run this to get the exact bundle name:
> ```bash
> sf project retrieve start --metadata GenAiPlannerBundle --target-org my-org --output-dir check/ && find check/ -name "*.genAiPlannerBundle"
> ```

**What the script does:**
- Deploys your response formats and custom connection definition
- Retrieves your agent's existing config
- Wires the connection to your agent
- Deploys the updated config

Just deactivate your agent before running (the script will remind you) and reactivate it after.

## What does success look like?

After deploying, your app receives structured JSON instead of plain text — so you can render it as cards, buttons, carousels, or whatever UI your app supports.

For example, when your app sends a message through the Agent API with `"surfaceType": "Custom"`, the agent responds with something like:

```json
{
  "message": "Here are some options for you:",
  "choices": [
    {
      "title": "Premium Plan",
      "imageUrl": "https://example.com/premium.png",
      "actionText": "Select Premium"
    },
    {
      "title": "Basic Plan",
      "imageUrl": "https://example.com/basic.png",
      "actionText": "Select Basic"
    }
  ]
}
```

Your app parses this JSON and renders it however you want. The agent still handles the conversation logic — you just control how the response looks.

**What your app needs to do:**
- Start Agent API sessions with `"surfaceConfig": {"surfaceType": "Custom"}` ([see full API examples](./GUIDE.md#step-8-use-the-custom-connection-via-agent-api))
- Parse the structured JSON responses
- Handle plain text fallbacks (the agent won't always use a format)

## What the skill creates for you

You don't need to understand these files — the skill generates them and the deploy script handles the rest. But if you're curious:

| What it is | What it does |
|------------|-------------|
| Response format definitions | Tell the agent what structured outputs are available (e.g., "text choices", "image cards") |
| Connection definition | Describes your custom connection and links it to the response formats |
| Deploy script | Automates the entire deployment — one command does everything |
| Config files | Required by the Salesforce CLI to run the deployment |

## Available Response Formats

| Format | Use Case |
|--------|----------|
| Text Choices | Present 2-7 clickable text options |
| Choices with Images | Product cards, listings with thumbnails |
| Time Picker | Let users select a time slot |
| Custom JSON | Any structured output your client can parse |

## Manual Setup (without Claude Code)

If you prefer to build manually, see the full step-by-step guide: [GUIDE.md](./GUIDE.md)

## Deployment Notes

- Use `sf project deploy start --metadata-dir` (not `--manifest`) — these metadata types aren't in the CLI registry yet
- Deactivate your agent before updating its config, then reactivate after
- Keep response formats under 7 per connection — more than that and the agent struggles to pick the right one

## Examples

The [`examples/`](./examples/) directory includes:

- **[`examples/acme-portal/`](./examples/acme-portal/)** — Pre-generated metadata for a fictional client. Browse this to see exactly what the skill produces, or deploy it to a sandbox to test the full flow.
- **[`examples/demo-response.html`](./examples/demo-response.html)** — Open in a browser to see what structured responses look like when rendered. Shows all format types side by side.
- **[`examples/verify-connection.sh`](./examples/verify-connection.sh)** — Quick script to verify your custom connection works. Starts an Agent API session with `surfaceType: Custom` and prints "CONNECTED" or "FAILED."

```bash
./examples/verify-connection.sh <org-alias> <client-id> <client-secret> <agent-developer-name>
```

## Testing

**Verify deployment:** Open Agent Builder → Connections tab. Your custom connection should appear in the list. This confirms the metadata is deployed correctly.

**Quick check via script:** Run `examples/verify-connection.sh` to confirm the Agent API accepts your custom surface. Prerequisites:
- An External Client App (ECA) with OAuth scopes: `api`, `refresh_token`, `chatbot_api`, `sfap_api`
- Client Credentials Flow enabled with a Run As user that has "API Only access" permission
- See [GUIDE.md](./GUIDE.md#step-8-use-the-custom-connection-via-agent-api) for full ECA setup steps.

**Agent API (required for structured responses):** Start a session with `"surfaceConfig": {"surfaceType": "Custom"}` in your session creation call. The Agent API injects your response formats as tools and surface instructions into the LLM context. See [GUIDE.md](./GUIDE.md) for full API examples.

**Note:** The Agent Builder preview pane does NOT support custom connections. It always uses the default channel. You must test structured responses via the Agent API.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `RegistryError` on deploy | Use `--metadata-dir` not `--manifest` |
| `Cannot update record as Agent is Active` | Deactivate agent in Agent Builder first |
| `Surface does not exist in org` | Deploy surface/formats before updating the bundle |
| Responses come back as plain text | Ensure `surfaceConfig` is set in your session call. Agent Builder preview doesn't support custom connections — use the Agent API. |
| `duplicate value found: PlannerId` | Only one custom connection per agent is allowed. Remove existing custom surface before adding a new one. |

## License

MIT
