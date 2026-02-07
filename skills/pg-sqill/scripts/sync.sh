#!/bin/bash
# pg-sqill sync script
# Syncs PostgreSQL schema directly into SKILL.md

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="$SCRIPT_DIR/../SKILL.md"

# Find DATABASE_URL
if [ -z "$DATABASE_URL" ]; then
  for envfile in .env .env.local .env.development; do
    if [ -f "$envfile" ]; then
      url=$(grep -E '^DATABASE_URL=' "$envfile" | sed 's/^DATABASE_URL=//' | tr -d '"'"'" 2>/dev/null)
      if [ -n "$url" ]; then
        DATABASE_URL="$url"
        break
      fi
    fi
  done
fi

if [ -z "$DATABASE_URL" ]; then
  echo "Error: DATABASE_URL not found"
  echo "Set it in your environment or .env file"
  exit 1
fi

echo "pg-sqill: Syncing database schema..."

# Test connection first
echo "Connecting to database..."
if ! psql "$DATABASE_URL" -c "SELECT 1" >/dev/null 2>&1; then
  echo "Error: Failed to connect to database"
  echo "Check your DATABASE_URL credentials"
  exit 1
fi

# Generate CREATE TABLE statements
echo "Introspecting schema..."

SCHEMA=$(psql "$DATABASE_URL" -t -A -F'|' <<'QUERY'
WITH
tables AS (
  SELECT c.oid, c.relname as table_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r'
  ORDER BY c.relname
),
columns AS (
  SELECT
    t.table_name,
    a.attnum,
    a.attname as column_name,
    pg_catalog.format_type(a.atttypid, a.atttypmod) as data_type,
    a.attnotnull as not_null,
    pg_get_expr(d.adbin, d.adrelid) as default_value
  FROM tables t
  JOIN pg_attribute a ON a.attrelid = t.oid
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE a.attnum > 0 AND NOT a.attisdropped
),
pk_cols AS (
  SELECT t.table_name, a.attname as column_name,
         array_length(i.indkey, 1) as pk_col_count
  FROM tables t
  JOIN pg_index i ON i.indrelid = t.oid AND i.indisprimary
  JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(i.indkey)
),
fk_info AS (
  SELECT
    t.table_name,
    a.attname as column_name,
    ref_t.relname as ref_table,
    ref_a.attname as ref_column,
    CASE c.confdeltype
      WHEN 'c' THEN 'CASCADE'
      WHEN 'n' THEN 'SET NULL'
      WHEN 'd' THEN 'SET DEFAULT'
      WHEN 'r' THEN 'RESTRICT'
      ELSE NULL
    END as on_delete
  FROM tables t
  JOIN pg_constraint c ON c.conrelid = t.oid AND c.contype = 'f'
  JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = c.conkey[1]
  JOIN pg_class ref_t ON ref_t.oid = c.confrelid
  JOIN pg_attribute ref_a ON ref_a.attrelid = c.confrelid AND ref_a.attnum = c.confkey[1]
),
unique_cols AS (
  SELECT DISTINCT t.table_name, a.attname as column_name
  FROM tables t
  JOIN pg_index i ON i.indrelid = t.oid AND i.indisunique AND NOT i.indisprimary
  JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(i.indkey)
  WHERE array_length(i.indkey, 1) = 1
)
SELECT
  c.table_name,
  c.column_name,
  c.data_type,
  c.not_null,
  c.default_value,
  CASE WHEN pk.column_name IS NOT NULL AND pk.pk_col_count = 1 THEN true ELSE false END as is_pk,
  fk.ref_table,
  fk.ref_column,
  fk.on_delete,
  CASE WHEN u.column_name IS NOT NULL THEN true ELSE false END as is_unique
FROM columns c
LEFT JOIN pk_cols pk ON pk.table_name = c.table_name AND pk.column_name = c.column_name
LEFT JOIN fk_info fk ON fk.table_name = c.table_name AND fk.column_name = c.column_name
LEFT JOIN unique_cols u ON u.table_name = c.table_name AND u.column_name = c.column_name
ORDER BY c.table_name, c.attnum;
QUERY
)

if [ -z "$SCHEMA" ]; then
  echo "Error: No tables found in public schema"
  exit 1
fi

# Convert raw output to CREATE TABLE format and write SKILL.md
python3 - "$SKILL_FILE" "$SCHEMA" <<'PYTHON'
import sys

skill_file = sys.argv[1]
raw_data = sys.argv[2]
tables = {}

for line in raw_data.strip().split('\n'):
    line = line.strip()
    if not line:
        continue
    parts = line.split('|')
    if len(parts) < 10:
        continue

    table, col, dtype, not_null, default, is_pk, ref_table, ref_col, on_delete, is_unique = parts

    if table not in tables:
        tables[table] = []

    tables[table].append({
        'name': col,
        'type': dtype,
        'not_null': not_null == 't',
        'default': default if default else None,
        'is_pk': is_pk == 't',
        'ref_table': ref_table if ref_table else None,
        'ref_col': ref_col if ref_col else None,
        'on_delete': on_delete if on_delete else None,
        'is_unique': is_unique == 't'
    })

# Generate CREATE TABLE statements
schema_lines = []
for table in sorted(tables.keys()):
    cols = tables[table]
    needs_quotes = table[0].isupper() or any(c.isupper() for c in table)
    tname = f'"{table}"' if needs_quotes else table

    lines = [f"CREATE TABLE {tname} ("]
    col_defs = []

    for c in cols:
        cname = c['name']
        if cname[0].isupper() or any(ch.isupper() for ch in cname):
            cname = f'"{cname}"'

        parts = [f"    {cname}", c['type']]

        if c['is_pk']:
            parts.append("PRIMARY KEY")

        if c['is_unique'] and not c['is_pk']:
            parts.append("UNIQUE")

        if c['not_null'] and not c['is_pk']:
            parts.append("NOT NULL")

        if c['default']:
            d = c['default']
            if 'gen_random_uuid' in d:
                d = 'gen_random_uuid()'
            elif 'now()' in d.lower() or 'current_timestamp' in d.lower():
                d = 'now()'
            elif '::' in d and 'character' in c['type']:
                d = d.split('::')[0]
            parts.append(f"DEFAULT {d}")

        if c['ref_table']:
            ref_t = c['ref_table']
            if ref_t[0].isupper() or any(ch.isupper() for ch in ref_t):
                ref_t = f'"{ref_t}"'
            ref = f"REFERENCES {ref_t}({c['ref_col']})"
            if c['on_delete']:
                ref += f" ON DELETE {c['on_delete']}"
            parts.append(ref)

        col_defs.append(" ".join(parts))

    lines.append(",\n".join(col_defs))
    lines.append(");")
    schema_lines.append("\n".join(lines))

schema_sql = "\n\n".join(schema_lines)

# Write SKILL.md with embedded schema
skill_content = f'''---
name: pg-sqill
description: PostgreSQL database helper. Use when writing SQL queries, exploring schema, or working with the database.
allowed-tools: Bash, Read
---

## Database

The application uses PostgreSQL. Connection string is in `DATABASE_URL` environment variable.

To query the database directly:
```bash
export $(cat .env | xargs) && psql $DATABASE_URL -c "YOUR SQL"
```

Note: Table names with uppercase letters require double quotes (e.g., `"Member"`, `"Task"`).

### Schema

```sql
{schema_sql}
```

## Tips

- Use `LIMIT 5` when exploring data
- Check column names before writing queries
- Join tables using foreign key relationships shown in schema

## Sync

Re-run `sync.sh` after schema changes.
'''

with open(skill_file, 'w') as f:
    f.write(skill_content)
PYTHON

echo "Schema written to $SKILL_FILE"
echo ""
echo "Done! The /pg-sqill skill is now available."
