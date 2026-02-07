#!/bin/bash
# pg-sqill sync script - syncs PostgreSQL schema to SKILL.md

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="$SCRIPT_DIR/../SKILL.md"

# Find DATABASE_URL
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
  exit 1
fi

echo "pg-sqill: Syncing schema..."

# Create query helper
PROJECT_ROOT="$(pwd)"
QUERY_PATH="${SCRIPT_DIR#$PROJECT_ROOT/}/query.sh"
cat > "$SCRIPT_DIR/query.sh" << EOF
#!/bin/bash
source "$PROJECT_ROOT/$ENV_FILE" 2>/dev/null
psql "\$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SET default_transaction_read_only = on; \$1"
EOF
chmod +x "$SCRIPT_DIR/query.sh"

# Test connection
if ! psql "$DATABASE_URL" -c "SELECT 1" >/dev/null 2>&1; then
  echo "Error: Failed to connect"
  exit 1
fi

# Dump schema - only CREATE TABLE statements
SCHEMA=$(pg_dump "$DATABASE_URL" --schema-only --no-owner --no-privileges --no-comments --schema=public 2>/dev/null | sed -n '/^CREATE TABLE/,/^);/p')

if [ -z "$SCHEMA" ]; then
  echo "Error: No tables found"
  exit 1
fi

# Write SKILL.md
cat > "$SKILL_FILE" << SKILLEOF
---
name: pg-sqill
description: PostgreSQL database helper. Use when writing SQL queries or working with the database.
allowed-tools: Bash, Read
---

## Database

To query: \`$QUERY_PATH "SELECT * FROM table LIMIT 5"\`

Note: Uppercase table names need quotes (e.g., \`"User"\`, \`"Chat"\`).

### Schema

\`\`\`sql
$SCHEMA
\`\`\`
SKILLEOF

echo "Done! /pg-sqill skill ready."
