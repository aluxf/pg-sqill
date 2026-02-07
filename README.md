# pg-sqill

PostgreSQL skill for Claude Code. Syncs your database schema and provides psql instructions so Claude can help you write queries.

## Install

```bash
npm install -g pg-sqill
```

## Usage

```bash
# Set your database connection
export DATABASE_URL="postgres://user:pass@localhost:5432/mydb"

# Sync schema to Claude skill
pg-sqill sync
```

This creates `.claude/skills/db/` with:
- `schema.sql` - Your database schema
- `SKILL.md` - Instructions for Claude

## In Claude Code

After syncing, Claude automatically uses the `/db` skill when you ask database questions:

```
You: "Write a query to get all users with their orders"
Claude: [loads schema, writes correct query with proper table/column names]
```

Or invoke manually:
```
/db
```

## Re-sync

Run `pg-sqill sync` again after schema changes (migrations, new tables, etc.).

**Tip**: Add to your post-migration script:
```json
{
  "scripts": {
    "migrate": "prisma migrate dev && pg-sqill sync"
  }
}
```

## How it works

1. `pg-sqill sync` runs `psql \dt` and `\d *` to introspect your schema
2. Saves output to `.claude/skills/db/schema.sql`
3. Creates skill file with psql instructions
4. Claude loads schema on-demand when you ask DB questions

## Requirements

- Node.js 18+
- `psql` CLI (comes with PostgreSQL)
- `DATABASE_URL` environment variable

## License

MIT
