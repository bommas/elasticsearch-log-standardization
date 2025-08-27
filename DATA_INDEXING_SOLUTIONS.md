# 🚨 Elasticsearch Data Indexing Errors & Solutions

## 📊 **Current Status**
- **Total Records**: 1,000
- **Successfully Indexed**: 580 (58%)
- **Failed**: 420 (42%)

## 🔍 **Root Cause Analysis**

### Primary Issue: **Field Type Conflicts**
Your raw log data contains **inconsistent field structures** that violate Elasticsearch's strict mapping requirements:

#### **Type 1: Object-based `msg` field**
```json
{
  "msg": {
    "@i": "300035a8",
    "@m": "Saving Masthead Footer Data...",
    "Lwp": {"Country": "us", "Language": "en"},
    "ChangeEventKey": {"Identifier": "abc123", "Language": "en"}
  }
}
```

#### **Type 2: String-based `msg` field**
```json
{
  "msg": "Received Trace-id 00000000-0000-0000-0000-000000000000..."
}
```

### **Specific Field Conflicts**
1. **`msg.ChangeEventKey`**: Sometimes object `{Identifier=..., Language=...}`, sometimes string
2. **`msg.Lwp`**: Sometimes object `{Country=..., Language=...}`, sometimes string  
3. **`msg.Partition`**: Sometimes object, sometimes string like `"[4]"`
4. **`msg.offset`**: Sometimes object, sometimes primitive
5. **`msg`**: Sometimes complete object, sometimes string

## 💡 **Solution Strategies**

### **🎯 Solution 1: Data Preprocessing (Recommended)**

Create a preprocessing script that normalizes data structure before indexing:

```bash
# Create preprocessing script
cat > preprocess_logs.py << 'EOF'
import json
import sys

def normalize_record(record):
    """Normalize inconsistent field structures"""
    
    # Handle msg field conflicts
    if 'msg' in record:
        msg = record['msg']
        
        # If msg is a string, wrap in object
        if isinstance(msg, str):
            record['msg'] = {
                '@m': msg,
                'original_string': True
            }
        
        # Handle nested field conflicts
        elif isinstance(msg, dict):
            # Normalize ChangeEventKey
            if 'ChangeEventKey' in msg:
                if not isinstance(msg['ChangeEventKey'], dict):
                    msg['ChangeEventKey'] = {'value': str(msg['ChangeEventKey'])}
            
            # Normalize Lwp
            if 'Lwp' in msg:
                if not isinstance(msg['Lwp'], dict):
                    msg['Lwp'] = {'value': str(msg['Lwp'])}
            
            # Normalize Partition
            if 'Partition' in msg:
                if isinstance(msg['Partition'], list):
                    msg['Partition'] = msg['Partition'][0] if msg['Partition'] else 0
                elif isinstance(msg['Partition'], str):
                    msg['Partition'] = msg['Partition'].strip('[]')
    
    return record

# Process file
with open('raw_events_randomized_all.txt', 'r') as infile:
    with open('normalized_events.txt', 'w') as outfile:
        for line in infile:
            try:
                record = json.loads(line.strip())
                normalized = normalize_record(record)
                outfile.write(json.dumps(normalized) + '\n')
            except Exception as e:
                print(f"Error processing line: {e}")
                continue
EOF

python3 preprocess_logs.py
```

### **🎯 Solution 2: Split by Data Type**

Separate different log types into different indices:

```bash
# Create type-specific scripts
cat > split_by_type.py << 'EOF'
import json

string_msgs = []
object_msgs = []

with open('raw_events_randomized_all.txt', 'r') as f:
    for line in f:
        try:
            record = json.loads(line.strip())
            if isinstance(record.get('msg'), str):
                string_msgs.append(record)
            else:
                object_msgs.append(record)
        except:
            continue

# Write to separate files
with open('string_msg_logs.txt', 'w') as f:
    for record in string_msgs:
        f.write(json.dumps(record) + '\n')

with open('object_msg_logs.txt', 'w') as f:
    for record in object_msgs:
        f.write(json.dumps(record) + '\n')

print(f"String messages: {len(string_msgs)}")
print(f"Object messages: {len(object_msgs)}")
EOF

python3 split_by_type.py
```

### **🎯 Solution 3: Ignore Malformed Documents**

Modify the index template to be more permissive:

```json
{
  "index_patterns": ["logs1-*"],
  "template": {
    "settings": {
      "index.mapping.ignore_malformed": true,
      "index.mapping.coerce": true,
      "index.default_pipeline": "logs_standardizer"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "@timestamp": {"type": "date"},
        "msg": {"enabled": false}
      }
    }
  }
}
```

### **🎯 Solution 4: Pipeline-Based Normalization**

Enhanced ingest pipeline that handles conflicts:

```json
{
  "processors": [
    {
      "script": {
        "description": "Normalize msg field structure",
        "source": "if (ctx.msg instanceof String) { ctx.msg_text = ctx.msg; ctx.remove('msg'); } else if (ctx.msg instanceof Map) { if (ctx.msg.containsKey('ChangeEventKey') && !(ctx.msg.ChangeEventKey instanceof Map)) { ctx.msg.ChangeEventKey = ['value': ctx.msg.ChangeEventKey.toString()]; } }"
      }
    }
  ]
}
```

### **🎯 Solution 5: Force Dynamic Mapping**

Create an index template that treats everything as text initially:

```json
{
  "index_patterns": ["logs1-*"],
  "template": {
    "mappings": {
      "dynamic_templates": [
        {
          "everything_as_text": {
            "match": "*",
            "mapping": {
              "type": "text",
              "fields": {
                "keyword": {"type": "keyword", "ignore_above": 1024}
              }
            }
          }
        }
      ]
    }
  }
}
```

## 🚀 **Immediate Action Plan**

### **Step 1: Quick Fix (5 minutes)**
```bash
# Use ignore_malformed setting
./cleanup_elasticsearch.sh

# Update index template with ignore_malformed
cat > index_template_permissive.json << 'EOF'
{
  "index_patterns": ["logs1-*"],
  "template": {
    "settings": {
      "index.mapping.ignore_malformed": true,
      "index.mapping.coerce": true,
      "index.default_pipeline": "logs_standardizer"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "@timestamp": {"type": "date"},
        "ErrorType_RAW": {"type": "text"},
        "ErrorType": {"type": "keyword"},
        "MCMID": {"type": "keyword"},
        "country": {"type": "keyword"},
        "language": {"type": "keyword"},
        "ClientIP": {"type": "keyword"},
        "log_level": {"type": "keyword"},
        "Panel_PCF_App": {"type": "keyword"}
      }
    }
  }
}
EOF

# Replace current template
cp index_template_permissive.json index_template.json
./setup_elasticsearch.sh
./bulk_load.sh
```

### **Step 2: Data Preprocessing (15 minutes)**
```bash
# Run the preprocessing script above
python3 preprocess_logs.py

# Use normalized data
mv normalized_events.txt raw_events_normalized.txt

# Update bulk_load.sh to use normalized file
sed -i '' 's/raw_events_randomized_all.txt/raw_events_normalized.txt/' bulk_load.sh

./cleanup_elasticsearch.sh
./setup_elasticsearch.sh
./bulk_load.sh
```

### **Step 3: Type-Based Indexing (20 minutes)**
```bash
# Split data by type
python3 split_by_type.py

# Create separate indices for each type
# Index 1: String messages (logs1-string)
# Index 2: Object messages (logs1-object)
```

## 📈 **Expected Results**

| Solution | Expected Success Rate | Effort | Data Quality |
|----------|----------------------|---------|--------------|
| Ignore Malformed | 85-95% | Low | Medium |
| Preprocessing | 95-99% | Medium | High |
| Type Splitting | 99%+ | High | High |

## 🔧 **Tools Created**

Your directory now contains:
- `✅ index_template.json` - Ultra-flexible template
- `✅ ingest_pipeline.json` - Robust extraction pipeline  
- `✅ setup_elasticsearch.sh` - Automated setup
- `✅ cleanup_elasticsearch.sh` - Complete cleanup
- `✅ bulk_load.sh` - Enhanced bulk loading
- `✅ raw_events_randomized_all.txt` - Original data

## 🎯 **Recommendation**

**Start with Solution 1 (Quick Fix)** - it will likely get you to 85-95% success rate with minimal effort. If you need higher success rates, proceed to Solution 2 (Preprocessing).

