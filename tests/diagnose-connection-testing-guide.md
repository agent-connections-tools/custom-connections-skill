# Testing Guide: diagnose-connection skill

## What this skill does

The `diagnose-connection` skill checks that an Agentforce agent's connections (standard and custom) are configured correctly. It's read-only — it never changes anything in the org. It produces a health report showing what's working and what's broken, with plain-English fix instructions.

## How to run it

From the `custom-connections-skill` project directory:

```
/project:diagnose-connection
```

The skill asks three questions (one at a time):
1. Your org alias (use `test-org`)
2. Your agent's developer name (use `Agentforce_Service_Agent`)
3. Which connection to check — it lists what it found and lets you pick one or say "all"

Then it runs checks and shows a report.

**Reviewing intermediate steps:** This is a Claude Code skill (prompt instructions to Claude), not a standalone script. When reviewing, you're watching two things:
1. **The final report** — the markdown output and JSON file
2. **Claude's tool calls** — the sf CLI commands Claude runs in the terminal. These show the raw deploy output (e.g., "Changed" vs "Created" status on dry-runs). If a scenario asks you to verify something about the intermediate steps (like the surface name used in a dry-run), look at Claude's Bash tool calls, not just the final report.

## Test org details

- **Org alias:** `test-org`
- **Primary test agent:** `Agentforce_Service_Agent` (display name: "TestSimple")
  - Connections: Telephony (standard), CustomerWebClient (standard), ServiceEmail (standard), BaxterCreditUnion_BCU01 (custom)
  - Response formats: BaxterCreditUnionChoices_BCU01, BaxterCreditUnionChoicesWithImages_BCU01
  - Status: v1 is Active
- **Standard-only agent:** `Agentforce_Employee_Agent` (display name: "Agentforce Employee Agent")
  - Connections: SurfaceAction__Messaging (standard, surfaceType: Messaging) — no custom connection
  - Status: v1 is Inactive
- **Custom connection with non-standard naming:** `TestEscalation`
  - Connections: Messaging, CustomerWebClient, Telephony, ServiceEmail, MicrosoftTeams (custom), Test (standard)
  - Response formats: only `TeamsText` exists (doesn't follow `build-custom-connection` naming pattern)
  - Status: v1 is Inactive
- **Agents without bundles (retrieve will fail):** `Copilot_for_Salesforce`, `TestAgent3`, `Soap_Demo`, `testTelephony`, `testAgent`, `BCU_Test`, `VoiceAgentTest`
- **All agents have a single version (v1).** No multi-version agents exist in this org.

## Check inventory

### Agentforce_Service_Agent — "all" connections

Expected: **12 passed, 1 warning, 0 issues** (+ 1 skipped)

| # | Check | Expected | Notes |
|---|-------|----------|-------|
| 1 | Agent retrieved | passed | |
| 2 | Activation status | **warning** | v1 is Active |
| 3 | Version | passed | Single version v1 |
| 4 | API version consistency | passed | v66.0 |
| 5 | Telephony | passed | Standard, Salesforce-provided |
| 6 | Web Chat | passed | Standard, Salesforce-provided |
| 7 | Email | passed | Standard, Salesforce-provided |
| 8 | Custom connection exists | passed | BaxterCreditUnion_BCU01 in org |
| 9 | Adaptive responses | passed | Enabled |
| 10 | Only one custom connection | passed | |
| 11 | No duplicate connections | passed | |
| 12 | Response formats found | passed | 2 found by naming convention |
| 13 | Response formats validated | passed | Dry-run succeeded |
| — | JSON schema check | **skipped** | No local .aiResponseFormat files (info note, not a pass) |

### Agentforce_Employee_Agent — "all" connections

Expected: **5 passed, 0 warnings, 0 issues**

| # | Check | Expected | Notes |
|---|-------|----------|-------|
| 1 | Agent retrieved | passed | |
| 2 | Activation status | passed | v1 is Inactive |
| 3 | Version | passed | Single version v1 |
| 4 | API version consistency | passed | |
| 5 | Messaging | passed | Standard, Salesforce-provided |

No custom connection checks run. No format validation. No JSON schema check.

**About topic/plugin references:** The bundle contains `localTopicLinks` and `localTopics` entries (e.g., ProductRecommendations_BCU01, TEst_16jSB000000U9KP). These are NOT checked by this skill — topic and plugin reference validation was removed because it's not connection-related. If a reviewer asks why these aren't in the report, that's by design.

**About the JSON schema check:** When no local `.aiResponseFormat` files exist in the current directory, this check is **skipped** with an info note. It does NOT count as a "passed" check. The pass total should be 12 (not 13). The info note should appear outside the pass/warning/issue counts.

Note: Pre-flight environment checks (CLI installed, org connected, API version ≥ 62.0) run before these and stop execution if they fail. They may or may not appear as separate lines in the report. What matters: if they pass, the main checks run.

## Test scenarios

### Scenario 1: Happy path — all connections

**Run:** `/project:diagnose-connection` with org `test-org`, agent `Agentforce_Service_Agent`, choose "all"

**Expected result:**
- Environment checks pass (CLI installed, org connected, API version ≥ 62.0)
- Skill lists 4 connections and asks which to check
- Agent-level: retrieved, version v1, API version consistent
- 3 standard connections pass with "provided by Salesforce"
- Custom connection passes all checks (exists, adaptive responses on, 2 formats found and validated)
- Active agent warning
- JSON report saved to `/tmp/diagnose-report.json`
- Total: 12 passed, 1 warning, 0 issues, 1 skipped (see check inventory)

**Review for:**
- Are all messages in plain English? No metadata jargon?
- Does the report use Setup → navigation paths for fix instructions?
- Is the JSON report well-formed and matches the markdown report?
- Does the check count in the summary line match the inventory?
- Is the JSON schema check reported as skipped/info (not passed)?

---

### Scenario 2: Diagnose a single connection

**Run:** `/project:diagnose-connection` with org `test-org`, agent `Agentforce_Service_Agent`, then pick **only the custom connection** (BaxterCreditUnion_BCU01)

**Expected result:**
- Environment and agent-level checks still run (retrieved, version, activation, API version)
- Standard connections (Telephony, Web Chat, Email) are **skipped** — not in the report
- Only the custom connection checks appear: exists, adaptive responses, one custom limit, no duplicates, formats found, formats validated
- Fewer total checks than Scenario 1

**Review for:**
- Does the skill actually skip the unselected connections? (Not just hide them)
- Is the report shorter than the "all" report?
- Does the summary count reflect only the checks that ran?

---

### Scenario 3: Wrong agent name

**Run:** Give agent name `Nonexistent_Agent`

**Important behavior to know:** The retrieve command returns `Status: Succeeded` even when the agent isn't found — it doesn't fail with a non-zero exit code. Instead, it shows a Warnings table containing `"Entity of type 'GenAiPlannerBundle' named 'Nonexistent_Agent' cannot be found"`. The skill needs to check for this warning (or check that no `.genAiPlannerBundle` file was produced), not rely on the exit code.

**Expected result:**
- Retrieve returns "Succeeded" with a warning — skill detects the agent wasn't actually found
- Skill shows available agents by querying BotDefinition
- Asks the user to pick the correct one
- Does NOT crash or show a raw stack trace

**Review for:**
- Does the skill detect the "not found" case despite the "Succeeded" status? (Watch the tool calls)
- Is the error message helpful? Does it explain what went wrong?
- Does it show the list of available agents?

---

### Scenario 4: Wrong org alias

**Run:** Give org alias `fake-org`

**Expected result:**
- Environment check fails at "Org connected"
- Skill stops immediately and tells the user how to log in (`sf org login web --alias fake-org`)
- Does NOT continue to the main checks

**Review for:**
- Does it stop cleanly? No partial results or confusing output?
- Is the fix instruction clear?

---

### Scenario 5: Agent with no custom connection

**Run:** `/project:diagnose-connection` with org `test-org`, agent `Agentforce_Employee_Agent`, choose "all"

**Expected result:**
- Agent retrieved successfully
- Only one standard connection listed: SurfaceAction__Messaging (surfaceType: Messaging)
- No custom connection checks run — no format validation, no adaptive response check, no duplicate check
- Report makes sense without custom-specific sections
- No errors about missing formats
- Total: 5 passed, 0 warnings, 0 issues (see check inventory)

**Review for:**
- Does the skill handle the "no custom connection" case gracefully?
- Does the report still make sense without custom connection checks?
- Is the Messaging connection listed correctly as a standard Salesforce-provided connection?

---

### Scenario 6: Response format validation — happy path (dry-run)

**What to check:** The skill uses two methods to validate response formats:
1. **Naming convention match** — looks for formats matching `<ClientName><Type>_<SurfaceId>`
2. **Dry-run deploy** — re-deploys the real surface (using the actual surface name from the bundle) in dry-run mode to confirm formats exist

**Expected result for test-org (Agentforce_Service_Agent):**
- Method A finds 2 formats: BaxterCreditUnionChoices_BCU01, BaxterCreditUnionChoicesWithImages_BCU01
- Method B uses the real surface name `BaxterCreditUnion_BCU01` (not a generated stub or prefixed name)
- Dry-run succeeds, confirming both formats are valid and deployed

**Review for (watch Claude's tool calls, not just the final report):**
- Does the Bash command show `BaxterCreditUnion_BCU01.aiSurface` as the filename? (Not `DiagnoseCheck_` or any other prefix)
- Does the sf CLI output show the surface as "Changed" (not "Created")? This confirms it's treating it as an update to the existing surface.
- Are both formats listed in the `<responseFormats>` blocks of the dry-run surface XML?

---

### Scenario 7: Response format validation — naming mismatch (no matching formats)

**Run:** `/project:diagnose-connection` with org `test-org`, agent `TestEscalation`, choose the custom connection `MicrosoftTeams`

**Context:** `TestEscalation` has a custom connection named `MicrosoftTeams` (no suffix ID). The only response format in the org for it is `TeamsText`, which doesn't follow the `build-custom-connection` naming pattern (`<ClientName><Type>_<SurfaceId>`). So Method A (naming convention match) should find 0 matching formats.

**Expected result:**
- Method A finds 0 formats matching the naming convention
- Warning: "I couldn't find any response formats for this connection."
- Method B (dry-run) may or may not run depending on whether the skill requires Method A to find formats first
- The skill does NOT crash — it handles the "no formats found" case gracefully

**Review for:**
- Does the naming convention search fail gracefully when the surface name has no suffix ID?
- Is the warning message clear about why no formats were found?
- Does the skill suggest what to do? (e.g., "If you built it with the `build-custom-connection` skill, they should be there. You may need to redeploy them.")

---

### Scenario 8: Batch dry-run fallback (missing format)

**Context:** This tests the most complex logic branch in the skill (plan Decision #12): batch all formats in one dry-run → if batch fails, fall back to individual dry-runs to pinpoint which format is missing.

**Setup required before running:** This scenario requires a surface that references a format that doesn't exist in the org. Since we can't modify org metadata with this skill, you have two options:

**Option A (recommended):** During the dry-run step, manually check how the skill handles a failure by watching the tool calls. After Scenario 6 passes, note that both formats exist. Then ask: "What would happen if one of these formats was deleted?"

**Option B (requires org setup):** Deploy a test surface that references a nonexistent format:
1. Create an AiSurface XML that references `BaxterCreditUnionChoices_BCU01` (exists) AND `DOES_NOT_EXIST_FORMAT` (doesn't exist)
2. Deploy it to the org
3. Run the skill against the agent with that surface
4. The batch dry-run should fail, the skill should fall back to individual dry-runs, and report exactly which format is missing

**Expected behavior if a format is missing:**
- Batch dry-run fails with: `"Response format does not exist in org: DOES_NOT_EXIST_FORMAT"`
- Skill falls back to individual dry-runs per format
- Reports: "Response format 'DOES_NOT_EXIST_FORMAT' is missing from your org. Redeploy it with `sf project deploy start --metadata-dir`."
- Other formats that DO exist are reported as passed individually

**Review for:**
- Does the skill parse the batch error correctly to identify the missing format name?
- Does it actually fall back to individual dry-runs (watch the tool calls — you should see multiple `sf project deploy start` commands)?
- Does it distinguish between format-specific errors and surface-level errors?

---

### Scenario 9: Local JSON schema check

**Context:** The plan says "JSON.parse the `<input>` field to catch malformed schemas." Since AiResponseFormat XML can't be retrieved from the org (CLI blocks it), the skill checks local `.aiResponseFormat` files in the current working directory. This covers cases where the user has the source files from a previous `build-custom-connection` run.

**How to test — with local files:** Run the skill from a directory that contains `.aiResponseFormat` files:
```
cd examples/acme-portal && /project:diagnose-connection
```

**Expected result:**
- Skill finds 3 local files: AcmePortalChoices_AcmePortal01, AcmePortalChoicesWithImages_AcmePortal01, AcmePortalTimePicker_AcmePortal01
- Validates the JSON in each file's `<input>` field
- Reports pass/fail per file

**How to test — without local files:** Run from the project root:
```
/project:diagnose-connection
```

**Expected result:**
- Info note (not a "passed" check): "I couldn't check your response format JSON schemas because there are no local .aiResponseFormat files in this directory."
- This should NOT appear in the passed count

---

## Things to specifically review

### 1. Language and tone
- Is every message understandable by someone who's never touched Salesforce CLI or metadata?
- Are fix instructions actionable? (Setup → navigation paths, exact commands to run)
- Does it avoid terms like "plannerSurfaces", "AiSurface", "surfaceType", "GenAiPlannerBundle"?

### 2. Conversation flow
- Does it ask questions one at a time (not all at once)?
- Does it ask Question 3 (which connection to check) after listing what it found?
- Does it run commands immediately without asking "shall I run this?"

### 3. Report quality
- Is the top priority line accurate (most important fix first)?
- Are connections grouped clearly (standard vs. custom)?
- Do warnings and issues include "What this means" and "How to fix" sections?
- Does the summary line at the bottom match the actual check count? (See check inventories)
- Is the JSON schema check reported as "skipped" (not "passed") when no local files exist?

### 4. Error handling
- When something fails, does it explain WHY and WHAT TO DO?
- Does it stop on environment failures instead of continuing with broken state?
- Does it handle unexpected errors gracefully (no raw stack traces)?
- What happens if the dry-run deploy is slow or times out? Does it report a warning and continue?

### 5. Safety
- Does it NEVER modify the org? (read-only, dry-run only)
- Does the dry-run use the **real surface name** from the bundle? (Per plan Decision #13 — no generated stubs)
- Does it clean up temp directories at the end?

### 6. JSON report
- Is `/tmp/diagnose-report.json` created?
- Does it match the markdown output?
- Is the schema version `diagnose-connection-v1`?

## Known limitations and untestable scenarios

- **Can't retrieve AiSurface or AiResponseFormat XML** — the CLI registry blocks these types. The skill uses `sf org list metadata` to list them and dry-run deploys to validate them. This is a platform limitation, not a bug.
- **Format naming convention assumes build-custom-connection pattern** — if formats were created manually with different naming, Method A won't find them. Method B (dry-run) would still catch missing formats if we knew their names.
- **One custom connection per agent** — this is a platform limit. The skill flags it as an issue if multiple are found.
- **Local JSON schema check depends on CWD** — only works if the user runs the skill from a directory containing `.aiResponseFormat` source files.
- **Multi-version bundle warning is untestable** — all agents in test-org have a single version (v1). The version mismatch warning (plan says: "Agent has N versions — active: vX, most recent: vY") can't be triggered. To test this, you'd need to create an agent with multiple versions in the org. Acknowledged as untested.
- **Mid-run permission failure is untestable on demand** — the plan says "mark that check as skipped with reason, continue remaining checks." This requires a user profile that passes pre-flight but lacks specific metadata permissions. Can't be reliably triggered in test-org where the user has full admin access. Acknowledged as untested.
