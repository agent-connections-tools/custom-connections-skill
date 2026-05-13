# diagnose-connection — Skill Plan (v2)

**Author:** Abhi Rathna
**Date:** 2026-05-12
**Status:** Ready to build (v3 — pending final approval)

---

## What This Skill Does

Given an org alias and agent name, the skill retrieves the agent's metadata, inspects all wired connections (custom and standard), validates that everything is correctly configured, and reports exactly what's broken and how to fix it.

Think of it as a health check for Agent Connections.

---

## Who It's For

**Primary persona:** Salesforce Admins who set up connections in Agent Builder and hit "it doesn't work" with no clear error message.

**Secondary persona:** Developers debugging custom connections they've deployed via metadata API.

---

## The Problems It Solves

These are real failure modes from testing. Every one produced a confusing or silent failure:

| # | Failure Mode | What the Admin Sees | Root Cause |
|---|-------------|--------------------| -----------|
| 1 | Response format referenced but doesn't exist in org | Agent ignores the format, falls back to plain text | Format deployed with "Unchanged" status but never actually created (org corruption) |
| 2 | Surface not wired to agent bundle | Connection doesn't appear in Agent Builder Connections tab | plannerSurfaces block missing from GenAiPlannerBundle |
| 3 | Agent is active during deploy | "Cannot update record as Agent is Active" error | Must deactivate before bundle changes |
| 4 | Duplicate plannerSurfaces | "Element plannerSurfaces is duplicated" deploy error | Tried adding a second custom surface (only one allowed) |
| 5 | Wrong bundle version / default version mismatch | Changes applied to v1 but Agent Builder reads v2 | Agent has multiple versions; need to target the version Agent Builder is using |
| 6 | Broken topic/plugin references | "Plugin not found" error on deploy | Bundle references a topic that was deleted. Also seen with localTopics referencing plugins that don't exist (BCU bundle). |
| 7 | Surface name doesn't match AiSurface developer name | Surface doesn't load, silent failure | Bundle references `AcmePortal_ACME01` but the AiSurface is named differently. Easy typo. |
| 8 | API version mismatch across metadata | Cryptic deploy errors | Bundle deployed at v66.0, response format at v67.0. Platform throws unclear errors. |
| 9 | Permission errors on retrieve | Skill fails silently or throws cryptic sf CLI error | User's profile can't access GenAiPlannerBundle metadata. Need pre-flight check or clear error message. |
| 10 | Org API version too old | Queries 404, metadata types not recognized | Org's metadata API version is older than when AiSurface/AiResponseFormat were introduced. |
| 11 | Malformed JSON schema in response format | Format deploys fine but agent silently ignores it | The JSON inside the `<input>` tag has a syntax error (missing quote, trailing comma). Cheap to catch with JSON.parse. |

**Removed from v1:** ECA/OAuth setup check — requires Connected App metadata which is a different retrieval path. Will revisit in v2.

---

## How It Works

### Input (3 questions, asked one at a time)

1. **What's your org alias?** (e.g., `my-dev-org`)
2. **What's your agent name?** (skill retrieves all bundles, lists available agents, lets them pick — or auto-selects if only one exists)
3. **Which connection do you want to diagnose?** (lists all connections found on the agent, or "all" to check everything)

### Checks Performed

The skill runs these checks in order and reports results as a checklist:

**Bundle-level checks:**
- [ ] Agent bundle exists and is retrievable
- [ ] Bundle versions listed (v1, v2, etc.) with which is the default/active version (determined by the `defaultVersion` field in the bundle metadata; if absent, highest-numbered version is assumed active)
- [ ] Agent activation status (active vs. deactivated)
- [ ] All localTopicLinks have matching localTopics entries (no orphaned plugin references)
- [ ] All localTopics reference valid plugins (no "Plugin not found" failures)
- [ ] API version consistent across bundle and related metadata

**Connection-level checks (per surface):**
- [ ] Surface is listed in plannerSurfaces
- [ ] Surface type matches expected value (Custom, MessagingForInAppAndWeb, Voice, etc.)
- [ ] adaptiveResponseAllowed is set correctly
- [ ] Surface developer name in bundle matches the deployed AiSurface name exactly
- [ ] All response formats referenced by the surface exist in the org (via dry-run deploy validation)
- [ ] Response format JSON schemas are valid (JSON.parse the `<input>` field — catches missing quotes, trailing commas)
- [ ] Surface instructions are present and non-empty

**Custom connection extras:**
- [ ] Only one custom surface wired (platform limit)
- [ ] No duplicate plannerSurfaces entries

### Scope

**v1 is single-agent.** The skill diagnoses one agent at a time. Multi-agent ("audit all agents in this org") is a v2 feature.

### Output Formats

The skill produces three output formats:

**1. Markdown (default) — displayed in terminal:**

```
=== Connection Health Report: Agentforce_Service_Agent ===

PASSED (7)
  ✓ Agent bundle retrieved (v2)
  ✓ Agent is deactivated (safe to modify)
  ✓ All 4 topic references valid
  ✓ Messaging connection wired correctly
  ✓ Web connection wired correctly
  ✓ Custom surface "AcmePortal_ACME01" exists in org
  ✓ 3/3 response formats found

WARNINGS (1)
  ⚠ Agent has 2 versions (v1, v2) — changes should target v2
    Context: Agent Builder may read from the latest version, not the one you deployed to.
    See: GUIDE.md > Agent Versioning

FAILED (2)
  ✗ Response format "AcmePortalTimePicker_ACME01" not found in org
    → Fix: Redeploy the format using `sf project deploy start --metadata-dir`
    Context: Formats can show "Unchanged" on deploy but not actually exist. Redeploy with fresh names.
  ✗ adaptiveResponseAllowed is false on custom surface
    → Fix: Set to true in the plannerSurfaces block and redeploy the bundle
    Context: Required for custom connections to return structured responses.

=== 7 passed, 1 warning, 2 failed ===
```

**2. HTML — saved to file for sharing via Slack/email:**

Same content rendered as a styled HTML report (similar to demo-response.html). Saved to `/tmp/diagnose-report.html`.

**3. JSON — for CI/CD pipelines:**

```json
{
  "agent": "Agentforce_Service_Agent",
  "version": "v2",
  "passed": 7,
  "warnings": 1,
  "failed": 2,
  "checks": [
    { "name": "bundle_retrieved", "status": "passed", "detail": "v2" },
    { "name": "response_format_exists", "status": "failed", "detail": "AcmePortalTimePicker_ACME01 not found" }
  ]
}
```

Saved to `/tmp/diagnose-report.json`. Enables `if any checks fail, fail the pipeline` in CI.

---

## Technical Approach

### Metadata Retrieval

```bash
# Step 1: Retrieve all bundles (lightweight — just folder names, used to list available agents)
sf project retrieve start --metadata "GenAiPlannerBundle:*" --target-org $ORG_ALIAS --output-dir /tmp/diagnose/

# Step 2: Once the user picks an agent, retrieve just that bundle for detailed inspection
sf project retrieve start --metadata "GenAiPlannerBundle:Agentforce_Service_Agent" --target-org $ORG_ALIAS --output-dir /tmp/diagnose/
```

**Note:** Wildcard retrieve (`*`) is only used for the initial agent listing. Detailed inspection always targets the specific bundle to avoid pulling excessive data on orgs with many agents.

### Key Constraint: AiResponseFormat and AiSurface can't be queried or retrieved by name

**Investigated 2026-05-12 against test-org. Results:**

| Method | Result |
|--------|--------|
| Tooling API query (`SELECT FROM AiResponseFormat`) | "sObject type not supported" |
| Standard SOQL query | "sObject type not supported" |
| `sf project retrieve start --metadata AiResponseFormat:*` | CLI registry blocks it |
| `sf project retrieve start --manifest package.xml` | CLI registry blocks it |
| `sf org list metadata-types` | AiResponseFormat IS listed — the org knows about it |
| `sf project deploy start --metadata-dir` | **Works** — bypasses CLI registry |

**Chosen approach: dry-run deploy validation.**

To check if a response format exists:
1. Generate a minimal AiSurface XML that references the format name
2. Run `sf project deploy start --metadata-dir ... --dry-run`
3. If dry-run succeeds → format exists
4. If dry-run returns "does not exist" → format is missing

This is the same mechanism `build-custom-connection` uses for deployment. It's ugly but it's the only reliable method until Salesforce adds AiResponseFormat to the CLI registry.

### Validation Logic

The skill prompt instructs Claude to:
1. Run `sf project retrieve start` to get all bundles
2. Parse the XML to extract plannerSurfaces, localTopicLinks, localTopics
3. Check bundle-level health (versions, activation, topic references, API versions)
4. For each surface, check surfaceType, adaptiveResponseAllowed, format references
5. For custom surfaces, validate format existence via dry-run deploy
6. Compile results into all three output formats

### Where It Lives

```
custom-connections-skill/
├── .claude/commands/
│   ├── build-custom-connection.md    # existing
│   └── diagnose-connection.md        # new
```

Same repo, same pattern. User runs `/project:diagnose-connection` from the repo root.

### Namespace

Skill command is `/project:diagnose-connection` for now. When the `/agentforce:` namespace is adopted across the skill family (per the skills repo v2 plan), both skills will migrate together.

---

## What It Does NOT Do

- **Does not fix problems automatically.** Reports what's wrong and how to fix it. Auto-fix is a v2 consideration — read-only builds trust first.
- **Does not test the Agent API end-to-end.** That's `test-connection`.
- **Does not check ECA/OAuth configuration.** Different metadata path. v2 candidate.
- **Does not modify any org metadata.** Read-only, safe to run against production orgs.
- **Does not audit multiple agents.** v1 is single-agent. Multi-agent audit is v2.

---

## Effort Estimate

- Skill prompt (`.claude/commands/diagnose-connection.md`): ~3 hours
- Dry-run deploy validation logic: ~2 hours (the format existence check is the trickiest part)
- HTML + JSON output templates: ~1 hour
- Testing against test-org: ~1 hour
- Documentation (README update, examples): ~30 minutes

**Total: ~8 hours**

---

## Decisions Made

1. **Check list** — 11 failure modes. Removed ECA check from v1. Added: localized topic/plugin mismatches, default version mismatch, surface name typos, API version mismatch, permission errors on retrieve, org API version too old, malformed JSON schema in response format.
2. **Read-only for v1** — confirmed. No auto-fix.
3. **Same repo** — confirmed. `custom-connections-skill`.
4. **Tooling API** — investigated and resolved. Not available. Using dry-run deploy validation instead.
5. **Output formats** — markdown (terminal), HTML (sharing), JSON (CI/CD).
6. **Scope** — single-agent for v1. Multi-agent audit in v2.
7. **Namespace** — `/project:diagnose-connection` for now. Migrates to `/agentforce:` with the skill family.
8. **Wildcard retrieve** — only used for initial agent listing. Detailed inspection targets the specific bundle to avoid pulling excessive data.
9. **Version detection** — uses `defaultVersion` field from bundle metadata; falls back to highest-numbered version if absent.

---

## Changelog

- **v1 (2026-05-12):** Initial draft.
- **v2 (2026-05-12):** Incorporated review feedback — added 4 failure modes, 3 output formats, resolved Tooling API question (not available, using dry-run deploy), scoped to single-agent, updated effort estimate.
- **v3 (2026-05-12):** Third round of feedback — added failure mode #11 (malformed JSON schema), clarified wildcard vs. specific bundle retrieval, documented version detection logic (`defaultVersion` field), updated decisions list.
