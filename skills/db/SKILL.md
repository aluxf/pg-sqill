---
name: db
description: PostgreSQL database helper. Use when writing SQL queries, exploring schema, or working with the database.
allowed-tools: Bash, Read
---

## Database Schema

```
!cat .claude/skills/db/schema.sql 2>/dev/null || echo "Schema not found. Run: pg-sqill sync"
```

## Quick Reference

- **Query**: `psql $DATABASE_URL -c "SELECT ..."`
- **Tables with uppercase**: Use quotes, e.g., `"Member"`, `"Task"`
- **Interactive**: `psql $DATABASE_URL` then `\dt` (tables), `\d tablename` (describe)

## Tips

- Always check column names with `\d tablename` before writing queries
- Use `LIMIT 5` when exploring data
- Join tables using foreign key relationships shown in schema
