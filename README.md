# Custom Connections Skill for Agentforce

A Claude Code skill that generates all the metadata you need to deploy a Custom Connection to your Agentforce agent. Answer 3 questions, get a deploy-ready package.

## What problem does this solve?

**Before:** You want your agent to respond with rich UI (buttons, image cards, time pickers) instead of plain text. But setting this up means writing XML metadata files by hand, understanding Salesforce deployment commands, and wiring things together across multiple config layers. Even experienced developers find this tedious.

**After:** You run one skill, answer 3 plain-English questions, and get a fully automated deploy script that handles everything — including wiring the connection to your agent. No XML editing, no manual steps.

## What are Custom Connections?

Custom Connections let you define your own connection type with structured response formats — so your agent can respond with carousels, buttons, image cards, time pickers, or any UI component your client app supports. Instead of plain text, your app gets structured JSON it can render however it wants.

## Quick Start

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`) installed and authenticated to your org
- An existing agent you want to add the custom connection to

### First time setup

If you haven't logged in to your Salesforce org yet:

```bash
sf org login web --alias my-org
```

This opens a browser window where you sign in. The `--alias` flag gives your org a short name you'll use in deploy commands.

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

The script handles everything automatically:
- Deploys your response formats and custom connection definition
- Retrieves your agent's existing config
- Wires the connection to your agent
- Deploys the updated config

Just make sure to deactivate your agent before running (the script will remind you) and reactivate it after.

## What does success look like?

After deploying, when your app sends a message through the Agent API with `"surfaceType": "Custom"`, the agent can respond with structured JSON like this:

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

Your app receives this structured data and renders it however you want — as cards, buttons, carousels, etc.

## What gets generated

| File | Purpose |
|------|---------|
| `unpackaged/aiResponseFormats/*.aiResponseFormat` | Structured output schemas (choices, image cards, time picker, etc.) |
| `unpackaged/aiSurfaces/<Client>_<id>.aiSurface` | The custom connection definition with instructions and format references |
| `unpackaged/package.xml` | Metadata manifest for deployment |
| `sfdx-project.json` | Required by Salesforce CLI |
| `deploy.sh` | Fully automated deployment script |
| `README.md` | Connection-specific docs |

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

## Testing

**Verify deployment:** Open Agent Builder → Connections tab. Your custom connection should appear in the list. This confirms the metadata is deployed correctly.

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
