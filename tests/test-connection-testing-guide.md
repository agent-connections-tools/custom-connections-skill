# Testing Guide: test-connection skill

## What this skill does

The `test-connection` skill sends a real message through an Agentforce agent's connection (custom or standard) and tells you, in plain English, whether it works end-to-end. It's the **runtime** test in the build / diagnose / test trio:

- `build-custom-connection` — creates the metadata
- `diagnose-connection` — checks the metadata is wired correctly
- `test-connection` — confirms the agent actually responds when called

**State requirement is the OPPOSITE of build/diagnose.** This skill needs the agent to be **active**. Both other skills need it deactivated. The skill calls this out explicitly when it runs.

The skill is **read-mostly** — it creates a temporary Agent API session and cleans it up at the end. It never modifies metadata.

## How to run it

From the `custom-connections-skill` project directory:

```
/project:test-connection
```

The skill asks five questions (one at a time):
1. Your org alias (use `test-org`)
2. Your agent's developer name (use `BCU_Test`)
3. Which connection to test (it lists what it found and lets you pick)
4. Your ECA Consumer Key + Consumer Secret (see Test ECA details below)
5. The test message (or accept its suggestion)

Then it runs pre-flight checks, creates a session, sends the message, renders the response, and asks if you want to send another (capped at 5 turns).

**Reviewing intermediate steps:** This is a Claude Code skill (prompt instructions to Claude), not a standalone script. When reviewing, you're watching three things:
1. **The conversation flow** — did Claude ask one question at a time? Did it walk through ECA setup if asked?
2. **The final report** — the markdown output and JSON file
3. **Claude's tool calls** — the OAuth, session, and message API requests in the terminal. Confirm Claude sends only the 4 valid fields (`externalSessionKey`, `instanceConfig`, `streamingCapabilities`, `surfaceConfig`) and never `forceConfigEndpoint`, `streamingConfig`, or `externalClientId`.

## Test org details

**Org alias:** `test-org`

**Test ECA (already configured):**
- Consumer Key and Consumer Secret are **NOT in this guide**. Get them from the project owner (Abhi) via Slack DM or 1Password. They authenticate to a shared test org — don't paste them into any public channel, public repo file, or Claude Code transcript that could be saved.
- The ECA has all required scopes (`api`, `refresh_token`, `chatbot_api`, `sfap_api`), Client Credentials Flow enabled, and a Run As user with API Only access.
- Reviewers should not need to set up a new ECA for these tests — but Scenario 8 specifically tests the ECA-setup walkthrough by simulating "I don't have one."

**Important:** The skill itself does not store or log credentials. They live in shell variables only for the test run and are sanitized to `<redacted>` in the JSON report. Reviewers should verify that — NEVER find the actual Consumer Secret in `/tmp/test-connection-report.json` or any saved log.

**Test agents:**

- **`BCU_Test`** (multi-version, **v2 is Active**, primary test agent)
  - Custom connection: `BaxterCreditUnion_BCU01`
  - Response formats: `BaxterCreditUnionChoices_BCU01`, `BaxterCreditUnionChoicesWithImages_BCU01`
  - Bundle name is `BCU_Test_v2` (NOT `BCU_Test` — multi-version fallback required)
  - Trigger message: `"What plans do you offer?"` reliably triggers `BaxterCreditUnionChoices_BCU01`

- **`Agentforce_Service_Agent`** (display name "TestSimple", **v1 is Active**)
  - Connections: Telephony (standard), CustomerWebClient (standard), ServiceEmail (standard), BaxterCreditUnion_BCU01 (custom)
  - Same custom connection as BCU_Test but reachable via standard surfaces too

- **`Agentforce_Employee_Agent`** (**v1 is Inactive**)
  - One standard connection (Messaging)
  - Use this for the deactivated-agent scenario

- **`TestEscalation`** (v1 Inactive)
  - Custom connection `MicrosoftTeams` — response format `TeamsText` doesn't follow the build-custom-connection naming pattern
  - Use this to test naming-mismatch handling on a Custom connection

## Check inventory

### BCU_Test — custom connection, format triggers

Expected: **9 passed, 0 warnings, 0 issues**

| # | Check | Expected | Notes |
|---|-------|----------|-------|
| 1 | CLI installed | passed | `sf --version` succeeds |
| 2 | Org connected | passed | `test-org` resolves |
| 3 | API version ≥ 62.0 | passed | Org is v67.0 |
| 4 | Agent retrieved | passed | Multi-version fallback: bare name fails, retrieves `BCU_Test_v2` |
| 5 | Agent active status | passed | v2 is Active, ready to test |
| 6 | OAuth token obtained | passed | Client credentials grant succeeds |
| 7 | Required scopes present | passed | api + refresh_token + chatbot_api + sfap_api |
| 8 | Session created | passed | Returns session ID |
| 9 | Structured response triggered | passed | Format: `BaxterCreditUnionChoices_BCU01` |

Schema validation:
- If `BaxterCreditUnionChoices_BCU01.aiResponseFormat` is in CWD → "passed (matched local file)"
- If not → "skipped — no matching local schema, raw JSON shown"

### Agentforce_Employee_Agent — standard connection, no format

Expected: **8 passed, 0 warnings, 0 issues**

| # | Check | Expected | Notes |
|---|-------|----------|-------|
| 1 | CLI installed | passed | |
| 2 | Org connected | passed | |
| 3 | API version ≥ 62.0 | passed | |
| 4 | Agent retrieved | passed | Standard single-version agent |
| 5 | Agent active status | **failed (stop)** | v1 is Inactive — skill stops here |

The skill should stop at check 5 with the state-flip error message. **Do NOT continue to OAuth or session creation.** This validates that the inverse-of-diagnose state requirement is enforced.

### Agentforce_Service_Agent — standard connection (no format), happy path

Expected: **9 passed, 0 warnings, 0 issues**

When the user picks the **Telephony** connection:

| # | Check | Expected | Notes |
|---|-------|----------|-------|
| 1-7 | Pre-flight + OAuth | passed | |
| 8 | Session created | passed | `surfaceType: "Telephony"` accepted as-is (no mapping) |
| 9 | Response received | passed | Empty `result[]` is **expected** for standard connections — not a warning |

The "what the agent returned" section should show the agent's text reply (from `messages[*].message`), not a structured format.

### TestEscalation — custom with naming mismatch

Expected: **8 passed, 1 warning, 0 issues**

| # | Check | Expected | Notes |
|---|-------|----------|-------|
| 1-8 | Pre-flight + OAuth + session | passed | |
| 9 | Structured response | **warning** | Agent returned plain text — your message didn't trigger a format |

The warning should suggest a more targeted prompt or checking topic instructions. **Should NOT crash** when format names don't match the build-custom-connection convention.

## Test scenarios

### Scenario 1: Happy path — custom connection with format

**Run:** `/project:test-connection` against `test-org`, agent `BCU_Test`, choose `BaxterCreditUnion_BCU01`, message `"What plans do you offer?"`

**Expected result:**
- All 5 questions asked one at a time
- Multi-version fallback triggers (bare-name retrieve fails, finds `BCU_Test_v2`)
- Inline agent status appears: "Found agent: BCU Test (v2 — active, ready to test)"
- OAuth token obtained, all 4 scopes verified
- Session created with `surfaceConfig.surfaceType: "Custom"`
- Message sent, response received within ~10 seconds
- Response renders visually with numbered choices (Starter Plan, Basic Plan, etc.)
- After response, asks "Want to send another message, or are you done?"
- User says "done" → session deleted (DELETE call to `/sessions/<id>`)
- Final report: 9 passed, 0 warnings, 0 issues
- JSON saved to `/tmp/test-connection-report.json`

**Critical things to verify (watch tool calls):**
- Session creation request body has EXACTLY 4 fields: `externalSessionKey`, `instanceConfig`, `streamingCapabilities`, `surfaceConfig`. NOT `forceConfigEndpoint`, NOT `streamingConfig`, NOT `externalClientId`.
- Terminal summary count matches JSON `passed`/`warnings`/`failed` exactly
- `result[].value` is parsed via `JSON.parse(value)` (the value is a string-encoded JSON object — direct field access would fail)
- Session DELETE call happens at the end

**Review for:**
- Are all messages in plain English? No "plannerSurfaces", "surfaceConfig", "JWT scope" in user-facing output?
- Does the report use Setup → navigation paths for fix instructions?
- Does the choices list render visually, not as raw JSON?

---

### Scenario 2: Multi-turn — agent asks clarifying question first

**Run:** Same as Scenario 1, but use a vague first message: `"Help me"`. After the agent's response, send a more targeted second message: `"Show me your account types"`.

**Expected result:**
- Turn 1: agent likely returns plain text (asking what kind of help)
- Skill asks "Want to send another message, or are you done?" — user says yes
- Turn 2: agent returns structured choices
- Final report grades **only the last meaningful structured response** (turn 2), not the whole conversation
- JSON `turnsUsed: 2`
- Session deleted at the end

**Review for:**
- Does the skill correctly use `sequenceId: 1` for turn 1, `sequenceId: 2` for turn 2?
- Does the report grade the turn 2 response, not turn 1?
- Does the JSON output include the final response only, not the full transcript?

---

### Scenario 3: 5-turn cap reached without structured format

**Run:** Same as Scenario 1, but keep sending vague messages that don't trigger formats: `"Help"`, `"Tell me more"`, `"What do you do"`, `"OK"`, `"Cool"`. After turn 5, the skill should stop asking and report.

**Expected result:**
- Turns 1-5 all return plain text
- After turn 5, skill stops the loop automatically (does NOT ask "Want to send another?" a 6th time)
- Warning in the report: "Connection works (session + 5 messages) but no structured format was triggered after 5 turns. Check your agent's topics — they may not produce structured responses for the messages you tried."
- Session deleted at the end

**Review for:**
- Does the skill enforce the 5-turn cap?
- Is the warning message helpful — does it suggest checking topic instructions?

---

### Scenario 4: Wrong agent name

**Run:** Give agent name `Nonexistent_Agent`

**Expected result:**
- Pre-flight (CLI, org connection) passes
- Bundle retrieve returns "Succeeded" with a warning (CLI returns exit code 0 even when not found)
- Skill detects the bundle file wasn't created, queries `BotDefinition` to list available agents
- Asks user to pick the correct one
- Does NOT crash or show a stack trace

**Review for:**
- Does the skill detect the silent retrieve failure (the same way diagnose-connection does)?
- Is the list of available agents shown in plain English?

---

### Scenario 5: Wrong org alias

**Run:** Give org alias `fake-org`

**Expected result:**
- Pre-flight check #2 (org connection) fails
- Skill stops immediately with: "I can't connect to your org 'fake-org'. Run `sf org login web --alias fake-org` to log in."
- Does NOT continue to ECA prompt or any API calls

**Review for:**
- Clean stop, no partial results
- Fix instruction is concrete

---

### Scenario 6: Deactivated agent (state-flip enforcement)

**Run:** Give agent name `Agentforce_Employee_Agent` (v1 is Inactive)

**Expected result:**
- Pre-flight passes
- Bundle retrieves successfully
- Inline status display: "Found agent: Agentforce Employee Agent (v1 — inactive)"
- Skill stops with the state-flip message: "Your agent needs to be **active** to test it. If you just ran `diagnose-connection` or deployed changes, you may have deactivated it. Go to Setup → Agents → select your agent → Activate."
- Does NOT continue to OAuth or session creation

**Review for:**
- Does the error message reference diagnose-connection explicitly? (Prevents whipsaw between the two skills)
- Is the fix instruction a concrete Setup → navigation path?

---

### Scenario 7: Wrong ECA credentials

**Run:** Use `BCU_Test`, but provide an obviously fake Consumer Key (e.g., `FAKE_KEY_FOR_TESTING_REJECTION`)

**Expected result:**
- Pre-flight passes through agent retrieve and active status check
- OAuth call fails with `invalid_client_id`
- Skill maps the error to plain-English fix: "Your Consumer Key isn't recognized in this org. Check Setup → External Client Apps → your app → Settings → OAuth Settings → Consumer Key."
- Does NOT continue to session creation

**Review for:**
- Is the raw `invalid_client_id` translated to plain English?
- Does the fix instruction have a Setup → navigation path?

---

### Scenario 8: ECA walkthrough (user has no ECA)

**Run:** Same as Scenario 1, but answer "no" to "Do you have an External Client App set up?"

**Expected result:**
- Skill walks through the 6-step ECA setup process inline:
  1. Create the app in External Client Apps Manager
  2. Enable 4 OAuth scopes (api, refresh_token, chatbot_api, sfap_api)
  3. Enable Client Credentials Flow + JWT-based access tokens for named users
  4. Disable 3 settings (Require Secret for Web Server Flow, Require Secret for Refresh Token Flow, Require PKCE)
  5. Configure the Policy tab (Run As user with API Only access)
  6. Get Consumer Key and Consumer Secret
- After the walkthrough, asks for credentials and continues normally

**Review for:**
- Are all 6 steps in plain English with Setup → navigation paths?
- Does the skill loop back to the credentials question after the walkthrough?
- No metadata jargon (no "ConnectedApp", "OAuth scope claim", etc.)?

---

### Scenario 9: Standard connection (no format expected)

**Run:** Use `Agentforce_Service_Agent`, choose Telephony connection, message `"Hi"`

**Expected result:**
- Session created with `surfaceConfig.surfaceType: "Telephony"` (raw bundle value, no mapping)
- Message sent, agent responds with text
- `result[]` is empty — **this is expected**, not a warning
- Report shows: "Standard connection — agent responded with text (response formats only apply to custom connections)."
- Final summary: 9 passed, 0 warnings, 0 issues

**Critical things to verify:**
- Empty `result[]` on a standard connection should NOT trigger the "no format triggered" warning
- That warning is for Custom connections only

**Review for:**
- Does the report semantically distinguish standard vs custom?
- Does the skill use the bundle's raw surfaceType (e.g., `Telephony`) without trying to map to API names like `Voice`?

---

### Scenario 10: Naming mismatch on custom connection

**Run:** Use `TestEscalation`, choose `MicrosoftTeams` connection, message `"What can I do here?"`

**Context:** TestEscalation has a custom connection named `MicrosoftTeams` (no suffix ID). Its only response format is `TeamsText` — which doesn't follow the build-custom-connection naming pattern.

**Expected result:**
- Pre-flight: agent is INACTIVE (v1) → skill stops at Step 4 with state-flip error.

**Wait, this scenario can't run as-is.** TestEscalation needs to be Active to send messages. Either:
- (a) Reviewer activates TestEscalation in the org first, then runs this scenario
- (b) Skip Scenario 10 and instead use BCU_Test with a vague message that returns plain text — Scenario 3 already covers the no-format-triggered case

**For the reviewer:** activate TestEscalation if you want to exercise this path. Otherwise mark this scenario as untested.

If activated, expected result:
- Session creates, message sent, agent responds with plain text
- Warning: "Connection works (session + message + response received) but the agent returned plain text instead of a structured format."
- Should NOT crash trying to look up format files for `MicrosoftTeams` (no underscore = no parseable suffix)

---

### Scenario 11: Local schema validation

**How to test:** Run the skill from `examples/acme-portal/` (which has 3 local `.aiResponseFormat` files):
```
cd examples/acme-portal && /project:test-connection
```

**Run:** `BCU_Test`, choose `BaxterCreditUnion_BCU01`, message `"What plans do you offer?"`

**Expected result:**
- Skill triggers `BaxterCreditUnionChoices_BCU01`
- Looks for `BaxterCreditUnionChoices_BCU01.aiResponseFormat` in `examples/acme-portal/unpackaged/aiResponseFormats/`
- File NOT found (the directory has Acme files, not BCU files)
- Schema validation **skipped** (NOT failed) — this is the "format not in local files" path
- Report says: "Schema source: none — raw JSON shown"

**Run:** Same, but cd to a directory with `BaxterCreditUnion*.aiResponseFormat` files (if available) or modify a file name to match for testing.

**Expected result:**
- Skill finds the matching file by exact name (no startsWith/contains)
- Validates structurally: `message` is a string, `choices` is a non-empty array
- Does NOT recurse into array items (that would require a JSON Schema library)
- Report says: "Schema source: ./BaxterCreditUnionChoices_BCU01.aiResponseFormat"

**Review for:**
- Is the format name match **exact** (not prefix-based)? Verify by checking that `AcmePortalChoices_AcmePortal01` does NOT match `AcmePortalChoicesWithImages_AcmePortal01`.
- Is the validation top-level only?

---

### Scenario 12: Long-response timeout

**Run:** Use any agent with a knowledge-base or RAG-heavy topic. Send a complex query that requires retrieval.

**Expected result:**
- After 5 seconds of silence, skill displays: "Waiting for response — knowledge-heavy agents can take 30-60 seconds."
- If response arrives within 90 seconds → normal flow
- If curl times out at 90 seconds → warning, NOT failure: "The agent took longer than 90 seconds to respond. The connection itself is working, but the test couldn't complete in time."

**Note:** Test-org may not have RAG-configured agents. If so, this scenario is acknowledged as untested. The 90s timeout still protects against runaway requests.

---

## Things to specifically review

### 1. Language and tone (the bar)
- Every user-facing message in plain English?
- No metadata jargon: never see `plannerSurfaces`, `surfaceConfig.surfaceType`, `GenAiPlannerBundle`, `AiResponseFormat`, `JWT`, `OAuth scope claim` in user-facing output?
- Setup → navigation paths in fix instructions, not URLs?
- Action verbs in fixes ("Click Activate", "Copy the Consumer Key")?

### 2. Conversation flow
- Asks one question at a time (5 questions across Step 1)?
- Doesn't ask permission to run commands ("shall I run sf org display?") — just runs them?
- Walks through ECA setup if user says no?
- Brief status updates during long operations ("Logging in...", "Starting session...", "Sending your message...")?

### 3. Request shape (watch tool calls)
- Session creation request has EXACTLY 4 fields: `externalSessionKey`, `instanceConfig`, `streamingCapabilities`, `surfaceConfig`?
- NEVER sees `forceConfigEndpoint`, `streamingConfig`, or `externalClientId` in any request body?
- `surfaceConfig.surfaceType` uses the raw bundle value (e.g., `Custom`, `Telephony`, `Messaging`) — no mapping to `MessagingForInAppAndWeb`/`Voice`/etc.?

### 4. Response handling
- `result[].value` is parsed via `JSON.parse(value)` (the value is a string-encoded JSON, not a direct object)?
- Format name matching uses exact equality, not `startsWith` / `contains`?
- Custom connection with empty `result[]` → warning?
- Standard connection with empty `result[]` → expected, not a warning?

### 5. Multi-turn behavior
- Asks "Want to send another?" after each response?
- Increments `sequenceId` correctly (1, 2, 3, ...)?
- Stops at 5 turns with a sensible warning if no format triggered?
- Final report grades the LAST meaningful structured response, not the transcript?
- JSON output contains only the final graded response, not every turn?

### 6. State-flip enforcement
- Pre-flight stops if agent is inactive?
- Error message references diagnose-connection ("if you just ran diagnose-connection")?
- Inline status display shows "active" / "inactive" right after retrieval?

### 7. Cleanup
- DELETE call to `/sessions/<id>` happens at the end?
- DELETE happens even on failure (try/finally pattern)?
- Temp directory cleanup at the end?

### 8. Report quality
- Top priority line at the start?
- Connections shown with friendly names (Telephony, Web Chat, Email)?
- Structured responses rendered visually (numbered choices, image cards), not as raw JSON?
- Schema source path shown in the report?
- Terminal summary count matches JSON counts exactly?

### 9. JSON report
- Saved to `/tmp/test-connection-report.json`?
- Schema is `test-connection-v1`?
- Credentials NEVER appear (sanitized to `<redacted>` if leaked)?
- Counts match the markdown report?

### 10. Safety
- NEVER writes credentials to disk?
- NEVER logs credentials?
- Org-side state limited to the temporary session (which gets cleaned up)?
- Read-only against metadata (no deploys, no modifications)?

## Known limitations and untestable scenarios

- **RAG/knowledge timeouts (Scenario 12)** — test-org doesn't have RAG-configured agents. The 90s timeout and 5s "waiting" indicator are implemented but can't be triggered reliably in test-org.
- **Mid-run permission failures** — test-org user has full admin access. Can't trigger the "JWT decoded fine but session creation 401s due to profile" scenario.
- **TestEscalation naming-mismatch test** — agent is currently inactive. Reviewer needs to activate it manually to run Scenario 10.
- **ECA setup walkthrough (Scenario 8)** — the test ECA already exists. Reviewers can simulate "I don't have one" by answering no to Q4 and verifying the walkthrough renders correctly, but they don't need to actually create another ECA.
- **Schema validation against matching local files (Scenario 11 second part)** — depends on whether the reviewer has BCU-prefixed `.aiResponseFormat` files locally. The Acme-portal example files don't match BCU formats. Either generate matching files via build-custom-connection or skip this part of the scenario.

## Quick spot-check (5 minutes)

If you only have 5 minutes, run **Scenario 1** end-to-end. It exercises:
- Multi-version fallback
- All 5 input questions
- Pre-flight (CLI, org, API version, agent active, OAuth, scopes, runtime)
- Session creation with the correct 4 fields
- Message send + response receipt
- Structured response parsing (with the JSON.parse-on-value subtlety)
- Visual rendering of choices
- Multi-turn opt-in (answer "no" to skip turn 2)
- Session cleanup
- Markdown + JSON report

If Scenario 1 passes cleanly, the skill is fundamentally working. The other scenarios catch edge cases.
