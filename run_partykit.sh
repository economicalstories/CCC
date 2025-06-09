#!/bin/bash

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "Warning: .env file not found"
fi

# Check if access key is provided
if [ -z "$ACCESS_KEY" ]; then
    echo "Warning: ACCESS_KEY not set - server will run without authentication"
else
    echo "✅ ACCESS_KEY configured - authentication enabled"
fi

# Deploy PartyKit
echo "Deploying PartyKit server..."

cd partykit-server

if [ -n "$ACCESS_KEY" ]; then
    npx partykit deploy --var ACCESS_KEY=$ACCESS_KEY
else
    npx partykit deploy
fi

echo "Deployment complete. Tailing logs..."
npx partykit tail 