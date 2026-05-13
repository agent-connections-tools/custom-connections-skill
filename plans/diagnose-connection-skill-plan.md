# diagnose-connection — Skill Plan (v6)

**Author:** Abhi Rathna
**Date:** 2026-05-12
**Status:** Ready to build after validating open questions

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

These are real failure modes from testing. Every one produced a confusing or silent failure. Grouped by where the problem lives:

**Bundle-level failures** (checked by bundle-level checks):

| # | Failure Mode | What the Admin Sees | Root Cause |
|---|-------------|--------------------| -----------|
| 1 | Surface not wired to agent bundle | Connection doesn't appear in Agent Builder Connections tab | plannerSurfaces block missing from GenAiPlannerBundle |
| 2 | Agent is active during deploy | "Cannot update record as Agent is Active" error | Must deactivate before bundle changes |
| 3 | Duplicate plannerSurfaces | "Element plannerSurfaces is duplicated" deploy error | Tried adding a second custom surface (only one allowed) |
| 4 | Wrong bundle version / default version mismatch | Changes applied to v1 but Agent Builder reads v2 | Agent has multiple versions; need to target the version Agent Builder is using |
| 5 | Broken topic/plugin references | "Plugin not found" error on deploy | Bundle references a topic that was deleted. Also seen with localTopics referencing plugins that don't exist (BCU bundle). |
| 6 | API version mismatch across metadata | Cryptic deploy errors | Bundle deployed at v66.0, response format at v67.0. Platform throws unclear errors. |

**Surface-level failures** (checked by connection-level checks):

| # | Failure Mode | What the Admin Sees | Root Cause |
|---|-------------|--------------------| -----------|
| 7 | Response format referenced but doesn't exist in org | Agent ignores the format, falls back to plain text | Format deployed with "Unchanged" status but never actually created (org corruption) |
| 8 | Surface name doesn't match AiSurface developer name | Surface doesn't load, silent failure | Bundle references `AcmePortal_ACME01` but the AiSurface is named differently. Easy typo. |
| 9 | Malformed JSON schema in response format | Format deploys fine but agent silently ignores it | The JSON inside the `<input>` tag has a syntax error (missing quote, trailing comma). Cheap to catch with JSON.parse. |

**Environment-level failures** (caught by pre-flight checks):

| # | Failure Mode | What the Admin Sees | Root Cause |
|---|-------------|--------------------| -----------|
| 10 | Permission errors on retrieve | Skill fails silently or throws cryptic sf CLI error | User's profile can't access GenAiPlannerBundle metadata. Need pre-flight check or clear error message. |
| 11 | Org API version too old | Queries 404, metadata types not recognized | Org's metadata API version is older than when AiSurface/AiResponseFormat were introduced. |

**Removed from v1:** ECA/OAuth setup check — requires Connected App metadata which is a different retrieval path. Will revisit in v2.

---

## How It Works

### Input (3 questions, asked one at a time)

1. **What's your org alias?** (e.g., `my-dev-org`)
2. **What's your agent's developer name?** — help them find it:
   - Option A: Setup > Agents, look at the API name
   - Option B: Run `sf data query --query "SELECT DeveloperName FROM BotDefinition" --target-org <org>`
   - Same pattern as `build-custom-connection` — user provides the name directly, no wildcard retrieve needed
3. **Which connection do you want to diagnose?** (skill retrieves the bundle, lists all connections found, lets them pick — or "all" to check everything)

### Pre-flight Checks

Before running the full diagnosis, the skill verifies:

1. **Salesforce CLI is installed** — `sf --version` must succeed
2. **Org is authenticated** — `sf org display --target-org $ORG_ALIAS` must succeed
3. **Org API version supports Agent metadata** — check that the org's API version is >= 62.0 (when GenAiPlannerBundle, AiSurface, and AiResponseFormat were introduced). Detected via `sf org display` output. If too old, stop early with a clear message: "Your org's API version (vXX.0) doesn't support Agent metadata. Minimum required: v62.0."
4. **User has permission to retrieve metadata** — the initial `sf project retrieve start` will fail if the user's profile doesn't have metadata access. Catch this error specifically and report: "Could not retrieve agent metadata. Check that your user profile has the 'Modify Metadata Through Metadata API Functions' permission."

If any pre-flight check fails, stop and report the issue. Don't continue to the main checks.

**Mid-run permission failures:** Pre-flight checks verify bundle-level access, but some checks happen later (e.g., dry-run deploy for format validation). If a check hits a permission wall during execution, treat it as a warning ("Could not verify — insufficient permissions"), not a crash. Continue with the remaining checks and note which ones were skipped. The report should still be useful even if some checks couldn't run.

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

The skill produces two output formats from every run:

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
  ⚠ Agent has 2 versions — active: v2 (per defaultVersion), most recent: v2
    Context: If you deploy to a different version than the active one, Agent Builder won't reflect your changes.
    → Fix: Always deploy to the active version, or update defaultVersion after deploying.

FAILED (2)
  ✗ Response format "AcmePortalTimePicker_ACME01" not found in org
    → Fix: Redeploy the format using `sf project deploy start --metadata-dir`
    Context: Formats can show "Unchanged" on deploy but not actually exist. Redeploy with fresh names.
  ✗ adaptiveResponseAllowed is false on custom surface
    → Fix: Set to true in the plannerSurfaces block and redeploy the bundle
    Context: Required for custom connections to return structured responses.

=== 7 passed, 1 warning, 2 failed ===

Note: This diagnostic catches common configuration errors. If all checks pass
but the connection still doesn't work, test with `test-connection` or check
Agent Builder directly.
```

**2. JSON — saved to file for CI/CD pipelines:**

```json
{
  "$schema": "diagnose-connection-v1",
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

Both formats are produced on every run. The markdown is always displayed in the terminal. The JSON file is written silently — the skill reports the path at the end.

**HTML output deferred to v2.** Most people paste the markdown into Slack. Add HTML when someone asks for it.

---

## Technical Approach

### Metadata Retrieval

Single targeted retrieve — user provides the agent name, skill retrieves just that bundle:

```bash
sf project retrieve start --metadata "GenAiPlannerBundle:Agentforce_Service_Agent" --target-org $ORG_ALIAS --output-dir /tmp/diagnose/
```

**Why no wildcard listing:** `GenAiPlannerBundle:*` retrieves full bundle contents for every agent in the org, not just folder names. On orgs with many agents, that's a large payload for a listing step. Instead, the user provides the agent name directly (same pattern as `build-custom-connection`). If they don't know it, the skill helps them find it via `sf data query --query "SELECT DeveloperName FROM BotDefinition"`.

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

To check if response formats exist, re-deploy the surface that's already in the bundle:
1. Take the AiSurface XML from the retrieved bundle (the actual deployed surface, not a generated stub)
2. Run `sf project deploy start --metadata-dir ... --dry-run`
3. If dry-run succeeds → all referenced formats exist
4. If dry-run returns "does not exist" for a format → that format is missing

Using the real surface metadata (not a generated stub) avoids false signals from malformed generated XML. The dry-run validates exactly what's deployed.

**Open question (must validate before building):** What happens when you dry-run deploy a surface that already exists in the org? If it succeeds (treated as a no-op update), this approach works cleanly. If it fails (duplicate error), we need to generate a temporary surface with a unique name that references the same formats. See "Open Questions" section.

**Latency optimization:** Each dry-run deploy takes ~10-30s. For agents with multiple surfaces, batch all surfaces into a single dry-run. If it fails, fall back to individual dry-runs per surface to pinpoint which format is missing. Profile against test-org before finalizing.

**False positive limitation:** Dry-run deploy is the best available signal, not ground truth. In rare cases (failure mode #7 — "Unchanged" status corruption), a format may pass dry-run validation but still not function at runtime. The skill notes this in the report footer: "This diagnostic catches common configuration errors. If all checks pass but the connection still doesn't work, the issue may be runtime-specific — test with `test-connection` or check Agent Builder directly."

### Version Detection

The skill determines the active bundle version using:
1. **Primary:** Read the `defaultVersion` field from the bundle metadata (if present)
2. **Fallback:** If no `defaultVersion` field, use the highest-numbered version folder in the retrieved bundle

When multiple versions exist, the skill shows **both** the active version and the most recent version:

```
⚠ Agent has 3 versions — active: v1 (per defaultVersion), most recent: v3
  Context: You may have deployed to v3 but Agent Builder is still reading v1.
  → Fix: Update the defaultVersion field to v3, or redeploy your changes to v1.
```

This prevents confusion when `defaultVersion` points to v1 but the user just deployed changes to v3.

### Validation Logic

The skill prompt instructs Claude to:

1. Run pre-flight checks (CLI, org auth, API version, permissions)
2. Run `sf project retrieve start --metadata "GenAiPlannerBundle:<agent>"` to get the bundle
3. If retrieve fails, help user find the correct name via `sf data query --query "SELECT DeveloperName FROM BotDefinition"`
4. Parse the XML to extract plannerSurfaces, localTopicLinks, localTopics, version info
5. List connections found, let user pick which to diagnose (or "all")
6. Check bundle-level health (versions, activation, topic references, API version consistency)
7. For each surface: check surfaceType, adaptiveResponseAllowed, format references, instructions
8. For each surface with format references: validate format existence via dry-run deploy (using real surface metadata from bundle)
9. For each response format: JSON.parse the `<input>` field to catch malformed schemas
10. Compile results into both output formats (markdown to terminal, JSON to file)

### Error Handling

- **sf CLI not installed:** Stop with install instructions
- **Org auth expired:** Stop with `sf org login web --alias <alias>` instructions
- **Retrieve fails with permission error:** Report the specific permission needed
- **Retrieve fails with unknown error:** Show the raw error and suggest checking org connectivity
- **Dry-run deploy fails with unexpected error:** Report as a warning, not a failure (the format may exist but something else is wrong)
- **Mid-run permission failure:** If a check hits a permission wall after pre-flight passed, mark that check as "skipped" with reason, continue remaining checks

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
- **Does not produce HTML reports.** Markdown + JSON only in v1. HTML for sharing is a v2 candidate.

---

## Effort Estimate

| Task | Hours |
|------|-------|
| Skill prompt including dry-run validation logic (`.claude/commands/diagnose-connection.md`) | ~5 |
| JSON output template | ~0.5 |
| Testing against test-org (all 11 failure modes) | ~3.5 |
| Dry-run latency profiling (batch if needed) | ~1 |
| Documentation (README update, examples) | ~0.5 |
| **Total** | **~10.5** |

**Why 10.5:** The dry-run validation logic is part of the skill prompt — it's all instructions to Claude, not a separate script. Merged into one 5-hour block. Dropped HTML (deferred to v2), saving ~1 hour. Testing all 11 failure modes means reproducing each from scratch (deactivate, modify metadata, redeploy, run skill, verify) — that's 15-20 min per mode.

**Latency risk:** Each dry-run deploy takes ~10-30s. An agent with 5 formats across one surface = one batched dry-run. Multiple surfaces = one dry-run per surface. If profiling shows >2 minutes total, investigate parallelizing.

---

## Decisions Made

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **11 failure modes** in v1 | Every one is a real failure from testing. ECA/OAuth deferred — different metadata path. |
| 2 | **Read-only for v1** | Auto-fix on production orgs is a trust exercise. Ship diagnosis first, offer `--fix` in v2. |
| 3 | **Same repo** (`custom-connections-skill`) | Same metadata domain, same user persona. No reason to fragment. |
| 4 | **Dry-run deploy** for format validation | Tooling API doesn't support AiResponseFormat. Investigated and confirmed 2026-05-12. Dry-run is the only option. |
| 5 | **Two output formats** (markdown + JSON) | Markdown for terminal, JSON for CI/CD. HTML deferred to v2 — most people paste markdown into Slack. |
| 6 | **Single-agent scope** | Multi-agent audit is v2. Keeps v1 focused and the prompt manageable. |
| 7 | **`/project:diagnose-connection`** namespace | Migrates to `/agentforce:` with the full skill family when the namespace is adopted. |
| 8 | **Direct agent name input** (no wildcard listing) | `GenAiPlannerBundle:*` retrieves full bundle contents for every agent — not lightweight. User provides name directly, same pattern as `build-custom-connection`. |
| 9 | **`defaultVersion` field** for version detection | Falls back to highest-numbered version if field is absent. Explained in output when multiple versions exist. |
| 10 | **Pre-flight checks** before diagnosis | Catches CLI, auth, API version, and permission issues early with clear error messages instead of cryptic failures mid-run. |
| 11 | **`$schema` field** in JSON output | Once CI pipelines depend on this JSON, any field rename breaks them. Schema version lets consumers detect changes. Lesson learned from audit-agent. |
| 12 | **Batch dry-run deploys** when possible | One dry-run with all formats referenced beats N individual dry-runs. Fall back to individual on failure to pinpoint which format is missing. |
| 13 | **Use real surface metadata** for dry-run | Deploy the actual AiSurface from the bundle in dry-run mode, not a generated stub. Validates exactly what's deployed, avoids false signals from malformed generated XML. |

---

## Open Questions

Two questions must be validated against test-org before building:

| # | Question | Why It Matters | Fallback If It Fails |
|---|----------|---------------|---------------------|
| 1 | **Does dry-run deploy of an existing AiSurface succeed or fail?** | The format validation strategy uses the real surface XML from the bundle. If dry-run treats it as a duplicate and errors, we need to generate a temporary surface with a unique name that references the same formats instead. | Generate temp surface: `DiagnoseCheck_<timestamp>.aiSurface` referencing the same formats, dry-run deploy it, then discard. |
| 2 | **Is `GenAiPlannerBundle:*` retrieve payload acceptable?** | We dropped the wildcard from the skill flow, but if the skill can't find the bundle by the name the user provides, the fallback help message suggests `BotDefinition` SOQL. Worth confirming this query works and returns the right developer names. | If BotDefinition query doesn't return bundle-compatible names, document the exact mapping (BotDefinition.DeveloperName → GenAiPlannerBundle name). |

**Previously resolved:**
- Tooling API availability → not available, using dry-run deploy
- ECA/OAuth scope → deferred to v2
- Output format → markdown + JSON (HTML deferred to v2)
- Version detection → `defaultVersion` field + fallback

---

## Changelog

- **v1 (2026-05-12):** Initial draft — 7 failure modes, markdown output only.
- **v2 (2026-05-12):** First review — added 3 failure modes (#8-10), 3 output formats, resolved Tooling API (dry-run deploy), scoped to single-agent.
- **v3 (2026-05-12):** Second review — added failure mode #11 (malformed JSON schema), clarified wildcard vs. specific bundle retrieval, documented version detection logic.
- **v4 (2026-05-12):** Consolidated revision — added pre-flight checks section, error handling section, expanded validation logic to 10-step sequence, restructured decisions as table, added open questions section (all resolved), expanded effort estimate with task breakdown, enriched JSON output example with full check list and fix fields.
- **v5 (2026-05-12):** Fourth review — bumped effort to 12h (realistic testing estimate), added `$schema` to JSON output, added mid-run permission graceful degradation, version detection now shows both active and most recent versions, added dry-run batching strategy with latency profiling, added false positive caveat in report footer.
- **v6 (2026-05-12):** Fifth review — dropped wildcard listing (user provides agent name directly, same as build-custom-connection), cut HTML output from v1, grouped failure modes by level (bundle/surface/environment), merged effort estimate line items (10.5h), use real surface metadata for dry-run instead of generated stub, added 2 open questions to validate before building.
