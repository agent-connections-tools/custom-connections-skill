# test-connection — Skill Plan (v2)

**Author:** Abhi Rathna
**Date:** 2026-05-13
**Status:** Draft — 6 open questions need validation against test-org before building

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

## The Problems It Solves

Every one of these failure modes was hit during real testing of `build-custom-connection`. The `examples/verify-connection.sh` script handles the basic OAuth + session flow, but it doesn't surface the *why* when something fails:

| # | Failure Mode | What the User Sees Today | How test-connection Handles It |
|---|--------------|--------------------------|-------------------------------|
| 1 | ECA not configured / wrong Consumer Key | `invalid_client_id` error | "Your Consumer Key isn't recognized in this org. Check Setup → External Client Apps → your app → Settings → OAuth Settings → Consumer Key." |
| 2 | Client Credentials Flow not enabled | "no client credentials user enabled" | "Your ECA doesn't have Client Credentials Flow enabled. Go to Setup → External Client Apps → your app → Policies tab → enable 'Enable Client Credentials Flow' and set a Run As user." |
| 3 | Missing OAuth scopes | OAuth succeeds but Agent API returns 401 | Decode the JWT scope claim and verify all 4 required scopes are present (api, refresh_token, chatbot_api, sfap_api). Report which are missing. |
| 4 | Run As user lacks permissions | Token works but session creation fails | Tell the user to verify the Run As user has 'API Only access' or appropriate profile. |
| 5 | Wrong agent ID | 404 on session creation | Query BotDefinition first, validate the agent exists before attempting session. |
| 6 | Agent is deactivated | Session creation fails or returns errors | Check BotVersion status before attempting. Surface "Your agent is deactivated. Activate it before testing." |
| 7 | Wrong field names in request body | 400 with field validation errors | Always use the validated request structure (`instanceConfig`, `streamingCapabilities`, `surfaceConfig`) — no `forceConfigEndpoint`, no `streamingConfig`. |
| 8 | Agent API runtime not provisioned on org | 404 from `test.api.salesforce.com` | Detect orgfarm/dev-ed orgs, warn upfront: "Agent API runtime isn't typically available on Developer Edition or orgfarm orgs. Use a sandbox or production org." |
| 9 | Response comes back as plain text (no format triggered) | Hard to tell if connection works or if the agent just didn't pick a format | After sending a message, parse the `result[]` array. If empty, report "agent responded with plain text — your connection works but the agent didn't trigger a structured format. Try a more targeted prompt or verify your topic instructions." |
| 10 | Wrong response format triggered | Agent uses ChoicesWithImages when you expected Choices | Optional check: user can specify expected format. Report mismatch as a warning, not a failure. |

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
   The skill maps each connection to the right Agent API `surfaceType` value automatically (see surfaceType Mapping).

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

Run these before any API calls. Stop early with clear messages if any fail.

1. **Salesforce CLI installed** — `sf --version`
2. **Org connected** — `sf org display --target-org $ORG_ALIAS`
3. **API version ≥ 62.0** — from org display output
4. **Agent exists** — retrieve the bundle (same logic as diagnose-connection, including multi-version fallback for agents with versioned bundles like `BCU_Test_v1`, `BCU_Test_v2`)
5. **Agent is active** — query BotVersion for Status = 'Active'. If deactivated, stop with: "Your agent needs to be active to test it. Go to **Setup → Agents → select your agent → Activate**." (This is the opposite of diagnose-connection, which warns when agents are active.)
6. **Selected connection is on the agent** — verify the chosen surface exists in the bundle's plannerSurfaces
7. **ECA credentials work for OAuth** — attempt the client_credentials grant. If it fails, surface the specific error (invalid_client_id, no client credentials user enabled, etc.) with the exact Setup → navigation path to fix it
8. **Required scopes present** — decode the returned JWT, verify `api`, `refresh_token`, `chatbot_api`, and `sfap_api` are all in the `scope` claim. Missing scopes get named in the error.
9. **Agent API runtime endpoint available** — the OAuth response should include `api_instance_url`. If it returns only `instance_url` (no Agent API runtime), warn: "Your org may not have the Agent API runtime provisioned. This is common on Developer Edition or orgfarm orgs. The test may fail at session creation."

### Test Sequence

After pre-flight, the skill runs three checks against the live API:

**Check 1: Session creation**
- POST to `<api_instance_url>/einstein/ai-agent/v1/agents/<agentId>/sessions`
- Body uses validated structure: `externalSessionKey`, `instanceConfig`, `streamingCapabilities`, `surfaceConfig: {surfaceType: "$SURFACE_TYPE"}`
- The `$SURFACE_TYPE` is determined by the surfaceType mapping from the selected connection (see surfaceType Mapping)
- Pass if session ID is returned. Fail with the response body if 4xx/5xx.

**Check 2: Send message and receive response**
- POST to `<api_instance_url>/einstein/ai-agent/v1/sessions/<sessionId>/messages`
- Body: the test message from input (or default probe)
- Pass if a 200 response is received with messages.
- Capture the full response payload.

**Check 3: Validate response shape**
- Parse `messages[*].result[]` array.
- If `result[]` contains an entry with `type: "SURFACE_ACTION__<formatName>"` → pass. Custom connection is working end-to-end. Report which format was used.
- If `result[]` is empty but a text response came back → warning. "Connection works (session started, message sent, response received) but the agent returned plain text instead of a structured format. This usually means the agent didn't have a topic that produces choices. Try a more targeted prompt, or check your agent's topics."
- If session creation succeeded but message send failed → fail with the API error body.

### Interactive Mode

After showing the first response, ask: **"Want to send another message, or are you done?"**

If they want to continue:
- Increment `sequenceId` for each message (1, 2, 3, ...)
- Show each response the same way (human-readable rendering)
- Keep going until they say done or the agent ends the session (`EndSession` message type)

If they're done:
- End the session (cleanup)
- Show the test summary including all messages sent/received

Why multi-turn: A single message often isn't enough to trigger structured responses — the agent may ask a clarifying question first. Multi-turn lets you have the full conversation needed to reach a response format.

### Output

Two formats, same pattern as diagnose-connection:

**1. Markdown (terminal):**

```
=== Connection Test Report: Customer_Support_Agent ===

▶ Top result: ✓ Connection works end-to-end. Agent responded using
  AcmePortalChoices_ACME01 format with 4 choices.

PRE-FLIGHT
  ✓ Salesforce CLI installed
  ✓ Org 'my-org' connected
  ✓ Agent 'Customer_Support_Agent' is active (v2)
  ✓ OAuth credentials valid (token issued)
  ✓ All required scopes present (api, refresh_token, chatbot_api, sfap_api)
  ✓ Agent API runtime available

TEST SEQUENCE
  ✓ Session created (ID: 019e...)
  ✓ Message sent: "Show me my plan options"
  ✓ Response received (status 200)
  ✓ Structured response: AcmePortalChoices_ACME01

WHAT THE AGENT RETURNED
  Format: AcmePortalChoices_ACME01
  Message: "Here are the plans we offer:"
  Choices:
    1. Starter Plan ($5/month)
    2. Basic Plan ($10/month)
    3. Professional Plan ($25/month)
    4. Enterprise Plan ($50/month)

WARNINGS (0)
  None.

ISSUES (0)
  None.

=== Summary: 9 passed, 0 warnings, 0 issues ===
=== Connection works end-to-end. ===
```

**2. JSON (saved to `/tmp/test-connection-report.json`):**

```json
{
  "$schema": "test-connection-v1",
  "agent": "Customer_Support_Agent",
  "timestamp": "2026-05-13T...",
  "passed": 9,
  "warnings": 0,
  "failed": 0,
  "topResult": "Connection works end-to-end",
  "checks": [
    { "name": "session_created", "status": "passed", "detail": "Session ID: 019e..." },
    { "name": "structured_response", "status": "passed", "detail": "Format: AcmePortalChoices_ACME01" }
  ],
  "response": {
    "format": "AcmePortalChoices_ACME01",
    "message": "Here are the plans we offer:",
    "choices": [...]
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

No bash script wrapping needed — the skill is just guided invocation of the same `curl` calls with structured interpretation.

### Why this is read-mostly (not strictly read-only)

The skill creates an Agent API session, which is a real org-side resource (consumes Flex Credits, generates a session record). It cleans up by ending the session at the end of the run.

This is different from `diagnose-connection` (truly read-only). `test-connection` is closer to "minimum-write": it makes the smallest possible test interaction with the org and cleans up after itself. The user should be aware this counts toward their session/credit usage.

The skill's "What It Does NOT Do" section calls this out explicitly.

### surfaceType Mapping

The bundle XML has surface types like `Custom`, `Telephony`, `Messaging`. The Agent API session requires a `surfaceConfig.surfaceType` value. Based on GUIDE.md and the Agent API docs:

| Bundle surfaceType | Agent API surfaceType |
|-------------------|----------------------|
| `Custom` | `Custom` |
| `Messaging` | `MessagingForInAppAndWeb` |
| `CustomerWebClient` | `NextGenChat` |
| `Telephony` | `Voice` |
| `ServiceEmail` | `Email` |
| Unknown (e.g., `Test`) | Try the value as-is — warn that it may not work |

**Open question:** This mapping needs validation against test-org. See Open Questions #1.

### Multi-Version Agent Support

Same approach as diagnose-connection: if `GenAiPlannerBundle:$AGENT_NAME` fails to retrieve, search for versioned bundles (`${AGENT_NAME}_v*`), find the active version via BotVersion query, and retrieve that bundle. Use the agent name for display, the bundle name for file paths.

### ECA Setup Guide

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

### Credential Handling

- Never write credentials to a file (no config, no JSON reports with tokens)
- Never display them in terminal output
- Hold in shell variables only for the duration of the test
- End the session on exit — tokens aren't reusable across sessions
- JSON report sanitizes all credentials to `<redacted>`

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
## Step 1: Gather input (org, agent, consumer key, secret, optional test message)
## Step 2: Pre-flight checks (CLI, org, agent active, OAuth, scopes, runtime)
## Step 3: Create session
## Step 4: Send test message
## Step 5: Validate response shape
## Step 6: End session and clean up
## Step 7: Compile and display results
## Output templates (markdown + JSON)
## Error handling rules
## Important rules (secret handling, runtime side effects)
```

---

## What It Does NOT Do

- **Does not deploy or modify metadata.** This skill exercises the Agent API, not the metadata API. The only org-side effect is a temporary session (which is cleaned up).
- **Does not test streaming responses.** v1 uses `chunkTypes: ["Text"]` for full responses. Streaming (SSE) for real-time display is a v2 candidate.
- **Does not create the ECA for you.** Walks you through setup step by step, but you do it in the Setup UI. Auto-creating ECAs would require different metadata and permissions — v2 candidate.
- **Does not store credentials.** Secrets are held in shell variables only for the test duration. Never logged, never written to disk.
- **Does not test against the Agent Builder preview.** Preview doesn't support custom connections — that's a documented platform limitation. This skill always tests via the Agent API.
- **Does not validate response payloads against the declared JSON schema in v1.** AiResponseFormat can't be reliably retrieved (CLI blocks it). The skill shows the raw response — the user verifies the structure visually. Automated schema validation is a v2 candidate.
- **Does not test all connections at once.** One connection per test run. Testing "all" would require separate sessions per surface type.

---

## Effort Estimate

| Task | Hours |
|------|-------|
| Validate open questions against test-org (surfaceType mapping, response structure, auth flows) | ~3 |
| Skill prompt (`.claude/commands/test-connection.md`) | ~5 |
| Response format rendering logic | ~2 |
| ECA setup guide (in-skill walkthrough) | ~1 |
| Testing against test-org (all connection types, error cases, interactive mode) | ~4 |
| **Total** | **~15** |

The extra hours vs. diagnose-connection come from the open questions (empirical validation needed), the ECA setup guide, interactive mode (multi-turn session management), and response format rendering.

---

## Decisions Made

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **ECA OAuth, not sf CLI token** | The skill should authenticate the same way the user's client app will. If the ECA isn't set up, that's worth discovering now. sf CLI token shortcut is a v2 candidate. |
| 2 | **Walk through ECA setup in-skill** | The #1 blocker is OAuth configuration. Without this, most users can't get past authentication. |
| 3 | **Interactive mode (multi-turn)** | A single message often isn't enough to trigger structured responses — the agent may ask a clarifying question first. Multi-turn lets you have the full conversation. |
| 4 | **Non-streaming in v1** | Streaming (SSE) adds complexity — parsing partial chunks, handling reconnects. Full response is simpler and sufficient for testing. |
| 5 | **Reuse bundle retrieval from diagnose-connection** | Same multi-version fallback, same connection listing. No reason to reinvent. |
| 6 | **Never store credentials** | OAuth secrets in files are a security risk. Hold in shell variables, clear on exit. |
| 7 | **Render structured responses in terminal** | The whole point is showing what the response looks like. Raw JSON alone isn't useful to admins. |
| 8 | **Always end session on exit** | Don't leave orphaned sessions consuming org resources. Even on error, attempt cleanup. |
| 9 | **Suggest messages based on format type** | Reduces friction — the user doesn't have to guess what message will trigger a structured response. |
| 10 | **Local-first schema fallback, structural validation only** | AiResponseFormat XML can't be retrieved via the CLI. The skill looks for local `.aiResponseFormat` files in the working directory first (typically present from a recent `build-custom-connection` run). If found, use them as the source of truth and validate the response against them — but only structurally: required fields present, types correct, arrays non-empty. No full JSON Schema library. If no local files are found, fall back to showing the raw response for visual verification. Catches the failure modes that matter (empty choices, missing message, wrong type) without adding dependencies. |
| 11 | **One connection per test** | Multiple connections need separate sessions and the output gets confusing. Keep it focused. |
| 12 | **Plain text is not an error** | The agent choosing plain text over a response format is normal behavior. Report it clearly, suggest a different message, don't mark it as failed. |
| 13 | **Same repo, same namespace** | `/project:test-connection`. Migrates to `/agentforce:` with the family later. |
| 14 | **JWT scope validation in pre-flight** | Catches "wrong scopes" before it manifests as a 401 mid-test. Cheaper to fail fast with a clear message. |
| 15 | **All standard connection types supported** | Not just custom — the skill maps each bundle surfaceType to the Agent API's surfaceType value. Tests any connection on the agent. |

---

## Open Questions

| # | Question | Status | How to validate |
|---|----------|--------|-----------------|
| 1 | **What are the exact surfaceType values the Agent API accepts?** GUIDE.md shows `Custom`. Need to confirm `MessagingForInAppAndWeb`, `NextGenChat`, `Voice`, `Email`. | Open | Start sessions with each surfaceType against test-org agents that have those connections |
| 2 | **What's the exact JSON structure of an Agent API response when a response format is used?** Where does the structured data live — `formatName`/`formatData`? `result[].type`? | Open | Send a message through the BaxterCreditUnion_BCU01 connection and inspect the full response |
| 3 | **Can the sf CLI access token (from `sf org display`) start Agent API sessions?** If yes, this would be a quick-test shortcut for v2. | Open | Try `curl` with the sf CLI token against the Agent API session endpoint |
| 4 | **What error does the Agent API return when the agent is inactive?** Need the exact error to provide a clear diagnostic message. | Open | Deactivate a test agent and attempt session creation |
| 5 | **What's the canonical "end session" API call?** GUIDE.md doesn't document it. If there's no DELETE endpoint, sessions auto-expire. | Open | Test DELETE against `<api_url>/einstein/ai-agent/v1/sessions/<id>` |
| 6 | **Should the skill accept the secret via direct input or environment variable?** Direct input is simpler for admins but visible in conversation. Env var (`SF_ECA_SECRET`) is more secure but adds friction. | Open | Decide based on persona. Likely: direct input in v1 with "never stored or logged" guarantee. |
| 7 | **Multi-turn interactive mode in v1: yes or no?** Decision #3 enables interactive multi-turn ("agent may ask a clarifying question first"). One reviewer prefers single-message-per-run for simplicity ("one message is enough to prove the format triggers"). Need to pick before building. | Open | Confirm the primary persona's actual workflow. If admins typically need clarifying turns to reach a structured response, keep multi-turn. If the test message can be tuned to trigger a format on turn 1, drop multi-turn for v1. |

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

The state flip (deactivated → active) between diagnose and test is intentional. The skill should call it out clearly.

## Relationship to verify-connection.sh

The repo already has `examples/verify-connection.sh` — a bash script that starts a session and reports CONNECTED/FAILED. The skill is a superset:

| | verify-connection.sh | test-connection skill |
|--|---------------------|----------------------|
| Starts session | Yes | Yes |
| Sends a message | No | Yes |
| Shows the response | No | Yes — human-readable + raw JSON |
| Interactive (multi-turn) | No | Yes |
| Helps with ECA setup | No | Yes — step-by-step guide |
| Error messages with fix instructions | Minimal | Yes — every error explained |
| Works with standard connections | No (hardcoded Custom) | Yes — all surface types |

The script stays useful for CI/CD smoke tests. The skill is for interactive testing and first-time setup.

---

## Changelog

- **v1 (2026-05-13):** Expanded from initial draft. Added: connection selection (Question 3), surfaceType mapping for all connection types, ECA setup guide, interactive multi-turn mode, response format rendering, multi-version agent support, credential handling rules. Dropped schema validation from v1 scope (AiResponseFormat not reliably retrievable). 6 open questions to validate before building.
- **v2 (2026-05-13):** Reviewer pass. Updated Decision #10 from "no schema validation in v1" to "local-first schema fallback, structural validation only" — catches malformed responses without adding a JSON Schema library dependency, falls back gracefully when local files aren't present. Added Open Question #7: whether to keep interactive multi-turn mode (Decision #3) or simplify to single-message-per-run for v1. State flip (deactivated → active) and always-cleanup-on-exit were already covered in v1 — confirmed both still in place.
