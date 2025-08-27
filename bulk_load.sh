#!/bin/bash

# === CONFIGURATION ===
API_KEY="SkVRaW5KZ0JRSy1YVXFsbEhrS206YTRjZ0lmMU5UTzF5b09vVW12SzBYQQ=="
ES_URL="https://dellollypoc.es.us-east-1.aws.found.io"
INDEX="logs1-raw"
PIPELINE="logs_standardizer"
INPUT_FILE="raw_events_randomized_all.txt"
BULK_FILE="bulk.json"

# Cleanup function to remove temporary files
cleanup() {
    echo "🧹 Cleaning up temporary files..."
    if [ -f "$BULK_FILE" ]; then
        rm -f "$BULK_FILE"
        echo "✅ Removed $BULK_FILE"
    fi
}

# Function to check if command was successful
check_status() {
    if [ $? -eq 0 ]; then
        echo "✅ $1 successful"
    else
        echo "❌ $1 failed"
        cleanup
        exit 1
    fi
}

# Function to check bulk response for errors
check_bulk_response() {
    local response="$1"
    
    # Check if response contains errors
    if echo "$response" | grep -q '"errors":true'; then
        echo "❌ Bulk upload had errors:"
        echo "$response" | jq '.items[] | select(.index.error) | .index.error' 2>/dev/null || echo "$response"
        cleanup
        exit 1
    elif echo "$response" | grep -q '"errors":false'; then
        local took=$(echo "$response" | jq -r '.took' 2>/dev/null || echo "unknown")
        local count=$(echo "$response" | jq -r '.items | length' 2>/dev/null || echo "unknown")
        echo "✅ Bulk upload successful: $count documents indexed in ${took}ms"
    else
        echo "⚠️  Bulk upload completed (status unclear)"
        echo "Response: $response"
    fi
}

# Set trap to cleanup on script exit
trap cleanup EXIT

echo "🚀 Starting bulk load process..."
echo "📁 Input file: $INPUT_FILE"
echo "🎯 Target index: $INDEX"
echo "⚙️  Pipeline: $PIPELINE"
echo

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ Input file $INPUT_FILE not found!"
    exit 1
fi

# Check file size
file_size=$(wc -l < "$INPUT_FILE")
echo "📊 Processing $file_size lines from $INPUT_FILE"

# Remove existing bulk file if it exists
if [ -f "$BULK_FILE" ]; then
    echo "🗑️  Removing existing $BULK_FILE"
    rm -f "$BULK_FILE"
fi

# Convert raw file (one JSON object per line) into _bulk format
echo "🔄 Converting to bulk format..."
awk '{print "{\"index\":{}}"; print $0}' "$INPUT_FILE" > "$BULK_FILE"
check_status "Bulk format conversion"

# Check bulk file was created and has content
if [ ! -f "$BULK_FILE" ] || [ ! -s "$BULK_FILE" ]; then
    echo "❌ Failed to create bulk file or file is empty"
    exit 1
fi

bulk_lines=$(wc -l < "$BULK_FILE")
echo "✅ Created bulk file with $bulk_lines lines"

# Test connection to Elasticsearch
echo "🔍 Testing connection to Elasticsearch..."
connection_test=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: ApiKey $API_KEY" "$ES_URL")
if [ "$connection_test" != "200" ]; then
    echo "❌ Failed to connect to Elasticsearch (HTTP $connection_test)"
    exit 1
fi
echo "✅ Connection to Elasticsearch successful"

# POST bulk.json into Elastic with API key authentication
echo "📤 Uploading data to $ES_URL/$INDEX using pipeline $PIPELINE..."
response=$(curl -s -X POST "$ES_URL/$INDEX/_bulk?pipeline=$PIPELINE" \
  -H "Content-Type: application/x-ndjson" \
  -H "Authorization: ApiKey $API_KEY" \
  --data-binary "@$BULK_FILE")

check_bulk_response "$response"

echo
echo "🎉 Upload process complete!"
echo "💡 Check your Elasticsearch index '$INDEX' for the uploaded data."
