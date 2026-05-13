# test-connection — Skill Plan (v3 — final)

**Author:** Abhi Rathna
**Date:** 2026-05-13
**Status:** Build-ready. All open questions validated against test-org on 2026-05-13.

---

## What This Skill Does

Given an org alias, agent name, and ECA credentials, the skill starts a real Agent API session, sends a test message, and validates the response. It tells the user whether the connection works end-to-end and — if not — exactly what's wrong.

This is the third skill in the build / diagnose / test trio:
- `build-custom-connection` — creates the metadata
- `diagnose-connection` — checks the metadata is configured correctly
- `test-connection` — confirms the agent actually responds correctly when called

`build-custom-connection` and `diagnose-connection` both reference this skill in their docs as "the runtime test" — this plan makes good on that promise.

---

## Who It's For

**Primary persona:** Salesforce Admins who've built or configured a connection and want to verify it works end-to-end — without writing curl commands or reading raw JSON.

**Secondary persona:** Developers building client apps who want to see what the Agent API actually returns for a given surface type before writing their own integration code.

---

## Non-Technical UX Requirements

This skill must be usable by Salesforce Admins who have **never** written a curl command, read an OAuth JWT, or interacted with the Agent API directly. The same accessibility bar as `build-custom-connection` and `diagnose-connection`. Specifically:

**Language:**
- **Plain English everywhere.** No metadata jargon. Don't say "plannerSurfaces", "surfaceConfig.surfaceType", "JWT scope claim", "result[] array", "GenAiPlannerBundle", or "AiResponseFormat" in user-facing messages. Translate to: "your connection", "the connection type", "your access permissions", "the agent's response", "your agent's configuration", "your response format files."
- **Setup → navigation paths**, not URLs or API endpoints. "Setup → External Client Apps Manager → your app → OAuth Settings" instead of "the ConnectedApp metadata."
- **Action verbs in fix instructions.** "Click Activate" not "set the Status field to Active." "Copy the Consumer Key" not "extract the OAuth client_id."

**Conversation flow:**
- **One question at a time.** Never dump 5 inputs at once. Wait for each answer before asking the next. Same pattern as `build-custom-connection` and `diagnose-connection`.
- **Run commands without asking permission.** Don't say "shall I run sf org display?" — just run it and show the result.
- **Help the user find inputs they don't know.** When asking for the agent name, offer two ways to find it (Setup → Agents OR `sf data query`). When asking for ECA credentials, point to the exact Setup screen.
- **Walk through ECA setup if they don't have one.** Don't fail with "ECA not configured" — guide them through the 6 steps in the Setup UI.

**Error messages:**
- Every error has **What this means** (1-sentence plain-English explanation) and **How to fix** (concrete step with Setup → navigation path or exact command).
- Never show raw API errors or stack traces. Translate them. Example: instead of `"invalid_client_id"`, show "Your Consumer Key isn't recognized in this org. Check Setup → External Client Apps → your app → Settings → OAuth Settings → Consumer Key."
- When something fails, the user should know **why** and **what to do next** without leaving the terminal.

**Report:**
- **Top priority line.** First line of the report tells the user the single most important thing — passed end-to-end, or the highest-priority fix. Same pattern as diagnose-connection.
- **Connections shown by friendly name** (Telephony, Web Chat, Email) where possible — not raw `SurfaceAction__CustomerWebClient` names.
- **Render structured responses visually** (numbered choices, image cards, time picker) — not raw JSON. The JSON is in the file for CI/CD; the terminal shows what the user actually wants to see.
- **No metadata schema language in the report.** Show "found 4 choices" not "the result[] entry has 4 elements in the choices array." Show "The agent picked the AcmePortalChoices format" not "type: SURFACE_ACTION__AcmePortalChoices_ACME01."

**Transparency:**
- Show what the skill is doing without making the user read it. Brief status updates: "Logging in...", "Starting session...", "Sending your message...", "Waiting for response..." (the 5s waiting indicator).
- If a check is skipped (no local files, no `<apiVersion>` tag, etc.), say so plainly with a one-line reason. Don't silently omit.

**README and GUIDE updates:**
- The skill must be added to `README.md` and `GUIDE.md` with the same treatment as `build-custom-connection` and `diagnose-connection`:
  - **README:** A "Quick Start: Testing your connection" section with the questions the skill asks, a sample report, and what the skill does.
  - **GUIDE:** A new step (likely Step 11) "Testing your connection end-to-end" that explains the test sequence in plain language, what the report sections mean, and what the skill can't catch (e.g., visual rendering issues — that's the user's app).

---

## The Problems It Solves

Every one of these failure modes was hit during real testing of `build-custom-connection`. The `examples/verify-connection.sh` script handles the basic OAuth + session flow, but it doesn't surface the *why* when something fails:

| # | Failure Mode | What the User Sees Today | How test-connection Handles It |
|---|--------------|--------------------------|-------------------------------|
| 1 | ECA not configured / wrong Consumer Key | `invalid_client_id` error | "Your Consumer Key isn't recognized in this org. Check Setup → External Client Apps → your app → Settings → OAuth Settings → Consumer Key." |
| 2 | Client Credentials Flow not enabled | "no client credentials user enabled" | "Your ECA doesn't have Client Credentials Flow enabled. Go to Setup → External Client Apps → your app → Policies tab → enable 'Enable Client Credentials Flow' and set a Run As user." |
| 3 | Missing OAuth scopes | OAuth succeeds but Agent API returns 401 | Decode the JWT scope claim and verify all 4 required scopes are present (api, refresh_token, chatbot_api, sfap_api). Report which are missing. |
| 4 | Run As user lacks permissions | Token works but session creation fails | Tell the user to verify the Run As user has 'API Only access' or appropriate profile. If pre-flight passes but session creation 401s, mention permset/profile as a likely cause. |
| 5 | Wrong agent ID | 404 on session creation | Query BotDefinition first, validate the agent exists before attempting session. |
| 6 | Agent is deactivated | Session creation fails or returns errors | Check BotVersion status before attempting. Surface "Your agent needs to be **active** to test it. If you just ran diagnose-connection or deployed changes, you may have deactivated it." |
| 7 | Wrong field names in request body | 400 with field validation errors | Use only the 4 fields the skill actually sends: `externalSessionKey`, `instanceConfig`, `streamingCapabilities`, `surfaceConfig`. **No** `forceConfigEndpoint` (deprecated), `streamingConfig` (wrong name), or `externalClientId` (not in the schema). The full list of valid fields the API accepts is in the Validation Results section — refer to it there if a future skill version needs more fields. |
| 8 | Agent API runtime not provisioned on org | 404 from `test.api.salesforce.com` | Detect orgfarm/dev-ed orgs, warn upfront: "Agent API runtime isn't typically available on Developer Edition or orgfarm orgs. Use a sandbox or production org." |
| 9 | Response comes back as plain text on a Custom connection (no format triggered) | Hard to tell if connection works or if the agent just didn't pick a format | After sending a message, parse the `result[]` array. If empty AND the connection is Custom, report "agent responded with plain text — your connection works but the agent didn't trigger a structured format. Try a more targeted prompt or verify your topic instructions." If empty AND the connection is standard, this is expected behavior — don't warn. |
| 10 | Long-response timeout (knowledge/RAG agents take 30-60s) | curl appears to hang with no output | Set curl `--max-time 90`. Show a "waiting for response..." message after 5s of silence so users don't think it's broken. Treat 408/timeout as a warning, not a hard failure. |

---

## How It Works

### Inputs (5 questions, asked one at a time)

1. **What's your org alias?** (e.g., `my-org`). If they're not sure, suggest running `sf org list`.

2. **What's your agent's developer name?** Help them find it:
   - Go to **Setup → Agents** and look at the API Name column
   - Or run: `sf data query --query "SELECT DeveloperName FROM BotDefinition" --target-org <org>`

3. **Which connection do you want to test?** Retrieve the agent's bundle (reuse diagnose-connection's multi-version fallback logic), list all connections with their type:
   ```
   1. Telephony (standard)
   2. Web Chat (standard)
   3. Email (standard)
   4. BaxterCreditUnion_BCU01 (custom)
   ```
   The skill passes the bundle's raw `surfaceType` value through to the API. The API accepts all standard surface types — no mapping needed (validated empirically — see Validation Results).

4. **Do you have an External Client App set up for the Agent API?**
   - If yes → ask for the **Consumer Key** and **Consumer Secret** (from **Setup → External Client Apps Manager → your app → OAuth Settings**)
   - If no → walk them through creating one (see ECA Setup Guide section)

5. **What message do you want to send?** Suggest a default based on the connection's response formats:
   - Custom with choices format: "What products do you recommend?"
   - Custom with time picker: "I'd like to schedule an appointment"
   - Standard or no known formats: "Hello, I need help"
   - Let them type their own or accept the suggestion
   - Explain: "The message needs to trigger a topic that produces a list or structured output — that's what makes the agent use a response format."

**Secrets handling:** Credentials live in memory for the test run only. Never written to disk. Never logged. The JSON report sanitizes them to `<redacted>`.

### Pre-flight Checks

> **State requirement is INVERTED from build/diagnose.** `build-custom-connection` and `diagnose-connection` both want the agent **deactivated** before running. `test-connection` requires the agent to be **active** — you can't send messages to a deactivated agent.

Run these before any API calls. Stop early with clear messages if any fail.

1. **Salesforce CLI installed** — `sf --version`
2. **Org connected** — `sf org display --target-org $ORG_ALIAS`
3. **API version ≥ 62.0** — from org display output
4. **Agent exists** — retrieve the bundle (same logic as diagnose-connection, including multi-version fallback for agents with versioned bundles like `BCU_Test_v1`, `BCU_Test_v2`)
5. **Agent is active** — query BotVersion for Status = 'Active'. If deactivated, stop with: "Your agent needs to be **active** to test it. If you just ran diagnose-connection or deployed changes, you may have deactivated it. Go to **Setup → Agents → select your agent → Activate**."
6. **Selected connection is on the agent** — verify the chosen surface exists in the bundle's plannerSurfaces
7. **ECA credentials work for OAuth** — attempt the client_credentials grant. If it fails, surface the specific error (invalid_client_id, no client credentials user enabled, etc.) with the exact Setup → navigation path to fix it
8. **Required scopes present** — decode the returned JWT, verify `api`, `refresh_token`, `chatbot_api`, and `sfap_api` are all in the `scope` claim. Missing scopes get named in the error.
9. **Agent API runtime endpoint available** — the OAuth response should include `api_instance_url`. If it returns only `instance_url` (no Agent API runtime), warn: "Your org may not have the Agent API runtime provisioned. This is common on Developer Edition or orgfarm orgs. The test may fail at session creation."

### Inline Status Display

Right after retrieving the agent, the skill shows the agent's name and current state inline before any other checks:

```
Found agent: Customer_Support_Agent (v2 — active, ready to test)
```

If the agent is inactive, this message is the first place the user sees it — the fix instruction (Setup → Agents → Activate) follows immediately. This avoids the scenario where someone runs test-connection right after diagnose-connection without re-activating.

### Test Sequence

After pre-flight, the skill runs three checks against the live API:

**Check 1: Session creation**
- POST to `<api_instance_url>/einstein/ai-agent/v1/agents/<agentId>/sessions`
- Body uses validated structure: `externalSessionKey`, `instanceConfig`, `streamingCapabilities: {chunkTypes: ["Text"]}`, `surfaceConfig: {surfaceType: "$BUNDLE_SURFACE_TYPE"}`
- The `$BUNDLE_SURFACE_TYPE` is the raw value from the bundle's plannerSurfaces (e.g., `Custom`, `Telephony`, `Messaging`). No mapping needed.
- Pass if session ID is returned. Fail with the response body if 4xx/5xx.

**Check 2: Send message and receive response**
- POST to `<api_instance_url>/einstein/ai-agent/v1/sessions/<sessionId>/messages`
- Body: the test message from input
- Use curl `--max-time 90` (knowledge/RAG agents can take 30-60s). Show a "waiting for response..." message after 5s of silence.
- Pass if a 200 response is received with messages.
- Capture the full response payload.

**Check 3: Validate response shape**
- Parse `messages[*].result[]` array.
- **For Custom connections:**
  - If `result[]` contains `{"type": "SURFACE_ACTION__<formatName>", "value": "<JSON-string>"}` → pass. Connection is working end-to-end.
    - The `value` is a **string-encoded JSON object** (validated empirically). Use `JSON.parse(value)` to extract `message` and `choices`/other format fields.
    - Look up the matching local `.aiResponseFormat` file by name (Decision #10). If found, run structural validation against it. If the agent picked a format not in local files, skip validation (don't fail), just show the raw JSON.
  - If `result[]` is empty but a text response came back → warning. "Connection works (session started, message sent, response received) but the agent returned plain text instead of a structured format. Try a more targeted prompt, or check your agent's topics."
- **For standard connections:**
  - `result[]` is expected to be empty (standard connections don't use response formats). The agent's reply is in `messages[*].message`. Report as passed.
- If session creation succeeded but message send failed → fail with the API error body.

### Interactive Mode (multi-turn, opt-in)

After showing each response, ask: **"Want to send another message, or are you done?"**

- If the user says yes: increment `sequenceId` (1, 2, 3...) and send the next message in the same session.
- If the user says no: end the session (cleanup) and compile the report.
- **Hard cap: 5 turns.** If the agent hasn't returned a structured format by turn 5 (on a Custom connection), report "connection works (session + N messages) but no structured format was triggered after 5 turns" and suggest checking topic instructions.

**Report semantics: single-response, not transcript.** The skill grades the **last meaningful structured response** — not the full conversation. The JSON output captures the final graded response, not every turn. This keeps the report logic simple while preserving the multi-turn protocol the primary persona needs (admins who don't know the exact trigger phrase).

### Output

Two formats, same pattern as diagnose-connection:

**1. Markdown (terminal):**

```
=== Connection Test Report: Customer_Support_Agent ===

▶ Top result: ✓ Connection works end-to-end. Agent responded using
  AcmePortalChoices_ACME01 format with 4 choices (turn 2 of 2).

PRE-FLIGHT
  ✓ Salesforce CLI installed
  ✓ Org 'my-org' connected
  ✓ Agent 'Customer_Support_Agent' is active (v2)
  ✓ OAuth credentials valid (token issued)
  ✓ All required scopes present (api, refresh_token, chatbot_api, sfap_api)
  ✓ Agent API runtime available

TEST SEQUENCE
  ✓ Session created (ID: 019e...)
  ✓ Turn 1: "What can you help me with?" → plain text
  ✓ Turn 2: "Show me my plan options" → AcmePortalChoices_ACME01
  ✓ Response shape valid (matched local AcmePortalChoices_ACME01.aiResponseFormat)

WHAT THE AGENT RETURNED
  Format: AcmePortalChoices_ACME01
  Message: "Here are the plans we offer:"
  Choices:
    1. Starter Plan ($5/month)
    2. Basic Plan ($10/month)
    3. Professional Plan ($25/month)
    4. Enterprise Plan ($50/month)

  Schema source: ./output/unpackaged/aiResponseFormats/AcmePortalChoices_ACME01.aiResponseFormat

WARNINGS (0)
  None.

ISSUES (0)
  None.

=== Summary: 9 passed, 0 warnings, 0 issues ===
=== Connection works end-to-end. ===
```

**2. JSON (saved to `/tmp/test-connection-report.json`):**

> Note: `$schema: "test-connection-v1"` is the **output schema version**, not the plan version. This is the first release of the JSON output format. The plan version (v3) tracks the planning/review process, not the output schema. CI consumers should check `$schema` to detect future schema changes.

```json
{
  "$schema": "test-connection-v1",
  "agent": "Customer_Support_Agent",
  "bundleVersion": "v2",
  "connection": "AcmePortal_ACME01",
  "timestamp": "2026-05-13T...",
  "passed": 9,
  "warnings": 0,
  "failed": 0,
  "topResult": "Connection works end-to-end",
  "turnsUsed": 2,
  "checks": [
    { "name": "session_created", "status": "passed", "detail": "Session ID: 019e..." },
    { "name": "structured_response", "status": "passed", "detail": "Format: AcmePortalChoices_ACME01" },
    { "name": "schema_validation", "status": "passed", "detail": "Validated against ./output/unpackaged/aiResponseFormats/AcmePortalChoices_ACME01.aiResponseFormat" }
  ],
  "response": {
    "format": "AcmePortalChoices_ACME01",
    "message": "Here are the plans we offer:",
    "choices": ["Starter Plan ($5/month)", "..."]
  }
}
```

The structured response payload is included so CI pipelines can assert on the shape (e.g., "must return at least 3 choices").

---

## Technical Approach

### Building on verify-connection.sh

The existing `examples/verify-connection.sh` already implements the OAuth + session start flow. The skill prompt instructs Claude to use the same mechanics, plus:
- The 3-check sequence above
- Plain-English error mapping for the failure modes
- The richer report format
- Multi-turn session handling

No bash script wrapping needed — the skill is just guided invocation of the same `curl` calls with structured interpretation.

### Why this is read-mostly (not strictly read-only)

The skill creates an Agent API session, which is a real org-side resource (consumes Flex Credits, generates a session record). It cleans up by ending the session at the end of the run.

This is different from `diagnose-connection` (truly read-only). `test-connection` is closer to "minimum-write": it makes the smallest possible test interaction with the org and cleans up after itself. The user should be aware this counts toward their session/credit usage.

### surfaceType — pass-through, no mapping

**Empirical finding (Q1):** The Agent API accepts all surface type values without translation. Both bundle-style (`Telephony`, `Messaging`, `CustomerWebClient`, `ServiceEmail`) and the documentation's "API-style" names (`MessagingForInAppAndWeb`, `NextGenChat`, `Voice`, `Email`) all return 200 from session creation against test-org. No mapping table needed — the skill passes the bundle's raw `surfaceType` value straight through to `surfaceConfig.surfaceType`.

### Multi-Version Agent Support

Same approach as diagnose-connection: if `GenAiPlannerBundle:$AGENT_NAME` fails to retrieve, search for versioned bundles (`${AGENT_NAME}_v*`), find the active version via BotVersion query, and retrieve that bundle. Use the agent name for display, the bundle name for file paths.

### ECA Setup Guide (when user has no ECA)

When the user doesn't have an External Client App, walk them through it step by step. This is the #1 blocker for first-time users.

1. **Create the app:** Go to **Setup → External Client Apps Manager → New**, name it (e.g., "Agent Test Client"), choose "Web App"
2. **Configure OAuth scopes** — enable: `api`, `refresh_token/offline_access`, `chatbot_api`, `sfap_api`
3. **OAuth settings** — enable: "Client Credentials Flow" and "JWT-based access tokens for named users"
4. **OAuth settings** — disable: "Require Secret for Web Server Flow", "Require Secret for Refresh Token Flow", "Require PKCE"
5. **Policy tab:** Enable Client Credentials Flow, set "Run As (Username)" to a user with **API Only access** permission
6. **Get credentials:** Copy Consumer Key (client ID) and Consumer Secret (client secret) from OAuth Settings

After they complete this, loop back to Question 4 and ask for their credentials.

### Response Format Rendering

Render structured responses in a human-readable way in the terminal:

**Text Choices:**
```
  1. Check my balance
  2. Make a payment
  3. Talk to a representative
```

**Choices with Images:**
```
  ┌─────────────────────────────────────────────┐
  │ 1. Premium Plan                             │
  │    [image: https://example.com/premium.png] │
  │    → Select Premium                         │
  ├─────────────────────────────────────────────┤
  │ 2. Basic Plan                               │
  │    [image: https://example.com/basic.png]   │
  │    → Select Basic                           │
  └─────────────────────────────────────────────┘
```

**Time Picker:**
```
  Time picker: starting at 09:00
  "Choose your preferred time"
```

**Unknown/Custom Formats:** Pretty-print the raw JSON.

Important: `result[].value` is a **string-encoded JSON object** (empirical finding from Q9). The skill must `JSON.parse(value)` before extracting `message` / `choices` / etc. Direct field access on the raw `value` won't work.

### Schema Validation Logic (Decision #10)

When `result[]` contains a `SURFACE_ACTION__<formatName>` entry:

1. **Match by triggered format name first.** Look in the working directory for `.aiResponseFormat` files. Find the one whose developer name matches the format the agent used (e.g., agent picked `AcmePortalChoices_ACME01` → look for `AcmePortalChoices_ACME01.aiResponseFormat`).
2. **If matching local file found:** Parse the `<input>` element as JSON Schema. Validate the parsed `value` structurally — required fields present, types correct, arrays non-empty. Don't pull in a JSON Schema library; flat structural checks are sufficient.
3. **If no matching local file (agent used a format not in local files):** Skip validation, show the raw parsed JSON. Don't fail — this is normal when the user runs the skill from a directory that only has some of the agent's formats.
4. **If no `.aiResponseFormat` files in CWD at all:** Skip validation entirely, show raw JSON. Don't try harder than this.
5. **Always report which file was used as the schema source** in the markdown and JSON output. Catches stale local files where the user modified the format in the org but didn't rebuild locally.

### Credential Handling

- Never write credentials to a file (no config, no JSON reports with tokens)
- Never display them in terminal output
- Hold in shell variables only for the duration of the test
- End the session on exit — tokens aren't reusable across sessions
- JSON report sanitizes all credentials to `<redacted>`

### Cleanup — Always

Wrap the test sequence in a `try/finally`-style pattern in the skill prompt: whether the test passes, fails, or crashes mid-run, **always** end the session before exiting. The failure path is where orphaned sessions are most likely — explicit cleanup prevents Flex Credit drain.

### Where It Lives

```
custom-connections-skill/
├── .claude/commands/
│   ├── build-custom-connection.md     # existing
│   ├── diagnose-connection.md         # existing
│   └── test-connection.md             # new
```

Same repo, same pattern.

### Skill Prompt Structure

```
# Test Agent Connection
## Your role
## Step 1: Gather input (org, agent, connection, ECA, message)
## Step 2: Pre-flight checks (CLI, org, agent active, OAuth, scopes, runtime)
## Step 3: Display agent status inline (active — ready to test)
## Step 4: Create session
## Step 5: Send test message (with --max-time 90 + waiting indicator at 5s)
## Step 6: Validate response shape (Custom vs standard logic split)
## Step 7: Render response in human-readable format
## Step 8: Ask "Want to send another message, or are you done?" (cap at 5 turns)
## Step 9: End session (always, even on failure)
## Step 10: Compile and display results (markdown + JSON)
## Output templates
## Error handling rules
## Important rules (secret handling, runtime side effects, always-cleanup)
```

---

## What It Does NOT Do

- **Does not deploy or modify metadata.** This skill exercises the Agent API, not the metadata API. The only org-side effect is a temporary session (which is cleaned up).
- **Does not test true streaming responses.** v1 uses `chunkTypes: ["Text"]` which returns a single JSON body (validated empirically — Q9). True streaming via the `messagesStream` endpoint is a v2 candidate.
- **Does not create the ECA for you.** Walks you through setup step by step, but you do it in the Setup UI. Auto-creating ECAs would require different metadata and permissions — v2 candidate.
- **Does not store credentials.** Secrets are held in shell variables only for the test duration. Never logged, never written to disk.
- **Does not test against the Agent Builder preview.** Preview doesn't support custom connections — that's a documented platform limitation. This skill always tests via the Agent API.
- **Does not test all connections at once.** One connection per test run. Testing "all" would require separate sessions per surface type.
- **Does not exceed 5 turns.** Multi-turn is capped to keep test runs bounded and prevent runaway sessions.
- **Does not validate against schemas the user doesn't have locally.** AiResponseFormat XML can't be retrieved via the CLI. If the user's working directory doesn't have the matching `.aiResponseFormat` file, the skill shows the raw JSON without trying to validate.

---

## Effort Estimate

| Task | Hours (multi-turn) | Hours (no multi-turn) |
|------|--------------------|-----------------------|
| Skill prompt (`.claude/commands/test-connection.md`) | ~5 | ~4 |
| Schema validation + format-match logic | ~1.5 | ~1.5 |
| Response format rendering logic | ~2 | ~2 |
| ECA setup guide (in-skill walkthrough) | ~1 | ~1 |
| Testing against test-org (all connection types, error cases, multi-turn flow) | ~4 | ~3 |
| Documentation (README + GUIDE updates) | ~1 | ~1 |
| **Total** | **~14.5h** | **~12.5h** |

**Note:** Q1, Q2, Q8, Q9, Q10 are all resolved (see Validation Results below). The 3-4h "validate open questions" block from v2 is no longer needed. Effort is reduced from 15-17h (v2) to 14.5h.

**Risk margin:** Add 2h if `test-org` doesn't already have an ECA configured for the runtime test pass — setting up an ECA from scratch (OAuth scopes, Client Credentials Flow, Run As user, etc.) is the most likely source of build-time slip. Verify ECA presence before counting hours.

---

## Decisions Made

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **ECA OAuth, not sf CLI token** | The skill should authenticate the same way the user's client app will. If the ECA isn't set up, that's worth discovering now. sf CLI token shortcut is a v2 candidate. |
| 2 | **Walk through ECA setup in-skill** | The #1 blocker is OAuth configuration. Without this, most users can't get past authentication. |
| 3 | **Interactive multi-turn protocol, single-response report semantics** | Send message, show response, ask "Want to send another, or are you done?" Cap at 5 turns. Grade the **last meaningful structured response** — not the transcript. JSON output captures the final graded response only. ~1h impl (loop + prompt), not 3h. |
| 4 | **Non-streaming in v1** | `chunkTypes: ["Text"]` returns a single JSON body (validated — Q9). Streaming via the `messagesStream` endpoint is a v2 candidate. |
| 5 | **Reuse bundle retrieval from diagnose-connection** | Same multi-version fallback, same connection listing. No reason to reinvent. |
| 6 | **Never store credentials** | OAuth secrets in files are a security risk. Hold in shell variables, clear on exit. |
| 7 | **Render structured responses in terminal** | The whole point is showing what the response looks like. Raw JSON alone isn't useful to admins. |
| 8 | **Always end session on exit** | Don't leave orphaned sessions consuming org resources. Even on error, attempt cleanup. Wrap in try/finally pattern. |
| 9 | **Suggest messages based on format type** | Reduces friction — the user doesn't have to guess what message will trigger a structured response. |
| 10 | **Local-first schema fallback, structural validation only (top-level fields only)** | Match by triggered format name first. Validate structurally if matching local file found: required top-level fields present (e.g., `message` exists as a string, `choices` exists as a non-empty array). **Do not recurse into array items** — checking that each `choices[i]` has `title`/`imageUrl`/`actionText` would require a JSON Schema library. The raw JSON display already lets the user eyeball nested structure. If agent picked a format not in local files: skip validation, show raw JSON, don't fail. If no local files at all: skip entirely. Always report which file was used as schema source. |
| 11 | **One connection per test** | Multiple connections need separate sessions and the output gets confusing. Keep it focused. |
| 12 | **Plain text on Custom = warning, on standard = expected** | Standard connections don't use response formats. `result: []` on a standard connection is normal — don't warn. On a Custom connection it's a warning ("agent didn't trigger a format"). |
| 13 | **Same repo, same namespace** | `/project:test-connection`. Migrates to `/agentforce:` with the family later. |
| 14 | **JWT scope validation in pre-flight** | Catches "wrong scopes" before it manifests as a 401 mid-test. Cheaper to fail fast with a clear message. If pre-flight passes but session creation 401s, mention permset/profile as a likely cause. |
| 15 | **All standard connection types supported (pass-through)** | Validated empirically (Q1) — the Agent API accepts all surface type values without mapping. Pass the bundle's raw `surfaceType` value straight to `surfaceConfig.surfaceType`. Same session flow works for Custom, Voice, Telephony, Messaging, Email, etc. (Q10). |
| 16 | **Inline agent status display** | Right after retrieval, show "Found agent X (active — ready to test)" before any other checks. Avoids the user running test-connection right after diagnose-connection without re-activating. |
| 17 | **90-second curl timeout with 5s "waiting" indicator** | RAG/knowledge agents can take 30-60s to respond. Set `--max-time 90`. Show "waiting for response..." after 5s of silence so users don't think it hung. Treat 408/timeout as a warning, not a hard failure. |

---

## Validation Results — All Open Questions Resolved

Validated against test-org on 2026-05-13 (BCU_Test agent, BaxterCreditUnion_BCU01 custom connection):

| # | Question | Result | How resolved in plan |
|---|----------|--------|---------------------|
| Q1 | Which surfaceType values does the Agent API accept? | **All 9 tested values accepted** (Custom, MessagingForInAppAndWeb, NextGenChat, Voice, Email, Telephony, Messaging, CustomerWebClient, ServiceEmail). | Decision #15. Pass the bundle's raw surfaceType value through. No mapping table. |
| Q2 | Does the session-creation request need an `externalClientId`? | **`externalClientId` is not a recognized field.** API returns "Unrecognized field" error. The 14 valid fields are: `tz, surfaceType, botMode, conversationContext, surfaceConfig, richContentCapabilities, externalSessionKey, instanceConfig, streamingCapabilities, featureSupport, executionHistory, parameters, bypassUser, variables`. | Failure mode #7 documents the valid fields list. Skill never sends `externalClientId`. |
| Q3 | Canonical "end session" API call? | `DELETE /einstein/ai-agent/v1/sessions/<sessionId>` returns 200 silently. | Decision #8 + cleanup section. Skill always issues DELETE on exit. |
| Q4 | Direct input or env var for the secret? | Direct input chosen (admin persona). | Credential Handling section. JSON output sanitizes to `<redacted>`. |
| Q5 | Does `useStreaming: false` reliably produce a non-streaming response? | The `chunkTypes: ["Text"]` parameter returns a **single JSON body**, not chunked stream. (Streaming requires the `messagesStream` endpoint.) Latency: 5-10s in test-org. | Decision #4 + Check 2. Skill uses the non-streaming endpoint. |
| Q6 | Are there scope-related 401s that pass JWT decoding? | Untestable in test-org (admin user has full access). Documented as a fallback ("if pre-flight passes but session creation 401s, mention permset/profile as a likely cause"). | Failure mode #4. |
| Q7 | Multi-turn vs single-message? | Keep multi-turn, opt-in shape, capped at 5 turns. Report grades last meaningful structured response. | Decision #3. |
| Q8 | Long-response timeout behavior? | Test-org latency is 5-10s (no RAG agents available locally). Production agents with knowledge can hit 30-60s. | Decision #17. 90s curl timeout + 5s "waiting" indicator. |
| Q9 | `chunkTypes: ["Text"]` shape? | **Single JSON body, not chunked.** Streaming requires the `messagesStream` endpoint. | Decision #4 + What It Does NOT Do (no true streaming in v1). |
| Q10 | Standard connections — different session flow? | **No.** All surface types use the same session creation endpoint and message flow. Standard connections return `result: []` (empty — no formats wired). | Decision #12 + Decision #15. Different report semantics for empty `result[]` based on connection type. |

**Bonus finding from Q9:** `result[].value` is a **string-encoded JSON object** — needs `JSON.parse(value)` to extract `message` / `choices`. Direct field access fails. Documented in Response Format Rendering section.

---

## Relationship to Other Skills

```
build-custom-connection     diagnose-connection       test-connection
      (create)          →     (verify config)     →    (verify runtime)
 "Deploy the metadata"     "Is it wired correctly?"  "Does it actually work?"
```

The three skills form a complete lifecycle:
1. **Build** — generates and deploys metadata (agent must be deactivated)
2. **Diagnose** — validates configuration is correct (agent must be deactivated for fixes)
3. **Test** — proves the connection works at runtime (agent must be **active**)

The state flip (deactivated → active) between diagnose and test is intentional. The skill calls it out clearly in pre-flight #5, the inline status display, the failure mode table, and this section.

## Relationship to verify-connection.sh

The repo already has `examples/verify-connection.sh` — a bash script that starts a session and reports CONNECTED/FAILED. The skill is a superset:

| | verify-connection.sh | test-connection skill |
|--|---------------------|----------------------|
| Starts session | Yes | Yes |
| Sends a message | No | Yes |
| Shows the response | No | Yes — human-readable + raw JSON |
| Multi-turn (opt-in) | No | Yes (capped at 5 turns) |
| Helps with ECA setup | No | Yes — step-by-step guide |
| Error messages with fix instructions | Minimal | Yes — every error explained |
| Works with standard connections | No (hardcoded Custom) | Yes — all surface types (validated) |
| Schema validation | No | Yes (local-first, structural) |
| 90s timeout + waiting indicator | No | Yes |

The script stays useful for CI/CD smoke tests. The skill is for interactive testing and first-time setup.

---

## Build-Time Notes (not plan changes — implementation guidance)

These came up during sign-off and belong in the skill prompt, not the plan:

- **Future-proof the field list:** If the Agent API returns an "Unrecognized field" error the skill hasn't seen before, show the raw error verbatim and suggest the user check for Agent API changelog updates. Don't try to maintain a hardcoded valid-fields list in the skill prompt — let the API tell us when it changes. (The 14 fields documented in Validation Results are a snapshot, not a contract.)

- **Don't expose the 14-field list to the user.** The list in the Validation Results section is defensive documentation for the skill author, not for end users. The skill always sends the correct 4 fields (`externalSessionKey`, `instanceConfig`, `streamingCapabilities`, `surfaceConfig`) — users never need to see the full list. If a user does hit an "Unrecognized field" error, fall back to the future-proofing rule above.

- **Format name match must be exact.** When matching the triggered `SURFACE_ACTION__<formatName>` against local `.aiResponseFormat` files, use exact developer-name equality — not `startsWith` or `contains`. Otherwise `AcmePortalChoices_ACME01` would falsely match `AcmePortalChoicesWithImages_ACME01` and validate against the wrong schema. The skill should strip the `SURFACE_ACTION__` prefix from the type field, then match exactly against the basename of each local file (without the `.aiResponseFormat` extension).

---

## Reviewer Sign-off Checklist

Before declaring v3 final, confirm:

**Plan completeness:**
- [ ] All three reviewer rounds incorporated (R1, R2, R3 — see Changelog v3 entry)
- [ ] All 10 open questions empirically resolved against test-org
- [ ] Decision #15 (all standard types supported) confirmed by Q1 + Q10 validation — no contradiction with open questions

**Behavior:**
- [ ] State-flip prominence: pre-flight #5 + inline status (#16) + failure mode #6 + Relationship section
- [ ] Schema validation handles format mismatch case (don't fail when agent picks a format not in local files)
- [ ] Multi-turn is opt-in, capped at 5 turns, single-response report semantics
- [ ] 90s timeout + 5s "waiting" indicator for long-running agents
- [ ] Always-cleanup pattern in skill prompt
- [ ] `result[].value` JSON.parse step documented in rendering logic
- [ ] No `externalClientId` in any sample request
- [ ] **No surfaceType mapping table in the skill prompt** — surfaceType is pass-through (Decision #15). If a mapping table sneaks in (e.g., copy-pasted from earlier drafts), remove it. The bundle's raw value goes straight to `surfaceConfig.surfaceType`.

**Non-technical UX (matches build/diagnose bar):**
- [ ] Plain English in all user-facing text — no metadata jargon (plannerSurfaces, surfaceConfig, JWT, GenAiPlannerBundle, etc.)
- [ ] One question at a time, never dump all 5 inputs upfront
- [ ] Every error has "What this means" + "How to fix" with Setup → navigation paths or exact commands
- [ ] ECA setup walkthrough included for users who don't have one
- [ ] Top priority line at the start of the report
- [ ] Standard connections shown with friendly names (Telephony, Web Chat, Email) — not raw SurfaceAction__ names
- [ ] Structured responses rendered visually (numbered choices, image cards, time picker) — not raw JSON
- [ ] Brief status updates during long operations ("Starting session...", "Waiting for response...")
- [ ] README.md updated with "Quick Start: Testing your connection" section
- [ ] GUIDE.md updated with a new step (likely Step 11) explaining test-connection in plain language

---

## Changelog

- **v1 (2026-05-13):** Initial draft. 10 failure modes, 4-question input flow, 3-check test sequence, markdown + JSON output. Two open questions on session cleanup and secret handling.
- **v2 (2026-05-13):** Reviewer pass. Updated Decision #10 from "no schema validation in v1" to "local-first schema fallback, structural validation only." Added Open Question #7: multi-turn vs single-message-per-run. State flip and always-cleanup confirmed.
- **v3 (2026-05-13 — final):** Three rounds of reviewer feedback consolidated + all 10 open questions empirically validated against test-org. **Non-Technical UX Requirements section added** — same accessibility bar as build-custom-connection and diagnose-connection. Plain English, one question at a time, ECA walkthrough, friendly connection names, visual response rendering, README + GUIDE updates required. Sign-off checklist now includes 11 non-technical UX items.
- **v3.1 (2026-05-13 — post-review polish):** Reviewer pass on v3 surfaced 5 clarifications. None blocking; all prevent misreads during build:
  - **Failure mode #7** trimmed: skill prompt only references the 4 fields it actually sends. Full 14-field list lives in Validation Results, not the failure mode table.
  - **JSON output `$schema`** clarified: schema version is `v1` (output format), plan version is v3 (planning process). They're independent.
  - **Decision #10** clarified: structural validation is **top-level only** — don't recurse into array items. Checking each `choices[i]` would require a JSON Schema library.
  - **Risk margin** redirected: real risk is ECA setup in test-org, not schema edge cases. Verify ECA presence before counting build hours.
  - **Sign-off checklist**: added "no surfaceType mapping table in the skill prompt" — Decision #15 eliminated the mapping; if a table sneaks in via copy-paste, remove it.
  - **Multi-turn (Q7) resolved:** opt-in, 5-turn cap, single-response report semantics. ~1h impl (Decision #3 updated).
  - **Schema validation (Decision #10) refined:** match by triggered format name, skip validation if format not in local files (don't fail), report which file was used as schema source.
  - **surfaceType mapping eliminated:** Q1 + Q10 validation showed the API accepts all surface type values. Pass-through, no mapping. Decision #15 holds.
  - **`externalClientId` removed entirely:** Q2 confirmed it's not a recognized field. Failure mode #7 lists the 14 valid fields.
  - **Long-response handling added (Decision #17):** 90s curl timeout + 5s "waiting" indicator (Q8).
  - **`result[].value` parsing documented:** string-encoded JSON requires nested parse (Q9 bonus finding).
  - **Standard connection semantics added (Decision #12):** empty `result[]` on standard connections is expected, not a warning.
  - **Inline agent status (Decision #16):** "Found agent X (active — ready to test)" right after retrieval prevents whipsaw between diagnose and test.
  - **Pre-flight error message tweak:** explicit reference to diagnose-connection ("if you just ran diagnose-connection or deployed changes, you may have deactivated it").
  - **Effort revised:** 14.5h with multi-turn, 12.5h without. Down from 15-17h (v2) because Q-validation block is no longer needed.
  - **Reviewer sign-off checklist added** for the final review pass.
  - **Status: Build-ready.** No more open questions. Pending only sign-off from reviewers.
