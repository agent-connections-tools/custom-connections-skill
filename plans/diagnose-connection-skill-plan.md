# diagnose-connection — Skill Plan (v4)

**Author:** Abhi Rathna
**Date:** 2026-05-12
**Status:** Ready to build (pending final review)

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

### Pre-flight Checks

Before running the full diagnosis, the skill verifies:

1. **Salesforce CLI is installed** — `sf --version` must succeed
2. **Org is authenticated** — `sf org display --target-org $ORG_ALIAS` must succeed
3. **Org API version supports Agent metadata** — check that the org's API version is >= 62.0 (when GenAiPlannerBundle, AiSurface, and AiResponseFormat were introduced). Detected via `sf org display` output. If too old, stop early with a clear message: "Your org's API version (vXX.0) doesn't support Agent metadata. Minimum required: v62.0."
4. **User has permission to retrieve metadata** — the initial `sf project retrieve start` will fail if the user's profile doesn't have metadata access. Catch this error specifically and report: "Could not retrieve agent metadata. Check that your user profile has the 'Modify Metadata Through Metadata API Functions' permission."

If any pre-flight check fails, stop and report the issue. Don't continue to the main checks.

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
- [ ] Response format JSON schemas are valid (JSON.parse the `<input>` field — catches missing quotes, trailing commas, invalid structure)
- [ ] Surface instructions are present and non-empty

**Custom connection extras:**
- [ ] Only one custom surface wired (platform limit)
- [ ] No duplicate plannerSurfaces entries

### Scope

**v1 is single-agent.** The skill diagnoses one agent at a time. Multi-agent ("audit all agents in this org") is a v2 feature.

### Output

The skill produces three output formats from every run:

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

Same content rendered as a styled HTML report. Saved to `/tmp/diagnose-report.html`.

**3. JSON — saved to file for CI/CD pipelines:**

```json
{
  "agent": "Agentforce_Service_Agent",
  "version": "v2",
  "timestamp": "2026-05-12T14:30:00Z",
  "passed": 7,
  "warnings": 1,
  "failed": 2,
  "checks": [
    { "name": "bundle_retrieved", "status": "passed", "detail": "v2" },
    { "name": "activation_status", "status": "passed", "detail": "deactivated" },
    { "name": "topic_references", "status": "passed", "detail": "4/4 valid" },
    { "name": "response_format_exists", "status": "failed", "detail": "AcmePortalTimePicker_ACME01 not found", "fix": "Redeploy the format using sf project deploy start --metadata-dir" },
    { "name": "adaptive_response_allowed", "status": "failed", "detail": "false on custom surface", "fix": "Set to true in plannerSurfaces block and redeploy" }
  ]
}
```

Saved to `/tmp/diagnose-report.json`. Enables `if any checks fail, fail the pipeline` in CI.

All three formats are produced on every run. The markdown is always displayed in the terminal. The HTML and JSON files are written silently — the skill reports the paths at the end.

---

## Technical Approach

### Metadata Retrieval

Two-phase approach to avoid pulling excessive data on orgs with many agents:

```bash
# Phase 1: List available agents (lightweight — just folder names)
sf project retrieve start --metadata "GenAiPlannerBundle:*" --target-org $ORG_ALIAS --output-dir /tmp/diagnose-list/

# Phase 2: Once the user picks an agent, retrieve just that bundle for detailed inspection
sf project retrieve start --metadata "GenAiPlannerBundle:Agentforce_Service_Agent" --target-org $ORG_ALIAS --output-dir /tmp/diagnose/
```

Phase 1 wildcard retrieve is only used to populate the agent selection list. All detailed parsing and checks run against the Phase 2 single-bundle retrieve.

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

This is the same mechanism `build-custom-connection` uses for deployment. It's the only reliable method until Salesforce adds AiResponseFormat to the CLI registry.

### Version Detection

The skill determines the active bundle version using:
1. **Primary:** Read the `defaultVersion` field from the bundle metadata (if present)
2. **Fallback:** If no `defaultVersion` field, use the highest-numbered version folder in the retrieved bundle

When multiple versions exist, the skill warns the user and tells them which version to target.

### Validation Logic

The skill prompt instructs Claude to:

1. Run pre-flight checks (CLI, org auth, API version, permissions)
2. Run `sf project retrieve start --metadata "GenAiPlannerBundle:*"` to list agents
3. Present the list, let user pick (or auto-select if only one)
4. Run `sf project retrieve start --metadata "GenAiPlannerBundle:<selected>"` to get the full bundle
5. Parse the XML to extract plannerSurfaces, localTopicLinks, localTopics, version info
6. Check bundle-level health (versions, activation, topic references, API version consistency)
7. For each surface: check surfaceType, adaptiveResponseAllowed, format references, instructions
8. For each response format referenced: validate existence via dry-run deploy
9. For each response format in the bundle: JSON.parse the `<input>` field to catch malformed schemas
10. Compile results into all three output formats (markdown to terminal, HTML + JSON to files)

### Error Handling

- **sf CLI not installed:** Stop with install instructions
- **Org auth expired:** Stop with `sf org login web --alias <alias>` instructions
- **Retrieve fails with permission error:** Report the specific permission needed
- **Retrieve fails with unknown error:** Show the raw error and suggest checking org connectivity
- **Dry-run deploy fails with unexpected error:** Report as a warning, not a failure (the format may exist but something else is wrong)

### Where It Lives

```
custom-connections-skill/
├── .claude/commands/
│   ├── build-custom-connection.md    # existing skill
│   └── diagnose-connection.md        # new skill
```

Same repo, same pattern. User runs `/project:diagnose-connection` from the repo root.

### Namespace

Skill command is `/project:diagnose-connection` for now. When the `/agentforce:` namespace is adopted across the skill family (per the skills repo v2 plan), both skills will migrate together.

---

## What It Does NOT Do

- **Does not fix problems automatically.** Reports what's wrong and how to fix it. Auto-fix is a v2 consideration — read-only builds trust first.
- **Does not test the Agent API end-to-end.** That's `test-connection` (a separate skill).
- **Does not check ECA/OAuth configuration.** Different metadata path. v2 candidate.
- **Does not modify any org metadata.** Read-only (dry-run deploys don't write), safe to run against production orgs.
- **Does not audit multiple agents.** v1 is single-agent. Multi-agent audit is v2.

---

## Effort Estimate

| Task | Hours |
|------|-------|
| Skill prompt (`.claude/commands/diagnose-connection.md`) | ~3 |
| Dry-run deploy validation logic (format existence check) | ~2 |
| HTML + JSON output templates | ~1 |
| Testing against test-org (all 11 failure modes) | ~1.5 |
| Documentation (README update, examples) | ~0.5 |
| **Total** | **~8** |

The dry-run deploy validation is the trickiest part — it needs to generate valid temporary metadata, run the deploy, parse the output, and clean up. The rest is straightforward prompt engineering following the `build-custom-connection` pattern.

---

## Decisions Made

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **11 failure modes** in v1 | Every one is a real failure from testing. ECA/OAuth deferred — different metadata path. |
| 2 | **Read-only for v1** | Auto-fix on production orgs is a trust exercise. Ship diagnosis first, offer `--fix` in v2. |
| 3 | **Same repo** (`custom-connections-skill`) | Same metadata domain, same user persona. No reason to fragment. |
| 4 | **Dry-run deploy** for format validation | Tooling API doesn't support AiResponseFormat. Investigated and confirmed 2026-05-12. Dry-run is the only option. |
| 5 | **Three output formats** always produced | Markdown for terminal, HTML for sharing, JSON for CI/CD. No flags needed — all three on every run. |
| 6 | **Single-agent scope** | Multi-agent audit is v2. Keeps v1 focused and the prompt manageable. |
| 7 | **`/project:diagnose-connection`** namespace | Migrates to `/agentforce:` with the full skill family when the namespace is adopted. |
| 8 | **Two-phase retrieve** | Wildcard only for agent listing. Specific bundle retrieve for inspection. Avoids pulling excessive data on orgs with many agents. |
| 9 | **`defaultVersion` field** for version detection | Falls back to highest-numbered version if field is absent. Explained in output when multiple versions exist. |
| 10 | **Pre-flight checks** before diagnosis | Catches CLI, auth, API version, and permission issues early with clear error messages instead of cryptic failures mid-run. |

---

## Open Questions

None. All blocking questions have been resolved:
- Tooling API availability → resolved (not available, using dry-run deploy)
- ECA/OAuth scope → resolved (deferred to v2)
- Output format → resolved (all three, always)
- Wildcard retrieve performance → resolved (two-phase approach)
- Version detection → resolved (`defaultVersion` field + fallback)

---

## Changelog

- **v1 (2026-05-12):** Initial draft — 7 failure modes, markdown output only.
- **v2 (2026-05-12):** First review — added 3 failure modes (#8-10), 3 output formats, resolved Tooling API (dry-run deploy), scoped to single-agent.
- **v3 (2026-05-12):** Second review — added failure mode #11 (malformed JSON schema), clarified wildcard vs. specific bundle retrieval, documented version detection logic.
- **v4 (2026-05-12):** Consolidated revision — added pre-flight checks section, error handling section, expanded validation logic to 10-step sequence, restructured decisions as table, added open questions section (all resolved), expanded effort estimate with task breakdown, enriched JSON output example with full check list and fix fields.
