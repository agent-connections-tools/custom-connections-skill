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

## Test org details

- **Org alias:** `test-org`
- **Primary test agent:** `Agentforce_Service_Agent` (display name: "TestSimple")
  - Connections: Telephony (standard), CustomerWebClient (standard), ServiceEmail (standard), BaxterCreditUnion_BCU01 (custom)
  - Response formats: BaxterCreditUnionChoices_BCU01, BaxterCreditUnionChoicesWithImages_BCU01
  - Status: v1 is Active
- **Standard-only agent:** `Agentforce_Employee_Agent`
  - Connections: Messaging (standard only — no custom connection)
- **Other agents with bundles:** `Agentforce_Service_Agent2`, `TestEscalation`
- **Agents without bundles (retrieve will fail):** `Copilot_for_Salesforce`, `TestAgent3`, `Soap_Demo`, `testTelephony`, `testAgent`, `BCU_Test`, `VoiceAgentTest`

## Check inventory (happy path)

When running against `Agentforce_Service_Agent` with "all" connections, these are the exact checks the skill runs. The expected count is **13 passed, 1 warning, 0 issues**.

| # | Check | Expected result | Source |
|---|-------|----------------|--------|
| 1 | Agent retrieved | passed | Step 4 |
| 2 | Activation status | **warning** (v1 is Active) | Step 4 |
| 3 | Version | passed (single version v1) | Step 4 |
| 4 | API version consistency | passed (v66.0) | Step 4 |
| 5 | Telephony | passed (standard, Salesforce-provided) | Step 5 |
| 6 | Web Chat | passed (standard, Salesforce-provided) | Step 5 |
| 7 | Email | passed (standard, Salesforce-provided) | Step 5 |
| 8 | Custom connection exists | passed (BaxterCreditUnion_BCU01 in org) | Step 5 |
| 9 | Adaptive responses | passed (enabled) | Step 5 |
| 10 | Only one custom connection | passed | Step 5 |
| 11 | No duplicate connections | passed | Step 5 |
| 12 | Response formats found | passed (2 found by naming convention) | Step 5 |
| 13 | Response formats validated | passed (dry-run deploy succeeded) | Step 5 |
| 14 | JSON schema check | passed (info: no local files in this directory) | Step 5 |

Note: Pre-flight environment checks (CLI installed, org connected, API version ≥ 62.0) run before these and stop execution if they fail. They may or may not appear as separate lines in the report depending on how the skill formats them. What matters: if they pass, the main checks run.

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
- Total: 13 passed, 1 warning, 0 issues (see check inventory above)

**Review for:**
- Are all messages in plain English? No metadata jargon?
- Does the report use Setup → navigation paths for fix instructions?
- Is the JSON report well-formed and matches the markdown report?
- Does the check count in the summary line match the inventory above?

---

### Scenario 2: Diagnose a single connection

**Run:** `/project:diagnose-connection` with org `test-org`, agent `Agentforce_Service_Agent`, then pick **only the custom connection** (BaxterCreditUnion_BCU01)

**Expected result:**
- Environment and agent-level checks still run (retrieved, version, activation, API version)
- Standard connections (Telephony, Web Chat, Email) are **skipped** — not in the report
- Only the custom connection checks appear: exists, adaptive responses, one custom limit, no duplicates, formats found, formats validated, JSON schema
- Fewer total checks than Scenario 1

**Review for:**
- Does the skill actually skip the unselected connections? (Not just hide them)
- Is the report shorter than the "all" report?
- Does the summary count reflect only the checks that ran?

---

### Scenario 3: Wrong agent name

**Run:** Give agent name `Nonexistent_Agent`

**Expected result:**
- Retrieve fails
- Skill shows available agents by querying BotDefinition
- Asks the user to pick the correct one
- Does NOT crash or show a raw stack trace

**Review for:**
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
- Only standard connections listed (Messaging)
- No custom connection checks run — no format validation, no adaptive response check, no duplicate check
- Report makes sense without custom-specific sections
- No errors about missing formats

**Review for:**
- Does the skill handle the "no custom connection" case gracefully?
- Does the report still make sense without custom connection checks?
- Is the Messaging connection listed correctly?

---

### Scenario 6: Response format validation (dry-run)

**What to check:** The skill uses two methods to validate response formats:
1. **Naming convention match** — looks for formats matching `<ClientName><Type>_<SurfaceId>`
2. **Dry-run deploy** — re-deploys the real surface (using the actual surface name from the bundle) in dry-run mode to confirm formats exist

**Expected result for test-org (Agentforce_Service_Agent):**
- Method A finds 2 formats: BaxterCreditUnionChoices_BCU01, BaxterCreditUnionChoicesWithImages_BCU01
- Method B uses the real surface name `BaxterCreditUnion_BCU01` (not a generated stub or prefixed name)
- Dry-run succeeds, confirming both formats are valid and deployed

**Review for:**
- Does it use the real surface name `BaxterCreditUnion_BCU01.aiSurface` for the dry-run? (Not `DiagnoseCheck_` or any other prefix)
- Does the dry-run show as "Changed" (not "Created")? This confirms it's treating it as an update to the existing surface.
- If the dry-run fails, does it report which specific formats are missing?

---

### Scenario 7: Local JSON schema check

**Context:** The plan says "JSON.parse the `<input>` field to catch malformed schemas." Since AiResponseFormat XML can't be retrieved from the org (CLI blocks it), the skill checks local `.aiResponseFormat` files in the current working directory as a convenience. This covers cases where the user has the source files from a previous `build-custom-connection` run.

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
- Info note: "I couldn't check your response format JSON schemas because there are no local .aiResponseFormat files in this directory."

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
- Does the summary line at the bottom match the actual check count? (See check inventory)

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

## Known limitations

- **Can't retrieve AiSurface or AiResponseFormat XML** — the CLI registry blocks these types. The skill uses `sf org list metadata` to list them and dry-run deploys to validate them. This is a platform limitation, not a bug.
- **Format naming convention assumes build-custom-connection pattern** — if formats were created manually with different naming, Method A won't find them. Method B (dry-run) would still catch missing formats if we knew their names.
- **One custom connection per agent** — this is a platform limit. The skill flags it as an issue if multiple are found.
- **Local JSON schema check depends on CWD** — only works if the user runs the skill from a directory containing `.aiResponseFormat` source files.
