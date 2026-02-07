# pg-sqill

PostgreSQL skill for AI coding agents. Syncs your database schema so Claude/Cursor/Copilot can write correct queries.

## Install

```bash
npx skills add aluxf/pg-sqill
```

Or manually copy `skills/pg-sqill/` to `.claude/skills/pg-sqill/`.

## Sync Schema

```bash
# Set your database connection (or use .env file)
export DATABASE_URL="postgres://user:pass@localhost:5432/mydb"

# Sync
bash .claude/skills/pg-sqill/scripts/sync.sh
```

This embeds your schema directly into `SKILL.md` as CREATE TABLE statements.

## Usage

After syncing, your agent loads the schema when you ask database questions:

```
You: "Write a query to get all users with their orders"
Agent: [uses schema, writes correct query with proper table/column names]
```

## Re-sync

Run after schema changes (migrations, new tables):

```bash
bash .claude/skills/pg-sqill/scripts/sync.sh
```

Add to post-migration hook:
```json
{
  "scripts": {
    "migrate": "prisma migrate dev && bash .claude/skills/pg-sqill/scripts/sync.sh"
  }
}
```

## Requirements

- `psql` CLI (comes with PostgreSQL)
- `DATABASE_URL` environment variable or `.env` file
- Python 3 (for schema formatting)

## Supported Agents

Works with any agent supporting [AgentSkills.io](https://agentskills.io):
- Claude Code
- Cursor
- GitHub Copilot
- Windsurf
- [20+ more](https://skills.sh)

## License

MIT
