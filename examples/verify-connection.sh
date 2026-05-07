#!/bin/bash
# Verify your custom connection works by starting an Agent API session.
# Usage: ./verify-connection.sh <org-alias> <client-id> <client-secret> <agent-developer-name>
# Note: JSON parsing uses grep/cut (no jq dependency). For production use, parse with jq.

set -e

ORG_ALIAS="${1:?Usage: ./verify-connection.sh <org-alias> <client-id> <client-secret> <agent-developer-name>}"
CLIENT_ID="${2:?}"
CLIENT_SECRET="${3:?}"
AGENT_NAME="${4:?}"

ORG_URL=$(sf org display --target-org "$ORG_ALIAS" --json 2>&1 | grep '"instanceUrl"' | grep -o 'https://[^"]*')
if [ -z "$ORG_URL" ]; then
    echo "FAILED: Could not resolve org URL for alias '$ORG_ALIAS'"
    exit 1
fi

# Get access token
TOKEN_RESPONSE=$(curl -s -X POST "$ORG_URL/services/oauth2/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
# Prefer api_instance_url (Agent API runtime) over instance_url (org URL)
API_URL=$(echo "$TOKEN_RESPONSE" | grep -o '"api_instance_url":"[^"]*"' | cut -d'"' -f4)
if [ -z "$API_URL" ]; then
    API_URL=$(echo "$TOKEN_RESPONSE" | grep -o '"instance_url":"[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$ACCESS_TOKEN" ]; then
    echo "FAILED: Could not authenticate. Check your client_id and client_secret."
    echo "$TOKEN_RESPONSE"
    exit 1
fi

# Get agent ID
AGENT_ID=$(sf data query --query "SELECT Id FROM BotDefinition WHERE DeveloperName='$AGENT_NAME'" --target-org "$ORG_ALIAS" --json 2>&1 | grep '"Id"' | head -1 | grep -o '"[a-zA-Z0-9]\{18\}"' | tr -d '"')
if [ -z "$AGENT_ID" ]; then
    echo "FAILED: No agent found with DeveloperName '$AGENT_NAME'"
    exit 1
fi

# Start session with Custom surface
SESSION_RESPONSE=$(curl -s -X POST "$API_URL/einstein/ai-agent/v1/agents/$AGENT_ID/sessions" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"externalSessionKey\": \"verify-$(date +%s)\",
    \"forceConfigEndpoint\": \"$ORG_URL\",
    \"instanceConfig\": {\"endpoint\": \"$ORG_URL\"},
    \"streamingConfig\": {\"useStreaming\": false},
    \"surfaceConfig\": {\"surfaceType\": \"Custom\"}
  }")

SESSION_ID=$(echo "$SESSION_RESPONSE" | grep -o '"sessionId" *: *"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')

if [ -n "$SESSION_ID" ]; then
    echo "CONNECTED — session started successfully."
    echo "Session ID: $SESSION_ID"
    echo "Your custom connection is working."
else
    echo "FAILED: Could not start session with surfaceType: Custom"
    echo "$SESSION_RESPONSE"
    exit 1
fi
