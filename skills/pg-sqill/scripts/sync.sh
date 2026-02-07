#!/bin/bash
# pg-sqill sync script
# Syncs PostgreSQL schema directly into SKILL.md

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="$SCRIPT_DIR/../SKILL.md"

# Find DATABASE_URL and track which file it came from
ENV_FILE=""
if [ -z "$DATABASE_URL" ]; then
  for envfile in .env.local .env .env.development; do
    if [ -f "$envfile" ]; then
      url=$(grep -E '^DATABASE_URL=' "$envfile" | sed 's/^DATABASE_URL=//' | tr -d '"'"'" 2>/dev/null)
      if [ -n "$url" ]; then
        DATABASE_URL="$url"
        ENV_FILE="$envfile"
        break
      fi
    fi
  done
else
  ENV_FILE="environment"
fi

if [ -z "$DATABASE_URL" ]; then
  echo "Error: DATABASE_URL not found"
  echo "Set it in your environment or .env file"
  exit 1
fi

echo "pg-sqill: Syncing database schema..."

# Create query helper script (with absolute path to env file)
QUERY_SCRIPT="$SCRIPT_DIR/query.sh"
PROJECT_ROOT="$(pwd)"
# Get path relative to project root for SKILL.md
QUERY_PATH="${SCRIPT_DIR#$PROJECT_ROOT/}/query.sh"
cat > "$QUERY_SCRIPT" << QUERYEOF
#!/bin/bash
source "$PROJECT_ROOT/$ENV_FILE" 2>/dev/null
psql "\$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SET default_transaction_read_only = on; \$1"
QUERYEOF
chmod +x "$QUERY_SCRIPT"

# Test connection first
echo "Connecting to database..."
if ! psql "$DATABASE_URL" -c "SELECT 1" >/dev/null 2>&1; then
  echo "Error: Failed to connect to database"
  echo "Check your DATABASE_URL credentials"
  exit 1
fi

# Generate CREATE TABLE statements
echo "Introspecting schema..."

SQL_QUERY="
WITH
tables AS (
  SELECT c.oid, c.relname as table_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r'
  ORDER BY c.relname
),
columns AS (
  SELECT t.table_name, a.attnum, a.attname as column_name,
    pg_catalog.format_type(a.atttypid, a.atttypmod) as data_type,
    a.attnotnull as not_null, COALESCE(pg_get_expr(d.adbin, d.adrelid), '') as default_value
  FROM tables t
  JOIN pg_attribute a ON a.attrelid = t.oid
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE a.attnum > 0 AND NOT a.attisdropped
),
pk_cols AS (
  SELECT t.table_name, a.attname as column_name, array_length(i.indkey, 1) as pk_col_count
  FROM tables t
  JOIN pg_index i ON i.indrelid = t.oid AND i.indisprimary
  JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(i.indkey)
),
fk_info AS (
  SELECT t.table_name, a.attname as column_name, ref_t.relname as ref_table, ref_a.attname as ref_column,
    CASE c.confdeltype WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' WHEN 'r' THEN 'RESTRICT' ELSE '' END as on_delete
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
SELECT c.table_name, c.column_name, c.data_type, c.not_null, c.default_value,
  CASE WHEN pk.column_name IS NOT NULL AND pk.pk_col_count = 1 THEN 't' ELSE 'f' END,
  COALESCE(fk.ref_table, ''), COALESCE(fk.ref_column, ''), COALESCE(fk.on_delete, ''),
  CASE WHEN u.column_name IS NOT NULL THEN 't' ELSE 'f' END
FROM columns c
LEFT JOIN pk_cols pk ON pk.table_name = c.table_name AND pk.column_name = c.column_name
LEFT JOIN fk_info fk ON fk.table_name = c.table_name AND fk.column_name = c.column_name
LEFT JOIN unique_cols u ON u.table_name = c.table_name AND u.column_name = c.column_name
ORDER BY c.table_name, c.attnum
"

SCHEMA_SQL=$(psql "$DATABASE_URL" -t -A -F'|' -c "$SQL_QUERY" | awk -F'|' '
BEGIN { current_table = "" }
{
  table = $1; col = $2; dtype = $3; not_null = $4; defval = $5
  is_pk = $6; ref_table = $7; ref_col = $8; on_delete = $9; is_unique = $10

  if (table == "") next

  # Quote table name if has uppercase
  tname = table
  if (match(table, /[A-Z]/)) tname = "\"" table "\""

  # Quote column name if has uppercase
  cname = col
  if (match(col, /[A-Z]/)) cname = "\"" col "\""

  # Start new table
  if (table != current_table) {
    if (current_table != "") print ");\n"
    print "CREATE TABLE " tname " ("
    current_table = table
    first_col = 1
  }

  # Column definition
  if (!first_col) print ","
  first_col = 0

  printf "    %s %s", cname, dtype

  if (is_pk == "t") printf " PRIMARY KEY"
  if (is_unique == "t" && is_pk != "t") printf " UNIQUE"
  if (not_null == "t" && is_pk != "t") printf " NOT NULL"

  # Simplify defaults
  if (defval != "") {
    d = defval
    if (index(d, "gen_random_uuid") > 0) d = "gen_random_uuid()"
    else if (tolower(d) ~ /now\(\)/ || tolower(d) ~ /current_timestamp/) d = "now()"
    else if (index(d, "::") > 0 && dtype ~ /character/) {
      split(d, parts, "::")
      d = parts[1]
    }
    printf " DEFAULT %s", d
  }

  # Foreign key
  if (ref_table != "") {
    rt = ref_table
    if (match(ref_table, /[A-Z]/)) rt = "\"" ref_table "\""
    printf " REFERENCES %s(%s)", rt, ref_col
    if (on_delete != "") printf " ON DELETE %s", on_delete
  }
}
END { if (current_table != "") print "\n);" }
')

if [ -z "$SCHEMA_SQL" ]; then
  echo "Error: No tables found in public schema"
  exit 1
fi

# Write SKILL.md
cat > "$SKILL_FILE" << SKILLEOF
---
name: pg-sqill
description: PostgreSQL database helper. Use when writing SQL queries, exploring schema, or working with the database.
allowed-tools: Bash, Read
---

## Database

The application uses PostgreSQL. Connection string is in \`DATABASE_URL\` environment variable.

To query the database:
\`\`\`bash
$QUERY_PATH "SELECT * FROM table LIMIT 5"
\`\`\`

Note: Table names with uppercase letters require double quotes (e.g., \`"Member"\`, \`"Task"\`).

### Schema

\`\`\`sql
$SCHEMA_SQL
\`\`\`

## Tips

- Use \`LIMIT 5\` when exploring data
- Check column names before writing queries
- Join tables using foreign key relationships shown in schema

## Sync

Re-run \`sync.sh\` after schema changes.
SKILLEOF

echo "Schema written to $SKILL_FILE"
echo ""
echo "Done! The /pg-sqill skill is now available."
