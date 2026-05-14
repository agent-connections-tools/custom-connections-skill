# Testing Guide: update-connection skill

## What this skill does

The `update-connection` skill adds a new response format to a custom connection that already exists in your org — without rebuilding the connection from scratch and without losing the formats that are already there.

It's the fourth verb in the family:

```
build-custom-connection      diagnose-connection       update-connection         test-connection
       (create)          →     (verify config)     →    (modify in place)    →    (verify runtime)
```

**State requirement is the same as build and diagnose** — the agent must be **deactivated** before running. After this skill deploys the change, you reactivate the agent and run `test-connection` to verify the new format works at runtime.

The skill is **read-mostly with one destructive operation** (deploying the merged surface). It has two confirmation gates before that deploy:
- **Step 4a** — confirms the formats currently detected on the connection (guards against silent data loss)
- **Step 7a** — confirms the planned change (guards against typos and changed minds)

## How to run it

From the `custom-connections-skill` project directory:

```
/project:update-connection
```

The skill asks four questions (one at a time):
1. Your org alias (use `test-org`)
2. Your agent's developer name
3. Which custom connection to update (skill lists what's on the agent)
4. Which format to add (skill filters out formats already on the connection)

Then it pulls the current state, shows you what's there, asks you to confirm both the detected list and the planned change, and deploys.

**Reviewing intermediate steps:** This is a Claude Code skill (prompt instructions to Claude), not a standalone script. When reviewing, watch three things:
1. **The conversation flow** — does Claude ask one question at a time? Does the format-picker exclude duplicates?
2. **The two confirmation gates** — Step 4a's "SILENTLY REMOVED" warning and Step 7a's explicit "proceed"
3. **The merged AiSurface XML** — every existing format is preserved, plus the new one

## Test org details

**Org alias:** `test-org`

**Test agents:**

- **`BCU_Test`** (multi-version, **v2 is Active or Inactive depending on prior tests**)
  - Custom connection: `BaxterCreditUnion_BCU01`
  - Formats currently on it: depends on prior test runs. After the live test of update-connection on 2026-05-14, it has 3 formats: `BaxterCreditUnionChoices_BCU01`, `BaxterCreditUnionChoicesWithImages_BCU01`, `BaxterCreditUnionTimePicker_BCU01`. Reviewers may need to remove the Time Picker manually before re-running Scenario 1, or pick a different format type to add.
  - Bundle uses versioned names (`BCU_Test_v1`, `BCU_Test_v2`) — multi-version fallback fires.

- **`Agentforce_Service_Agent`** (display name "TestSimple", v1 is Active)
  - Custom connection: `BaxterCreditUnion_BCU01` (same surface as BCU_Test points at)
  - Use this agent if you want to test on a single-version agent (no multi-version fallback)

- **`TestEscalation`** (v1 Inactive)
  - Custom connection: `MicrosoftTeams` — non-conventional naming, no `_<SurfaceId>` suffix
  - Use this for the **zero-detected-formats hard-stop** scenario (Scenario 5 below)

**Test ECA:** Not needed for this skill. `update-connection` uses only `sf` CLI commands — no OAuth, no Agent API. (Compare to `test-connection`, which needs ECA credentials.)

## Pre-test setup

**Before each scenario:** the target agent must be **deactivated**. Run:

```bash
sf agent deactivate --api-name <AgentName> --target-org test-org
```

After the test, optionally reactivate:

```bash
sf agent activate --api-name <AgentName> --version <N> --target-org test-org
```

## Check inventory

### BCU_Test — happy path (add Time Picker to a connection that doesn't have it)

Expected: **1 format added, 0 modified, 0 removed**

| # | Check | Expected | Notes |
|---|-------|----------|-------|
| 1 | CLI installed | passed | `sf --version` succeeds |
| 2 | Org connected | passed | `test-org` resolves |
| 3 | API version ≥ 62.0 | passed | Org is v67.0 |
| 4 | Bundle retrieved | passed | Multi-version fallback: bare name fails, retrieves `BCU_Test_v2` |
| 5 | Agent deactivated | passed | If active, skill stops with state-flip message |
| 6 | Custom connection found on agent | passed | `BaxterCreditUnion_BCU01` listed |
| 7 | Method A finds existing formats | passed | Returns 2 formats (Choices, ChoicesWithImages) |
| 8 | Method B confirms detected formats exist | passed | Both formats verified via dry-run probe |
| 9 | Step 4a confirmation dialog shown with "SILENTLY REMOVED" warning | passed | User confirms |
| 10 | Format-picker filters out duplicates | passed | Picker shows Time Picker + Custom JSON only (Text Choices and Choices with Images excluded) |
| 11 | Merged AiSurface XML includes all 3 formats | passed | Critical: existing 2 + new 1, never drop |
| 12 | Step 7a "proceed" gate fires | passed | User confirms |
| 13 | Deploy succeeded | passed | `--metadata-dir` deploy reports success |
| 14 | Step 9 verification: full-list match | passed | Method A+B re-run, finds 3 formats |
| 15 | Final report includes CURRENT/CHANGE/NEW state diff | passed | Three-section structure |

**Counting rule:** the JSON `passed`/`warnings`/`failed` counts represent top-level outcomes, not every individual check. The terminal summary should match the JSON. The check inventory above lists all 15 internal checks for reviewers; the report condenses them into ~3 top-level passed entries.

### TestEscalation — zero-detected-formats hard stop

Expected: **skill exits at Step 4a special case. No deploy.**

| # | Check | Expected | Notes |
|---|-------|----------|-------|
| 1-6 | Pre-flight + bundle retrieve + connection picker | passed | Same as happy path |
| 7 | Method A finds existing formats | **zero detected** | Surface name `MicrosoftTeams` has no `_<SurfaceId>` suffix; org has `TeamsText` (no matching prefix or suffix) |
| 8 | Step 4a special-case fires | passed | Hard stop with the "I couldn't detect any existing response formats" message |
| 9 | Skill exits cleanly | passed | No deploy attempted, no temp files left in problematic state |

This validates the safety rail. The user's connection is untouched — the skill refused to proceed because it couldn't safely enumerate the existing formats.

## Test scenarios

### Scenario 1: Happy path — add Time Picker to BaxterCreditUnion_BCU01

**Setup:** Deactivate `BCU_Test`. If `BaxterCreditUnion_BCU01` already has Time Picker (from a prior test run), either remove it manually first or pick a different format type to add.

**Run:** `/project:update-connection` against `test-org`, agent `BCU_Test`, connection `BaxterCreditUnion_BCU01`, format `Time Picker` (or any not-currently-present type).

**Expected result:**
- All 4 questions asked one at a time
- Multi-version fallback fires (bare-name retrieve fails, `BCU_Test_v2` succeeds)
- Method A finds the 2 existing formats (Choices, ChoicesWithImages)
- Method B's dry-run probe confirms both exist
- Step 4a shows the detected list with the explicit "SILENTLY REMOVED" warning text
- After "proceed", the format-picker shows only types NOT already on the connection
- Step 7a shows the planned change ("Currently has 2 formats / After this change: 3 formats / adding Time Picker")
- Deploy succeeds
- Step 9 verification confirms 3 formats on the deployed surface
- Final report shows CURRENT STATE (2) → CHANGE (add Time Picker) → NEW STATE (3) with the new entry tagged "— NEW"
- JSON saved to `/tmp/update-connection-report.json` with `before.formatCount: 2`, `after.formatCount: 3`, `added: ["...TimePicker_BCU01"]`

**Critical things to verify (watch tool calls):**
- Bundle retrieve uses `BCU_Test_v2`, not `BCU_Test`
- The merged AiSurface XML deployed in Step 8 contains **all three** `<responseFormats>` blocks, not just the new one
- Deploy result shows existing formats as `Unchanged`, new format as `Created`, surface as `Changed`

**Review for:**
- Plain English everywhere (no `plannerSurfaces`, `surfaceConfig`, `AiSurface`, `AiResponseFormat` in user-facing output)
- Friendly format names in the picker ("Text Choices", not `BaxterCreditUnionChoices_BCU01`)
- Setup → navigation paths in any error messages
- Next Steps section at the end (reactivate, run test-connection)

---

### Scenario 2: Active agent — state-flip enforcement

**Setup:** Activate `BCU_Test` v2 (`sf agent activate --api-name BCU_Test --version 2 --target-org test-org`).

**Run:** `/project:update-connection` against `test-org`, agent `BCU_Test`.

**Expected result:**
- Pre-flight passes
- Bundle retrieves (multi-version fallback)
- BotVersion query reports v2 Active
- Skill stops at Step 3 with the state-requirement message:
  > Your agent is currently active. Deploys are rejected when an agent is live. **How to fix:** Go to Setup → Agents → select your agent → click Deactivate. Then re-run this skill. Note: this is the same state requirement as `build-custom-connection` and `diagnose-connection`. After deploying changes, you'll reactivate and run `test-connection` to verify the new format works.
- No deploy attempted

**Review for:**
- Error message references both same-state skills (build, diagnose) AND the inverse-state skill (test) so users see the workflow
- Concrete Setup → navigation path in the fix instruction

---

### Scenario 3: Wrong agent name

**Setup:** Any agent state.

**Run:** Give agent name `Nonexistent_Agent`.

**Expected result:**
- Pre-flight (CLI, org) passes
- Bundle retrieve returns "Succeeded" with a "cannot be found" warning (CLI returns exit 0 even when not found)
- Skill detects the missing bundle file
- Falls back to the BotDefinition query, lists available agents, asks the user to pick
- Does NOT crash, no stack trace

**Review for:**
- Same silent-failure detection pattern as diagnose-connection and test-connection
- Plain-English explanation of why the lookup failed

---

### Scenario 4: Wrong org alias

**Setup:** N/A.

**Run:** Give org alias `fake-org`.

**Expected result:**
- Pre-flight check #2 (org connected) fails
- Skill stops immediately: "I can't connect to your org 'fake-org'. Run `sf org login web --alias fake-org` to log in."
- No bundle retrieve attempted

**Review for:**
- Clean stop, no partial results
- Concrete fix command

---

### Scenario 5: Zero-detected-formats hard stop (TestEscalation MicrosoftTeams)

**Setup:** Deactivate `TestEscalation` if it's currently active (it's typically Inactive).

**Run:** `/project:update-connection` against `test-org`, agent `TestEscalation`, connection `MicrosoftTeams`.

**Expected result:**
- Pre-flight passes
- Bundle retrieves
- Custom connection picker lists `MicrosoftTeams`
- Method A: surface name has no `_<SurfaceId>` suffix; the only format in the org (`TeamsText`) doesn't match `MicrosoftTeams<Type>_<SurfaceId>`. Returns zero matches.
- Step 4a's special case fires:
  > I couldn't detect any existing response formats on your connection, but your agent's configuration says this connection is wired up. This means your formats use non-standard naming I don't recognize. Continuing would regenerate your connection's configuration without those formats — disconnecting them from your connection. I'm stopping here to avoid that.
- Skill exits cleanly. No deploy. No confirmation prompt — this is a hard stop, not a warn.

**This is the load-bearing safety rail.** If this scenario doesn't fire correctly, the skill could silently destroy data on connections it can't fully enumerate.

**Review for:**
- Hard stop fires before any confirmation prompt
- The error message explains why (non-standard naming) and what to do (rename or wait for v2)
- No deploy attempted

---

### Scenario 6: User says "stop" at Step 4a confirmation

**Setup:** Deactivate `BCU_Test`.

**Run:** Same as Scenario 1, but at the Step 4a "If this doesn't match what you expect, say stop" prompt, the user says "stop".

**Expected result:**
- Skill exits cleanly without deploying
- No format file generated
- No surface XML written
- No `--metadata-dir` deploy attempted
- Final message confirms nothing was changed

**Review for:**
- Exit is clean, not an error
- Confirms "nothing was changed in your org"

---

### Scenario 7: User says "stop" at Step 7a confirmation

**Setup:** Deactivate `BCU_Test`.

**Run:** Same as Scenario 1, but at the Step 7a "Reply 'proceed' to deploy, or 'stop' to cancel" prompt, the user says "stop".

**Expected result:**
- Skill has already generated the new format file and merged surface XML in `$WORK_DIR/output/`
- But no deploy is attempted — `sf project deploy start --metadata-dir` is never called
- Skill exits cleanly
- Temp directory can be removed; nothing was committed to the org

**Review for:**
- Both gates work independently — Step 4a-stop and Step 7a-stop are separate exit paths
- File generation happens before Step 7a but is harmless (org-side state unchanged)

---

### Scenario 8: Custom JSON format

**Setup:** Deactivate `BCU_Test`. Pick a connection that doesn't already have Custom JSON.

**Run:** Same as Scenario 1, but pick "Custom JSON" as the format type. Provide a custom schema when asked (e.g., a Slack Block Kit time picker schema, or any valid JSON Schema).

**Expected result:**
- Skill validates the JSON Schema before generating the file
- Invalid JSON → asks for a corrected schema, does not proceed
- Valid JSON → file generated, merged XML produced, deploy succeeds
- The new format developer name follows the same pattern: `<ClientName>CustomJson_<SurfaceId>` (or skill picks a sensible default if "Custom JSON" doesn't fit the simple type-name pattern)

**Review for:**
- JSON Schema validation happens before file generation, not after
- Error message on invalid schema is plain English with concrete guidance ("the JSON inside your input field has a syntax error: missing comma on line 3")

---

### Scenario 9: All 4 format types already present

**Setup:** Deactivate an agent whose custom connection has all 4 format types (Text Choices, Choices with Images, Time Picker, Custom JSON). May require manual setup since the test-org's BaxterCreditUnion_BCU01 has only 3 currently.

**Run:** `/project:update-connection` against that agent.

**Expected result:**
- After detecting the 4 existing formats and confirming with the user via Step 4a, the format-picker has nothing to show
- Skill exits cleanly: "This connection already has all 4 supported format types. Use a future skill to remove or replace formats (not yet available)."
- No deploy

**Review for:**
- Skill recognizes the empty-picker state instead of crashing
- Suggested-future-skill messaging is honest about scope

---

### Scenario 10: Standard connection (not eligible)

**Setup:** Deactivate any agent with both standard and custom connections (e.g., `Agentforce_Service_Agent`).

**Run:** `/project:update-connection` against that agent. Try to pick a standard connection (Telephony, Web Chat, Email, Messaging).

**Expected result:**
- Step 3's connection picker only lists **custom** connections
- Standard connections are filtered out, not listed
- If the agent has zero custom connections, skill exits: "This agent has no custom connections. Use `/project:build-custom-connection` to create one."

**Review for:**
- Standard connections never appear in the picker
- Honest exit message when no custom connections exist

---

## Things to specifically review

### 1. Language and tone
- Plain English in every user-facing message?
- No metadata jargon (`plannerSurfaces`, `surfaceConfig`, `AiSurface`, `AiResponseFormat`, `GenAiPlannerBundle`, `metadata-dir`, `dry-run`, "merge XML")?
- Friendly format names in the picker ("Text Choices" not `BaxterCreditUnionChoices_BCU01`)?
- Setup → navigation paths in fix instructions?

### 2. Conversation flow
- One question at a time, never dumps all 4 inputs upfront?
- Format-picker filters out formats already on the connection (UX-level dedup)?
- Brief status updates during long operations ("Looking at what you currently have...", "Generating your new format file...", "Updating your connection...")?

### 3. The two confirmation gates
- Step 4a fires before any deploy, with the "SILENTLY REMOVED" warning text verbatim?
- Step 4a's zero-detected special case is a hard stop (no confirmation prompt)?
- Step 7a fires after Step 4a passes, with the planned change summary?
- Both gates accept "stop" cleanly without deploying?

### 4. The merge logic (the load-bearing engineering)
- Method A correctly extracts prefix and suffix from the surface name?
- Method A returns expected formats for conventional naming (BCU01)?
- Method A returns zero for non-conventional naming (MicrosoftTeams)?
- Method B (dry-run probe) is run after Method A to verify candidates exist?
- The merged AiSurface XML in Step 8 contains **all** detected formats plus the new one?
- No format is silently dropped from the existing list?

### 5. Step 9 verification
- Method A+B re-run after deploy?
- Compares full count + names against expected (existing + new)?
- Three outcomes covered: clean / count-low / new-not-detected?
- Hard warning fires on count-low (silent-clobbering caught)?
- Soft warning fires on new-not-detected (caching delay)?

### 6. State-flip enforcement
- Skill stops if agent is active, with the message referencing both same-state skills (build, diagnose) and the inverse-state skill (test)?
- Concrete Setup → navigation path in the fix instruction?

### 7. Cleanup
- Temp directory removed at the end?
- If cleanup is blocked (sandbox), skill doesn't escalate — workspace is harmless?

### 8. Report quality
- Top priority line at the start?
- CURRENT STATE / CHANGE / NEW STATE three-section structure?
- New entry tagged "— NEW" in the NEW STATE section?
- Next Steps section at the end (reactivate, run test-connection)?
- Terminal summary count matches JSON top-level counts?

### 9. JSON report
- Saved to `/tmp/update-connection-report.json`?
- Schema is `update-connection-v1`?
- `before` / `after` / `added` / `removed` / `modified` arrays present?
- Counts match the markdown report?

### 10. Safety
- NEVER deploys without going through both Step 4a and Step 7a confirmations?
- NEVER omits a detected format from the merged surface XML?
- Format name matching uses exact equality, not `startsWith` or `contains`?
- Standard connections excluded from the picker (custom-only in v1)?
- No `forceConfigEndpoint`, `streamingConfig`, or other invalid fields in any deploy artifact?

## Known limitations and untestable scenarios

- **Mixed case (manual non-conventional format on skill-built connection)** — Q1 Test (c) from the plan. Acknowledged untestable without modifying shared org state. The Step 4a confirmation dialog mitigates by shifting the failure mode from silent loss to user-confirmation. Acceptable for v1.
- **Partial deploy success** — `--metadata-dir` deploys are atomic in practice. Triggering a partial-success state for testing requires deliberately crafting a failure mid-bundle, which is hard to reproduce reliably. The skill's error handling for this case (report orphaned state, suggest diagnose-connection) is verifiable by inspection of the skill prompt.
- **Counter-mismatch in test-connection JSON** (observed during this skill's runtime test): test-connection's terminal showed "15 passed" while JSON showed `passed: 7`. Same issue we caught in diagnose-connection earlier. Not blocking for update-connection — this is a test-connection bug to fix separately.

## Quick spot-check (5 minutes)

If you only have 5 minutes, run **Scenario 1** end-to-end against BCU_Test. It exercises:
- Multi-version fallback
- Method A naming-convention scan
- Method B dry-run probe verification
- Step 4a confirmation with the "SILENTLY REMOVED" warning
- Format-picker UX-level dedup
- Step 7a "proceed" gate
- Merged AiSurface XML deploy (all formats preserved + new one added)
- Step 9 full-list verification
- CURRENT/CHANGE/NEW report structure
- JSON output with before/after diff

If Scenario 1 passes, the skill is fundamentally working. The other scenarios catch edge cases.
