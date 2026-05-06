# Review Feedback — Round 2

**Reviewer:** Deep Work Agent (for Abhi Rathna)
**Date:** May 6, 2026
**Status:** Most issues from Round 1 are resolved. One remaining item.

---

## What Was Fixed (Confirmed)

All high-priority items from Round 1 have been addressed in the README:

| Original Issue | Status |
|----------------|--------|
| Prerequisites too sparse — no install links or context | Fixed. Now includes install commands, links, "you only do this once" framing |
| "Agent bundle name" is an unknown term | Fixed. "Finding your agent bundle name" section added with query command and example output |
| "What gets generated" table too technical | Fixed. Reframed as "What the skill creates for you" with plain-English descriptions |
| Missing "when/why would I use this" | Fixed. "Is this for me?" section added at the top |
| Explanatory sentence below JSON example | Fixed. Moved above the JSON block |
| Missing "what does my app need to do" | Fixed. Section added with link to GUIDE.md Step 8 |

---

## One Remaining Issue

### Bundle name guidance may be fragile

The README currently says:

> Append `_v1` to it (e.g., `Customer_Support_Agent_v1`) — that's your bundle name.

This assumes the bundle always ends in `_v1`. If an agent has been versioned (redeployed, recreated), it could be `_v2`, `_v3`, etc. A user following this instruction would get a "bundle not found" error with no idea why.

**Fix — pick one:**

**Option A (safest):** Replace the `_v1` instruction with a direct query for the bundle name:
```bash
sf data query --query "SELECT DeveloperName FROM GenAiPlannerBundle" --target-org my-org
```
This always returns the exact name.

**Option B (simpler):** Keep the `_v1` guidance but add a fallback:
> "Typically ends in `_v1`. If the deploy script says it can't find the bundle, run this to get the exact name:"
> ```bash
> sf data query --query "SELECT DeveloperName FROM GenAiPlannerBundle" --target-org my-org
> ```

Option B is probably better for the non-techie audience — it gives a happy path that works 90% of the time and a clear escape hatch for the other 10%.

---

## Files That Need No Changes

- **GUIDE.md** — Solid. No updates needed.
- **.claude/commands/build-custom-connection.md** — Well-designed. No updates needed.
- **deploy.sh logic** — Good UX (pause for confirmation, stage markers, error messages).
- **Troubleshooting table** — Covers the key gotchas.

---

## Verdict

After this one fix, the repo is ready for a non-technical user. The README now reads as a clear, confidence-building guide rather than a developer reference.
