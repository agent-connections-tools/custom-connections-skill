# Review Feedback — Making This Accessible to Non-Technical Users

**Reviewer:** Deep Work Agent (for Abhi Rathna)
**Date:** May 6, 2026
**Goal:** Make the repo easy for a non-techie user who has an Agentforce agent and wants to build a custom connection using this skill.

---

## Overall Impression

The repo is well-structured. The README's "Before/After" framing and "answer 3 questions" promise are strong — they set the right expectations. The GUIDE.md is appropriately labeled as a technical reference. The Claude Code skill prompt is well-designed (one question at a time, auto-generates the surface ID).

The main gap: **the README assumes mid-level developer confidence.** Someone who's built an agent in Agent Builder (clicks, not code) will hit friction at several points.

---

## Specific Feedback

### 1. Prerequisites — too sparse for non-devs

The current prerequisites are:
```
- Claude Code installed
- Salesforce CLI installed and authenticated
- An existing agent
```

A non-technical user won't know how to install either tool. Expand to:

- Link to Claude Code install instructions (one-liner: `npm install -g @anthropic-ai/claude-code` or whatever the current install is)
- Link to Salesforce CLI install page
- Briefly explain what "authenticated to your org" means — the `sf org login web` command is there but the context around it ("you only do this once") would help

### 2. "Agent bundle name" is an unknown term

The deploy command is:
```bash
./deploy.sh <your-org-alias> <your-agent-bundle-name>
```

A builder who configured their agent in Agent Builder UI has never seen the term "bundle name." They know their agent's *name* (e.g., "Customer Service Agent") but not its developer name or bundle identifier.

**Fix:** Add a short section — "Finding your agent bundle name" — with:
```bash
sf data query --query "SELECT DeveloperName FROM BotDefinition" --target-org my-org
```
This command already exists in the GUIDE.md (Step 4) and the deploy.sh error message, but surface it in the README before the deploy step to prevent confusion.

### 3. The "What gets generated" table is too technical

The table listing `.aiResponseFormat`, `.aiSurface`, `package.xml` etc. is useful for developers but intimidating for non-techies. They don't need to know file formats — they just need to know the skill creates everything for them.

**Fix:** Either move this below the deploy section (so the happy path isn't interrupted) or reframe it as "What the skill creates for you" with plain-English descriptions instead of file extensions.

### 4. "What does success look like" — reorder for clarity

The JSON response example is good. But the explanatory sentence ("Your app receives this structured data and renders it however you want — as cards, buttons, carousels, etc.") currently sits below the JSON block. Move it above the JSON to set the frame before showing code. Non-devs need context before they see code, not after.

### 5. Missing: "What do I need my app to do?"

The README explains what the *agent* side looks like, but a non-dev building a custom client app might not realize they need to:
- Handle the Agent API session creation with `surfaceConfig`
- Parse the structured JSON responses
- Build a fallback for plain text responses

This is covered in GUIDE.md Step 8, but the README's "Testing" section only mentions verification in Agent Builder. Add a brief "Your app needs to..." section or link directly to the GUIDE.md Agent API section.

### 6. One conceptual gap: "Why would I want this?"

The README explains *what* custom connections are but could be stronger on *when* to use them. Add a sentence like: "If your agent responds through the Agent API to a custom app (not Salesforce's built-in chat widget), custom connections let you control the response format." This helps someone decide if this is even relevant to their setup.

---

## Summary of Changes to Make

| Priority | Change | Where |
|----------|--------|-------|
| High | Expand prerequisites with install links and "you only do this once" context | README |
| High | Add "Finding your agent bundle name" helper before the deploy command | README |
| Medium | Add a sentence clarifying when/why you'd use this (Agent API custom apps) | README top |
| Medium | Move "What gets generated" table below the deploy step or simplify language | README |
| Low | Move the "your app renders it however you want" sentence above the JSON example | README |
| Low | Add brief "Your app needs to..." section linking to GUIDE.md Step 8 | README |

---

## Files That Are Fine As-Is

- **GUIDE.md** — Solid technical reference. The opening gate ("If you're using the skill, you don't need to read this") is correct.
- **.claude/commands/build-custom-connection.md** — Well-designed skill prompt. One question at a time, auto-generates surface ID, generates deploy script. No changes needed.
- **Troubleshooting table** (both README and GUIDE.md) — Valuable. Keep as-is.
- **deploy.sh design** — The pause for confirmation, stage markers, and error messages are all good UX for non-technical users.
