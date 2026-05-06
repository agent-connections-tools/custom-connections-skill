# Custom Connections Skill for Agentforce

A Claude Code skill that generates all the metadata you need to deploy a Custom Connection to your Agentforce agent. Answer 4 questions, get a deploy-ready package.

## What are Custom Connections?

Custom Connections let you define your own connection type with structured response formats — so your agent can respond with carousels, buttons, image cards, time pickers, or any UI component your client app supports. Instead of plain text, your app gets structured JSON it can render however it wants.

## Quick Start

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`) installed and authenticated to your org
- Pilot permissions enabled on your org (`AgentSurfSecondResPerm` + `AgentSurfThirdResPerm`) — ask your Salesforce rep
- An existing agent you want to add the custom connection to

### Usage

```bash
git clone https://github.com/anthropics/custom-connections-skill.git
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
4. What surface ID do you want?

It generates a complete deploy-ready package in `output/` with a one-command deploy script.

### Deploy

```bash
cd output
./deploy.sh <your-org-alias>
```

The script deploys your AiSurface and AiResponseFormats, then prints instructions to wire the connection to your existing agent.

## What gets generated

| File | Purpose |
|------|---------|
| `unpackaged/aiResponseFormats/*.aiResponseFormat` | Structured output schemas (choices, image cards, time picker, etc.) |
| `unpackaged/aiSurfaces/<Client>_<id>.aiSurface` | The custom connection definition with instructions and format references |
| `unpackaged/package.xml` | Metadata manifest for deployment |
| `sfdx-project.json` | Required by Salesforce CLI |
| `deploy.sh` | One-command deployment script |
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

- Use `sf project deploy start --metadata-dir` (not `--manifest`) — pilot types aren't in the CLI registry yet
- Deploy AiResponseFormats + AiSurface first, then wire to your agent bundle separately
- Deactivate your agent before updating its GenAiPlannerBundle, then reactivate after
- Keep response formats under 7 per connection — more than that and the agent struggles to pick the right one

## Testing

**Agent Builder (fastest):** Open your agent in Agent Builder. The custom connection appears in the connection dropdown. Select it and chat — you'll see structured responses in the preview.

**Agent API (end-to-end):** Start a session with `"surfaceConfig": {"surfaceType": "Custom"}` in your session creation call. See [GUIDE.md](./GUIDE.md) for full API examples.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `RegistryError` on deploy | Use `--metadata-dir` not `--manifest` |
| `Cannot update record as Agent is Active` | Deactivate agent in Agent Builder first |
| `Surface does not exist in org` | Deploy surface/formats before updating the bundle |
| Agent API returns 404 | Org needs Agent API routing provisioned |
| Responses come back as plain text | Check `surfaceConfig` in your session call |

## License

MIT
