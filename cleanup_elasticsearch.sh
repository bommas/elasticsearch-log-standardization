#!/bin/bash

# === CONFIGURATION ===
API_KEY="SkVRaW5KZ0JRSy1YVXFsbEhrS206YTRjZ0lmMU5UTzF5b09vVW12SzBYQQ=="
ES_URL="https://dellollypoc.es.us-east-1.aws.found.io"

# Function to check if response contains errors
check_response() {
  local response="$1"
  local operation="$2"
  
  if echo "$response" | grep -q '"error"'; then
    echo "❌ $operation failed with error:"
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
    return 1
  elif echo "$response" | grep -q '"acknowledged":true\|"found":false'; then
    echo "✅ $operation successful"
    return 0
  else
    echo "✅ $operation completed"
    return 0
  fi
}

echo "🧹 Starting complete Elasticsearch cleanup..."
echo "⚠️  WARNING: This will delete ALL indices, templates, and pipelines related to logs1-*"
echo

# Remove pipeline from any existing indices first
echo "🔗 Removing pipeline from existing indices..."
response=$(curl -s -X PUT "$ES_URL/logs1-*/_settings" \
  -H "Content-Type: application/json" \
  -H "Authorization: ApiKey $API_KEY" \
  -d '{"index.default_pipeline": null}' 2>/dev/null)
echo "Pipeline removal response: $response"
echo

# Delete all indices matching logs1-* pattern
echo "🗑️  Deleting all logs1-* indices..."
response=$(curl -s -X DELETE "$ES_URL/logs1-*" \
  -H "Authorization: ApiKey $API_KEY" 2>/dev/null)
check_response "$response" "Indices deletion"
echo

# Delete index template
echo "🗑️  Deleting index template..."
response=$(curl -s -X DELETE "$ES_URL/_index_template/logs_standardizer_template" \
  -H "Authorization: ApiKey $API_KEY" 2>/dev/null)
check_response "$response" "Index template deletion"
echo

# Delete ingest pipeline
echo "🗑️  Deleting ingest pipeline..."
response=$(curl -s -X DELETE "$ES_URL/_ingest/pipeline/logs_standardizer" \
  -H "Authorization: ApiKey $API_KEY" 2>/dev/null)
check_response "$response" "Ingest pipeline deletion"
echo

# Clean up any index patterns that might exist
echo "🗑️  Deleting any legacy index patterns..."
response=$(curl -s -X DELETE "$ES_URL/_template/logs_standardizer*" \
  -H "Authorization: ApiKey $API_KEY" 2>/dev/null)
echo "Legacy template cleanup: $response"
echo

# Optional: Delete any data streams if they exist
echo "🗑️  Deleting any data streams..."
response=$(curl -s -X DELETE "$ES_URL/_data_stream/logs1-*" \
  -H "Authorization: ApiKey $API_KEY" 2>/dev/null)
echo "Data stream cleanup: $response"
echo

# Verify cleanup by listing what remains
echo "🔍 Verifying cleanup - checking for remaining objects..."
echo

echo "📋 Remaining index templates:"
curl -s -X GET "$ES_URL/_index_template/logs*" \
  -H "Authorization: ApiKey $API_KEY" | jq '.index_templates[] | .name' 2>/dev/null || echo "None found"
echo

echo "📋 Remaining ingest pipelines:"
curl -s -X GET "$ES_URL/_ingest/pipeline/logs*" \
  -H "Authorization: ApiKey $API_KEY" | jq 'keys[]' 2>/dev/null || echo "None found"
echo

echo "📋 Remaining indices:"
curl -s -X GET "$ES_URL/_cat/indices/logs1-*?v" \
  -H "Authorization: ApiKey $API_KEY" 2>/dev/null || echo "None found"
echo

echo "🎉 Cleanup complete!"
echo "💡 You can now run ./setup_elasticsearch.sh to recreate everything fresh."

