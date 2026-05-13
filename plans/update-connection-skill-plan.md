# update-connection — Skill Plan (v1)

**Author:** Abhi Rathna
**Date:** 2026-05-13
**Status:** Draft for review

---

## What This Skill Does

Modifies an existing custom connection without rebuilding it from scratch. The skill pulls the connection's current state from the org, shows the user what's already deployed, lets them pick what to add, then deploys the change without clobbering the existing formats.

The fourth verb in the skill family:

```
build-custom-connection      diagnose-connection       update-connection         test-connection
       (create)          →     (verify config)     →    (modify in place)    →    (verify runtime)
   "Deploy new metadata"    "Is it wired correctly?"  "Add formats safely"    "Does it actually work?"
```

V1 supports **one verb only — adding a response format**. The architecture (retrieve → parse → diff → redeploy) is built to extend cleanly to remove/modify operations in v2 without rework.

---

## Who It's For

**Primary persona:** Salesforce Admins who built a custom connection with `build-custom-connection` and now want to add a new format (date picker, image carousel, etc.) without re-running build from scratch and risking duplication or clobbering.

**Secondary persona:** Developers iterating on a connection's response formats during agent development.

---

## The State-Flip Map (full skill family)

The state requirement is now a first-class concept across the family:

| Skill | Agent state required | Why |
|------|------|------|
| `build-custom-connection` | **Deactivated** | Deploys bundle metadata; active agents reject metadata updates |
| `diagnose-connection` | **Deactivated** | So the user can fix what the diagnostic surfaces without re-deactivating |
| `update-connection` (this skill) | **Deactivated** | Deploys bundle metadata; same constraint as build |
| `test-connection` | **Active** | Sends real messages through the live agent |

**The user workflow:** deactivate → build/diagnose/update freely → activate → test → if something's wrong, deactivate again and loop. This skill belongs in the deactivated phase of that cycle.

The skill calls out the state inversion the same way `test-connection` does: explicit reference to the other skills, plain-English fix instruction, status display inline before any deploy.

---

## Why "stateful merge" is the architectural challenge

The other skills in the trio are stateless:
- `build-custom-connection` generates files from scratch
- `diagnose-connection` reads org state but never writes
- `test-connection` exercises the runtime, doesn't touch metadata

This skill is the first that **reads org state and writes back to it**. The hard part isn't "deploy a new file" — it's "deploy a new file without breaking what's already there."

Specifically: the AiSurface XML lists every response format the connection uses. If you regenerate the surface from scratch (the build skill's pattern), you can easily drop a format the user previously deployed manually or via a separate flow. The skill must:

1. Retrieve the current `AiSurface` XML
2. Parse the existing `<responseFormats>` entries
3. Generate the new format's `.aiResponseFormat` file
4. Append (not replace) the new format to the surface's `<responseFormats>` list
5. Deploy both files together

Any operation that modifies an existing connection — add, remove, swap — needs this same retrieve-parse-merge-write loop. Building it once correctly for "add" means v2's "remove" and "modify" verbs slot in cleanly.

---

## How It Works

### Inputs (4 questions, asked one at a time)

1. **What's your org alias?** Same as the other skills.

2. **What's your agent's developer name?** Help them find it (Setup → Agents OR `sf data query`).

3. **Which custom connection do you want to update?** The skill retrieves the agent's bundle (with multi-version fallback, same as diagnose) and lists every custom connection on the agent:
   ```
   1. AcmePortal_ACME01 (custom) — currently has 2 response formats
   2. BaxterCreditUnion_BCU01 (custom) — currently has 3 response formats
   ```
   Standard connections (Telephony, etc.) are not listed — v1 doesn't support them. If the agent has no custom connection, the skill exits early with a message: "This agent has no custom connections. Use `/project:build-custom-connection` to create one."

4. **What format do you want to add?** Show the same options as `build-custom-connection`:
   - Text choices (2-7 clickable options)
   - Choices with images (product cards, listings with thumbnails)
   - Time picker (select a time slot)
   - Custom JSON (describe the structure you want)

   The skill explains what's already on the connection so the user doesn't add a duplicate:
   > "Your AcmePortal_ACME01 connection already has Text Choices and Choices with Images. Adding the same format again would create a duplicate. Pick one of the others, or pick Custom JSON to define a new shape."

### Pre-flight Checks

Run these before any retrieve. Stop early on failure.

1. **Salesforce CLI installed** — `sf --version`
2. **Org connected** — `sf org display --target-org $ORG_ALIAS`
3. **API version ≥ 62.0** — from org display
4. **User can retrieve metadata** — caught when the bundle retrieve runs

> **State requirement:** The agent must be **deactivated** before this skill runs. Same as `build-custom-connection` and `diagnose-connection`. After deploying the change, the user reactivates the agent and runs `test-connection` to verify the new format works.

### Stateful Merge Sequence

This is the core of the skill. Eight steps:

**1. Retrieve the agent bundle** (same pattern as diagnose-connection's multi-version fallback):
```bash
sf project retrieve start --metadata "GenAiPlannerBundle:$BUNDLE_NAME" --target-org $ORG_ALIAS --output-dir retrieved/
```

**2. Confirm the agent is deactivated:** query `BotVersion` for `Status = 'Active'`. If active, stop with the state-flip message. **Note:** the inversion is *to* `test-connection` (which needs active), not *from* it — same direction as build/diagnose.

**3. Parse the bundle XML** to find the chosen `<plannerSurfaces>` entry and extract the surface name (e.g., `AcmePortal_ACME01`).

**4. Discover what's currently on the surface.** This is the hardest step in the skill. The bundle XML tells us the surface *name* (e.g., `AcmePortal_ACME01`) but **not** its current `<responseFormats>` list. AiSurface metadata can't be retrieved by name through the CLI (the CLI registry blocks it — confirmed during `diagnose-connection` build).

The skill reuses `diagnose-connection`'s two-method approach to infer the current state:

**Method A — naming convention scan (fast, works for skill-built connections):**
- List all `AiResponseFormat` metadata in the org: `sf org list metadata --metadata-type AiResponseFormat --target-org $ORG_ALIAS`
- Filter by the surface's naming prefix and suffix. E.g., for `AcmePortal_ACME01`, look for `AcmePortal*_ACME01.aiResponseFormat`.
- If the connection was built with `build-custom-connection`, the naming convention holds and Method A finds every format. Fast.
- If the connection was built by hand or with non-standard naming, Method A misses formats. Falls back to Method B.

**Method B — dry-run deploy probe (slower, more robust):**
- Build a temporary surface XML that references the formats from Method A's candidate list
- Run `sf project deploy start --metadata-dir <temp> --target-org $ORG_ALIAS --dry-run`
- The dry-run output names any formats that don't exist (`"Response format does not exist in org: <name>"`). Anything not flagged exists.
- Use the result as the authoritative current-formats list.

**Why both methods:** Method A handles the 95% case (skill-built connections) quickly. Method B catches the rare case where a connection has manually-named formats. Same pattern proven in `diagnose-connection`.

**Limitation worth surfacing in the report:** Neither method can retrieve the *raw XML* of the existing AiSurface — only the list of formats it references. The skill regenerates the AiSurface XML from scratch each deploy, copying the existing format list and appending the new one. This means any custom fields the user added to the surface XML by hand (e.g., custom `<description>` text) will be lost. v1 acknowledges this as a known limitation; v2 could address it if the CLI registry adds AiSurface support.

### Step 4a: Detection confidence checkpoint (the safety rail)

Method A is a heuristic — it works for skill-built connections but can miss formats with non-conventional naming. For a read-only skill (diagnose) a miss just means an incomplete report. For this skill, **a miss means data loss on deploy**: the regenerated surface won't reference the format we couldn't detect, and the next deploy disconnects it from the connection.

The skill addresses this with an explicit user confirmation **before any deploy**:

```
I found 2 existing formats on your connection:
  1. AcmePortalChoices_ACME01 (Text Choices)
  2. AcmePortalChoicesWithImages_ACME01 (Choices with Images)

If this doesn't match what you expect, say "stop" and I'll exit
without changing anything. Otherwise I'll add the new format you
picked and redeploy.
```

The user confirms the detected state before anything is deployed. This turns the unknown-unknowns problem (formats Method A can't detect) into a UX gate rather than silent clobbering.

**Special case — Method A finds zero formats** but the bundle references the surface (so it must have at least one format wired). The skill stops with a stronger message:

```
I couldn't detect any existing response formats on your connection,
but your agent's configuration says this connection is wired up. This
usually means your formats use non-standard naming I don't recognize.

Continuing would regenerate your connection's configuration without
those formats — disconnecting them from your connection.

I'm stopping here to avoid that. To proceed, you'd need to either
rename your formats to follow the convention <ClientName><Type>_<SurfaceId>,
or wait for the v2 update that supports non-conventional naming.
```

This converts a silent failure mode into an explicit guardrail.

**5. Generate the new format's `.aiResponseFormat` file** using the same templates as `build-custom-connection`. The file follows the existing naming convention (`<ClientName><FormatType>_<SurfaceId>`).

**6. Generate the merged AiSurface XML.** Take the existing `<responseFormats>` entries from the parsed surface metadata, append the new format's developer name, write the merged XML.

**7. Build the package and deploy:**
```bash
sf project deploy start --metadata-dir <merged-output> --target-org $ORG_ALIAS
```

**8. Verify the new format is in the deployed surface** by re-running the dry-run probe. If the new format name appears in the list, deploy succeeded.

### Deploy atomicity (rollback behavior)

Deploys via `--metadata-dir` are atomic — the entire metadata bundle either succeeds together or fails together. There's no partial-deploy state where some files land and others don't. Practical consequences:

- **If deploy fails** (e.g., invalid JSON in the new format's schema, schema validation error from the API, transient network issue): **nothing changes in the org.** The existing surface and existing formats are untouched. The skill reports the API error verbatim plus a plain-English explanation, and exits cleanly.
- **No rollback needed.** Since nothing was committed, there's nothing to roll back. The user fixes the issue (e.g., corrects the schema) and re-runs the skill.
- **The temp workspace can be removed safely** any time — it never holds state the org needs.

The skill prompt's error-handling rules cover the specific failure shapes (network timeout, malformed format JSON, agent activated mid-flow) and map them to plain-English messages with concrete fixes.

### Output

Two formats, same pattern as the other skills.

**1. Markdown (terminal):**

```
=== Connection Update Report: AcmePortal_ACME01 ===

▶ Top result: ✓ Added 'Time Picker' format. Connection now has 3 formats.

PRE-FLIGHT
  ✓ Salesforce CLI installed
  ✓ Org 'my-org' connected
  ✓ Agent is deactivated (safe to deploy)
  ✓ Bundle retrieved (v2)

CURRENT STATE (before update)
  Connection: AcmePortal_ACME01
  Existing formats: 2
    1. AcmePortalChoices_ACME01 (Text Choices)
    2. AcmePortalChoicesWithImages_ACME01 (Choices with Images)

CHANGE
  Add: AcmePortalTimePicker_ACME01 (Time Picker)

DEPLOY
  ✓ AcmePortalTimePicker_ACME01.aiResponseFormat — created
  ✓ AcmePortal_ACME01.aiSurface — updated (3 response formats)
  ✓ Deploy succeeded

NEW STATE (after update)
  Connection: AcmePortal_ACME01
  Total formats: 3
    1. AcmePortalChoices_ACME01 (Text Choices)
    2. AcmePortalChoicesWithImages_ACME01 (Choices with Images)
    3. AcmePortalTimePicker_ACME01 (Time Picker) — NEW

=== Summary: 1 format added, 0 modified, 0 removed ===

Next steps:
  1. Reactivate your agent (Setup → Agents → select your agent → Activate)
  2. Run /project:test-connection to verify the new format works at runtime
```

**2. JSON (saved to `/tmp/update-connection-report.json`):**

```json
{
  "$schema": "update-connection-v1",
  "agent": "Customer_Support_Agent",
  "bundleVersion": "v2",
  "connection": "AcmePortal_ACME01",
  "operation": "add",
  "timestamp": "2026-05-13T...",
  "before": {
    "formatCount": 2,
    "formats": ["AcmePortalChoices_ACME01", "AcmePortalChoicesWithImages_ACME01"]
  },
  "after": {
    "formatCount": 3,
    "formats": ["AcmePortalChoices_ACME01", "AcmePortalChoicesWithImages_ACME01", "AcmePortalTimePicker_ACME01"]
  },
  "added": ["AcmePortalTimePicker_ACME01"],
  "removed": [],
  "modified": [],
  "deployStatus": "passed"
}
```

The before/after structure is intentional — it makes the diff explicit and gives CI consumers a way to assert "exactly N formats were added, nothing was removed."

---

## Non-Technical UX Requirements

Same accessibility bar as `build-custom-connection`, `diagnose-connection`, and `test-connection`. The skill must be usable by Salesforce Admins who have never edited XML, written a curl command, or run a Salesforce CLI command before. Specifically:

**Language:**
- **Plain English everywhere.** No metadata jargon in user-facing messages. Don't say `plannerSurfaces`, `AiSurface`, `AiResponseFormat`, `responseFormats`, `surfaceConfig`, `GenAiPlannerBundle`, `metadata-dir`, `dry-run`, "merge XML", or "regenerate from scratch." Translate to: "your connection", "your response formats", "your agent's configuration", "what you currently have", "what we're about to add".
- **Setup → navigation paths**, not URLs or API endpoints. "Setup → Agents → select your agent → Deactivate" instead of "deactivate the BotVersion."
- **Action verbs in fix instructions.** "Click Deactivate" not "set the Status field to Inactive."
- **Friendly format names.** Always say "Text Choices" / "Image Cards" / "Time Picker" / "Custom JSON" — never the developer-name format like `AcmePortalChoices_ACME01` in the format-picking UI (the skill maps friendly names to developer names internally).

**Conversation flow:**
- **One question at a time.** 4 questions, never dumped together. Wait for each answer before asking the next.
- **Run commands without asking permission.** Don't say "shall I retrieve your bundle?" — just retrieve it and show the result.
- **Help the user find inputs they don't know.** Same as the trio: when asking for the agent name, offer Setup → Agents OR `sf data query` as ways to find it.
- **Show what's currently there before asking what to add.** The user picks "what to add" from a list that's already filtered by what they don't have. If the connection has Text Choices and Image Cards, the format-picker offers Time Picker and Custom JSON only (not the two they've already deployed). This is friendlier than asking the user to pick anything and then erroring on duplicates.

**Show before/after — the central UX commitment:**
- The user MUST see what's currently deployed before they confirm a change. No silent edits. The "CURRENT STATE" section appears in the report before "CHANGE" and "NEW STATE."
- Frame it as "your connection currently has X — this will make it have Y." Never frame it as "deploying metadata."
- If the user picks something that would clobber an existing format (Q3 deduplication), warn and ask for confirmation: "Your connection already has Text Choices. Adding another with the same type would create a duplicate. **Confirm you want to proceed**, or pick a different format type." This preserves the legitimate use case (user wants to replace a format with a new version of the same type) without forcing them through a "remove" operation that doesn't exist yet in v1.

**Error messages:**
- Every error has **What this means** (1-sentence plain-English explanation) and **How to fix** (concrete step with Setup → navigation path or exact command).
- Never show raw API errors or stack traces. Translate them. Example: instead of `"ConstraintViolationException: Bundle metadata is locked"`, show "Your agent is currently active, so changes can't be deployed. Go to Setup → Agents → select your agent → click Deactivate, then run this skill again."
- The deactivated-agent message references the workflow explicitly: "Note: this is the same state requirement as `build-custom-connection` and `diagnose-connection`. After deploying, run `/project:test-connection` to verify the new format works (that skill needs the agent active)."

**Transparency about what changed:**
- The report's CURRENT STATE / CHANGE / NEW STATE sections make every modification explicit and auditable.
- The "I might have missed formats" and "hand-edited surface fields will be lost" limitations are combined into a single detection-confidence checkpoint (Step 4a above). Before any deploy, the skill shows the formats it detected and asks "If this doesn't match what you expect, say stop." This covers both:
  - Formats Method A couldn't detect (non-conventional naming) — would be disconnected on deploy if we proceeded
  - Hand-edited surface fields (custom description, instructions) — would be lost when the surface XML is regenerated
  Both are unknown-unknowns from the skill's perspective. The user is the only one who can spot them. The confirmation gate makes that explicit.
- Brief status updates during long operations: "Looking at what you currently have...", "Generating your new format file...", "Updating your connection...", "Confirming the deploy worked..."

**Report:**
- **Top priority line.** First line of the report — "Added X to your connection." or the highest-priority issue if something failed.
- **Visual diff.** The CURRENT STATE / NEW STATE blocks make adds/changes obvious at a glance — no metadata field names, just numbered lists with friendly format names.
- **Next steps section.** After every successful update, tell the user what to do next: reactivate the agent, run test-connection. Don't leave them stranded with "deploy succeeded" and no guidance on the workflow.

**README and GUIDE updates:**
- The skill must be added to `README.md` and `GUIDE.md` with the same treatment as the trio:
  - **README:** A "Quick Start: Updating a connection" section between the build and diagnose sections (or after diagnose — wherever the iterate-on-existing flow logically belongs). Include the 4 questions the skill asks, a sample report showing the before/after diff, and what the skill does.
  - **GUIDE:** A new step (likely Step 12) "Updating an existing connection" that explains the merge approach in plain language, what the report's three-state structure (current/change/new) means, what the skill can't preserve (hand-edits), and when to run it (after build, before testing the new format).
- Both updates must use plain English — no metadata jargon — same standard as the existing chapters for build/diagnose/test.

---

## What It Does NOT Do (v1 scope)

- **Does not remove response formats.** v2 candidate. Adding doesn't risk breaking deployed sessions; removing does (an active session might be using the format you're about to delete).
- **Does not modify response format schemas.** v2 candidate. Schema changes are riskier than additions — they can break clients that already parse the old shape.
- **Does not change surface-level instructions.** v2 candidate. Pure text change, low risk, but adds a second verb to v1's scope.
- **Does not work on standard connections** (Telephony, Web Chat, Email, Messaging). Standard connections don't have user-defined response formats — there's nothing to add. v1 is custom-only.
- **Does not auto-rebuild the agent bundle.** The skill modifies the AiSurface and AiResponseFormat metadata. If the user has separately updated the GenAiPlannerBundle (e.g., to add a new topic), this skill doesn't touch that.
- **Does not preserve hand-edited fields on the AiSurface XML.** The CLI can't retrieve AiSurface XML by name, so the skill can only know the surface's *name* and its *list of response formats* — not its full XML body. If the user manually edited the surface's `<description>` or other fields outside what `build-custom-connection` generates, those edits are lost when the skill regenerates the surface. The report flags this explicitly so users with hand-edited surfaces aren't surprised. v2 may address if/when the CLI registry adds AiSurface support.
- **Does not deactivate the agent.** Same pattern as build/diagnose — the user deactivates manually before running. The skill stops with a clear message if it finds an active agent.
- **Does not test the new format at runtime.** That's `test-connection`'s job. This skill ends at "deploy succeeded" — verification belongs in the next step.

---

## Technical Approach

### Reuse from existing skills

| Component | Source | Notes |
|---|---|---|
| Bundle retrieve + multi-version fallback | `diagnose-connection` Step 3 | Identical logic; reuse the pattern |
| Method A: format name discovery (naming convention scan) | `diagnose-connection` Step 9 (Method A) | List `AiResponseFormat` metadata, filter by surface prefix/suffix |
| Method B: format existence verification (dry-run probe) | `diagnose-connection` Step 9 (Method B) | Use Method B to confirm Method A's candidates actually exist |
| `.aiResponseFormat` file templates | `build-custom-connection` | Same XML scaffolding for the 4 format types |
| AiSurface XML generation | `build-custom-connection` | Same template, but populated with the existing format list (from Method A+B) plus the new format appended |
| Deploy via `--metadata-dir` | `build-custom-connection` deploy.sh | Same CLI command |
| Agent active/inactive detection | `diagnose-connection` Step 4 | Same `BotVersion` query |

**The single new piece of logic** in this skill is the merge step itself: take the existing format list (output of Method A+B), append the new format, regenerate the AiSurface XML. Everything else is composition of patterns already proven in the trio.

The only genuinely new logic is the **merge step**: parsing existing `<responseFormats>` entries and appending the new one without duplicating.

### Where It Lives

```
custom-connections-skill/
├── .claude/commands/
│   ├── build-custom-connection.md     # existing
│   ├── diagnose-connection.md         # existing
│   ├── test-connection.md             # existing
│   └── update-connection.md           # new
```

Same repo. Trio becomes a quartet.

### Skill Prompt Structure

```
# Update Custom Connection
## Your role
## Step 1: Gather input (org, agent, connection, format to add)
## Step 2: Pre-flight checks (CLI, org, API version, agent deactivated)
## Step 3: Retrieve and parse current state (bundle + surface dry-run probe)
## Step 4: Show current state to the user (existing formats, deduplication warning)
## Step 5: Confirm the user wants to proceed with the planned change
## Step 6: Generate the new format file
## Step 7: Generate the merged AiSurface XML (existing formats + new one)
## Step 8: Deploy via --metadata-dir
## Step 9: Verify the new format is in the deployed surface (re-probe)
## Step 10: Compile and display results (markdown + JSON)
## Output templates
## Error handling rules
## Important rules
```

---

## Effort Estimate

| Task | Hours |
|------|-------|
| Skill prompt (`.claude/commands/update-connection.md`) | ~4 |
| Stateful merge logic (parse existing surface, generate merged XML) | ~2 |
| Deduplication check (warn user before adding a format that already exists) | ~1 |
| JSON output template + before/after diff structure | ~0.5 |
| Testing against test-org (add each format type, verify before/after, dedup detection, deactivation enforcement) | ~3 |
| Documentation (README + GUIDE updates) | ~1 |
| **Total** | **~11.5h** |

**Risk margin:** add 2h if the dry-run probe reveals edge cases when the surface has unusual existing formats (e.g., a format the user added manually with non-standard naming).

---

## Decisions Made

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Stateful merge architecture** | Building "pull current state + merge change + deploy" once means add/remove/modify all share the same architecture. Three sibling skills would each reimplement the pull-and-parse step. |
| 2 | **V1 supports add only** | Adding doesn't break deployed sessions. Removing and modifying do. Ship the safe verb first; layer risky verbs onto the same architecture in v2. |
| 3 | **Custom connections only** | Standard connections don't have user-defined response formats. Nothing to update there. Trying to extend would expand scope without adding value. |
| 4 | **Show before/after explicitly** | The user must see what exists before they confirm a change. Silent edits are how connections get clobbered. The before/after diff in both markdown and JSON makes the change auditable. |
| 5 | **Deduplication check before deploy** | If the user picks a format type that already exists on the connection (e.g., adding a second "Text Choices"), warn them. This is a near-certain user mistake — not something we silently allow. |
| 6 | **Reuse retrieve+parse from diagnose-connection** | Don't reinvent the bundle retrieve, the multi-version fallback, or the surface dry-run probe. Those are the exact same operations. |
| 7 | **Reuse format templates from build-custom-connection** | Same XML scaffolding for the 4 format types. The templates are the spec — re-using them keeps the family coherent. |
| 8 | **Deactivated agent required** | Same as build and diagnose. Active agents reject metadata updates. The state-flip table now has 3 deactivated skills (build/diagnose/update) and 1 active skill (test). |
| 9 | **Two output formats (markdown + JSON)** | Same pattern as the rest of the family. Markdown for terminal, JSON for CI/CD. Before/after diff in both. |
| 10 | **Same `/project:` namespace** | `/project:update-connection`. Migrates to `/agentforce:` with the family later. |
| 11 | **`$schema: "update-connection-v1"`** | Output schema versioned independently of the plan. Same convention as test-connection. |

---

## Open Questions

| # | Question | Why It Matters | Validation Plan |
|---|----------|---------------|----------------|
| 1 | **Does Method A (naming-convention scan) reliably find all formats for a surface?** | The skill's Step 4 depends on Method A's accuracy. If Method A misses a format that actually exists (e.g., a format with non-conventional naming), the merge logic generates a surface XML missing that format — clobbering it on deploy. Method B catches missing-from-org cases but not present-in-org-but-missed-by-Method-A cases. | Validate against test-org's BaxterCreditUnion_BCU01 (skill-built, naming convention holds) AND TestEscalation's MicrosoftTeams (non-conventional naming). Document the gap. If Method A is unreliable, we need a third detection approach before v1 ships. |
| 2 | **What does the deploy step return when the existing surface is "updated" with the same format list plus a new one?** | If the API treats "surface XML with 2 existing formats + 1 new format" as a no-op for the existing 2 and a "Created" for the new 1, we know the merge worked. If it treats the whole surface as "Changed" without distinguishing, we need a different verification approach. | Add a format to BCU_Test's BaxterCreditUnion_BCU01 connection in test-org via the skill. Inspect the deploy output. Document. |
| 3 | ~~**What's the right deduplication behavior — silent skip, warn, or hard error?**~~ | ~~Three options: (a) warn and confirm, (b) hard-error refuse, (c) silent no-op.~~ | **Resolved (post-v1 review):** warn and confirm (option a). A hard error blocks the legitimate use case of replacing a format with a new version of the same type — and the user has no "remove" verb yet to work around it. Warn+confirm preserves safety without dead-ending iteration. The format-picker also filters duplicates at the UX level (per Non-Technical UX section), so users only hit this prompt if they explicitly bypass the picker. |
| 4 | **Should the dedup check warn even on different format developer names?** | The user might add `AcmePortalChoices_ACME01_v2` (a renamed variant) when `AcmePortalChoices_ACME01` already exists. Different developer names but functionally a duplicate. | v1: only check exact developer name match. Treating "similar names" as duplicates introduces false positives. The user can rename if they hit a real conflict. |

**Validation priority:** Q1 and Q2 are load-bearing — must be resolved against test-org before any prompt scaffolding. Q3 resolved post-review (warn + confirm). Q4 is a UX choice that can be settled during build.

---

## Reviewer Sign-off Checklist

Before declaring v1 ready to build:

**Plan completeness:**
- [ ] Stateful merge architecture is clear (retrieve → parse → merge → deploy → verify)
- [ ] State-flip table is up-to-date across the full family
- [ ] V1 scope is "add only" — explicit no on remove, modify, swap, standard connections
- [ ] Open Question #1 (dry-run probe behavior) flagged for empirical validation before build

**Behavior:**
- [ ] Pre-flight enforces deactivated agent (matches build/diagnose state requirement)
- [ ] Skill shows existing formats to the user before deploying anything
- [ ] Deduplication check warns/blocks on format-name collision
- [ ] Before/after diff in both markdown and JSON output
- [ ] Multi-version fallback works (same as diagnose-connection)

**Non-technical UX (matches family bar):**
- [ ] Plain English in all user-facing text — no metadata jargon (`plannerSurfaces`, `AiSurface`, `AiResponseFormat`, `surfaceConfig`, `metadata-dir`, etc.)
- [ ] Friendly format names everywhere user-facing ("Text Choices" not `AcmePortalChoices_ACME01`)
- [ ] One question at a time, never dumps all 4 inputs upfront
- [ ] Format-picker filters out formats already on the connection (UX-level dedup, not just error-level)
- [ ] "What this means" + "How to fix" on every error, with Setup → navigation paths
- [ ] CURRENT STATE / CHANGE / NEW STATE sections in the report — before/after diff is explicit, not buried
- [ ] Hand-edited-surface limitation surfaced **before** deploy as a confirm-or-cancel note
- [ ] Top priority line at the start of the report
- [ ] Next steps section at the end (reactivate agent, run test-connection)
- [ ] Brief status updates during long operations ("Looking at what you currently have...", "Generating your new format file...")
- [ ] Deactivated-agent error message references both `build-custom-connection`/`diagnose-connection` (same state) and `test-connection` (inverse state) so users see the workflow
- [ ] README.md updated with "Quick Start: Updating a connection" section
- [ ] GUIDE.md updated with new step explaining update-connection in plain language

---

## Changelog

- **v1 (2026-05-13):** Initial draft. 4 inputs, stateful merge architecture, add-only scope for v1, custom-only, deactivated agent required. 4 open questions, 2 load-bearing.
  Reviewer correctly flagged that the bundle XML gives us the surface *name* but not its current `<responseFormats>` list — the AiSurface itself can't be retrieved by name through the CLI (registry limitation, same one diagnose-connection works around). Step 4 expanded to explain the Method A + Method B approach reused from `diagnose-connection`. New limitation surfaced: the skill regenerates the AiSurface XML from scratch each deploy, so any hand-edited fields on the existing surface XML are lost. Documented in "What It Does NOT Do" so users with hand-edited surfaces aren't surprised.

  **Non-Technical UX Requirements section expanded** to match the bar set by the trio. Specific additions:
  - **Format-picker filters out duplicates at the UX level** (don't let the user pick something that would error). Friendlier than the original "pick anything, error on duplicates" plan.
  - **Hand-edited-surface limitation surfaced before deploy** as a confirm-or-cancel note, not buried in "What It Does NOT Do." Users with hand-edited surfaces see the warning before they commit.
  - **Three-state report structure (CURRENT / CHANGE / NEW STATE)** — explicit before/after diff. No silent edits.
  - **Friendly format names everywhere user-facing.** "Text Choices" not developer-name strings like `AcmePortalChoices_ACME01`.
  - **Deactivated-agent error references the full workflow** — calls out the same-state pairing with build/diagnose AND the inverse-state with test-connection so users see the full picture.
  - **Next steps section** at the end of the report — tells the user to reactivate and run test-connection. Don't leave them stranded.
  - **README and GUIDE updates required** in the sign-off checklist, not optional.

  Sign-off checklist expanded from 8 to 13 non-technical UX items.

- **v1.1 (2026-05-13 — post-review polish, 4 items addressed):** First reviewer pass on v1 surfaced 4 refinements:
  - **Method A safety rail (Step 4a added):** the skill now shows the formats it detected and asks the user to confirm before any deploy. Special case for "Method A finds zero formats but bundle wires the surface" — hard stop with explanation, no deploy. Turns the unknown-unknowns problem into a UX gate rather than silent clobbering.
  - **Hand-edits + missed-formats merged into one confidence checkpoint:** rather than two separate warnings, both unknown-unknowns are caught by Step 4a's "If this doesn't match what you expect, say stop" prompt. The user is the only one who can spot either issue — make that explicit.
  - **Q3 deduplication resolved as warn + confirm** (not hard error). Hard error blocks the legitimate "replace a format with a new version" use case, especially when no "remove" verb exists yet. The format-picker still filters duplicates at the UX level, so users only hit the warn+confirm prompt if they bypass that.
  - **Deploy atomicity / rollback section added:** `--metadata-dir` deploys are atomic. If the deploy fails, nothing changes in the org. No rollback needed. Documented so users (and reviewers) know there's no half-deployed state to worry about.
