# pg-sqill

PostgreSQL skill for AI coding agents. Syncs your database schema so Claude/Cursor/Copilot can write correct queries.

## Install

```bash
npx skills add aluxf/pg-sqill
```

## Sync

```bash
bash <skill-path>/scripts/sync.sh
```

This:
- Embeds your schema as CREATE TABLE statements in `SKILL.md`
- Creates a `query.sh` helper for seamless database queries
- **Read-only by default** - query.sh blocks DELETE/UPDATE/DROP

## Usage

After syncing, your agent can query the database directly:

```bash
<skill-path>/scripts/query.sh "SELECT * FROM users LIMIT 5"
```

The skill auto-detects your env file (`.env.local`, `.env`, etc.) and configures the helper with the correct `DATABASE_URL`.

## Re-sync

Run after schema changes:

```bash
bash <skill-path>/scripts/sync.sh
```

Or add to your migration hook:
```json
{
  "scripts": {
    "migrate": "prisma migrate dev && bash <skill-path>/scripts/sync.sh"
  }
}
```

## Requirements

- `psql` CLI (comes with PostgreSQL)
- `DATABASE_URL` in environment or `.env` file
- Python 3

## Supported Agents

Works with any agent supporting [AgentSkills.io](https://agentskills.io):
- Claude Code
- Cursor
- GitHub Copilot
- Windsurf
- [20+ more](https://skills.sh)

## License

MIT
