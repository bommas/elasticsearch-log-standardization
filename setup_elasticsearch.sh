#!/bin/bash

# === CONFIGURATION ===
API_KEY="SkVRaW5KZ0JRSy1YVXFsbEhrS206YTRjZ0lmMU5UTzF5b09vVW12SzBYQQ=="
ES_URL="https://dellollypoc.es.us-east-1.aws.found.io"

# Function to check if command was successful
check_status() {
    if [ $? -eq 0 ]; then
        echo "✅ $1 successful"
    else
        echo "❌ $1 failed"
        exit 1
    fi
}

# Function to check if response contains error
check_response() {
    local response="$1"
    local action="$2"
    
    if echo "$response" | grep -q '"error"'; then
        echo "❌ $action failed with error:"
        echo "$response" | jq .error 2>/dev/null || echo "$response"
        exit 1
    elif echo "$response" | grep -q '"acknowledged":true'; then
        echo "✅ $action successful"
    else
        echo "✅ $action completed"
    fi
}

echo "🚀 Setting up Elasticsearch index template and ingest pipeline..."
echo

# Remove pipeline from any existing indices first
echo "🗑️  Removing pipeline from existing indices..."
response=$(curl -s -X PUT "$ES_URL/logs1-*/_settings" \
  -H "Content-Type: application/json" \
  -H "Authorization: ApiKey $API_KEY" \
  -d '{"index.default_pipeline": null}' 2>/dev/null)
echo "Pipeline removal from indices response: $response"

echo

# Delete existing indices to force new mapping
echo "🗑️  Deleting existing indices to apply new mapping..."
response=$(curl -s -X DELETE "$ES_URL/logs1-*" \
  -H "Authorization: ApiKey $API_KEY" 2>/dev/null)
echo "Index deletion response: $response"

echo

# Delete existing index template if it exists
echo "🗑️  Deleting existing index template (if exists)..."
response=$(curl -s -X DELETE "$ES_URL/_index_template/logs_standardizer_template" \
  -H "Authorization: ApiKey $API_KEY" 2>/dev/null)
echo "Template deletion response: $response"

echo

# Delete existing ingest pipeline if it exists
echo "🗑️  Deleting existing ingest pipeline (if exists)..."
response=$(curl -s -X DELETE "$ES_URL/_ingest/pipeline/logs_standardizer" \
  -H "Authorization: ApiKey $API_KEY" 2>/dev/null)
echo "Pipeline deletion response: $response"

echo

# Create index template
echo "📝 Creating index template..."
response=$(curl -s -X PUT "$ES_URL/_index_template/logs_standardizer_template" \
  -H "Content-Type: application/json" \
  -H "Authorization: ApiKey $API_KEY" \
  --data-binary "@index_template.json")

check_response "$response" "Index template creation"
echo

# Create ingest pipeline
echo "⚙️  Creating ingest pipeline..."
response=$(curl -s -X PUT "$ES_URL/_ingest/pipeline/logs_standardizer" \
  -H "Content-Type: application/json" \
  -H "Authorization: ApiKey $API_KEY" \
  --data-binary "@ingest_pipeline.json")

check_response "$response" "Ingest pipeline creation"
echo

echo "🎉 Setup complete! You can now run bulk_load.sh to load your data."
