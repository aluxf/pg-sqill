#!/usr/bin/env node

import { execSync } from "node:child_process";
import { writeFileSync, mkdirSync, existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const SKILL_DIR = ".claude/skills/db";
const SCHEMA_FILE = join(SKILL_DIR, "schema.sql");
const SKILL_FILE = join(SKILL_DIR, "SKILL.md");

function getConnectionString() {
  // Try DATABASE_URL from environment
  if (process.env.DATABASE_URL) {
    return process.env.DATABASE_URL;
  }

  // Try to load from .env file
  const envFiles = [".env", ".env.local", ".env.development"];
  for (const envFile of envFiles) {
    if (existsSync(envFile)) {
      const content = readFileSync(envFile, "utf-8");
      const match = content.match(/DATABASE_URL=["']?([^"'\n]+)["']?/);
      if (match) {
        return match[1];
      }
    }
  }

  return null;
}

function introspectSchema(connectionString) {
  try {
    // Get list of tables in public schema
    const tablesResult = execSync(
      `psql "${connectionString}" -t -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename"`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }
    );
    const tables = tablesResult.trim().split("\n").map(t => t.trim()).filter(Boolean);

    if (tables.length === 0) {
      return "No tables found in public schema.";
    }

    // Get table list
    let output = execSync(
      `psql "${connectionString}" -c "\\dt public.*"`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }
    );

    // Describe each table individually
    for (const table of tables) {
      const desc = execSync(
        `psql "${connectionString}" -c "\\d \\"${table}\\""`,
        { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }
      );
      output += "\n" + desc;
    }

    return output;
  } catch (error) {
    if (error.stderr) {
      console.error("psql error:", error.stderr);
    }
    throw new Error("Failed to introspect database. Is psql installed and DATABASE_URL correct?");
  }
}

function writeSkillFile() {
  const skillContent = `---
name: db
description: PostgreSQL database helper. Use when writing SQL queries, exploring schema, or working with the database.
allowed-tools: Bash, Read
---

## Database Schema

\`\`\`
!cat ${SCHEMA_FILE} 2>/dev/null || echo "Schema not found. Run: pg-sqill sync"
\`\`\`

## Quick Reference

- **Query**: \`psql $DATABASE_URL -c "SELECT ..."\`
- **Tables with uppercase**: Use quotes, e.g., \`"Member"\`, \`"Task"\`
- **Interactive**: \`psql $DATABASE_URL\` then \`\\dt\` (tables), \`\\d tablename\` (describe)

## Tips

- Always check column names with \`\\d tablename\` before writing queries
- Use \`LIMIT 5\` when exploring data
- Join tables using foreign key relationships shown in schema
`;

  writeFileSync(SKILL_FILE, skillContent);
}

function main() {
  const command = process.argv[2];

  if (command === "sync" || !command) {
    console.log("pg-sqill: Syncing database schema...\n");

    const connectionString = getConnectionString();
    if (!connectionString) {
      console.error("Error: DATABASE_URL not found.");
      console.error("Set it in your environment or .env file.");
      process.exit(1);
    }

    // Create skill directory
    mkdirSync(SKILL_DIR, { recursive: true });

    // Introspect and save schema
    console.log("Introspecting database...");
    const schema = introspectSchema(connectionString);
    writeFileSync(SCHEMA_FILE, schema);
    console.log(`Schema written to ${SCHEMA_FILE}`);

    // Write skill file
    writeSkillFile();
    console.log(`Skill written to ${SKILL_FILE}`);

    console.log("\nDone! The /db skill is now available in Claude Code.");
    console.log("Re-run 'pg-sqill sync' after schema changes.");

  } else if (command === "help" || command === "--help" || command === "-h") {
    console.log(`
pg-sqill - PostgreSQL skill for Claude Code

Usage:
  pg-sqill sync     Sync database schema to Claude skill
  pg-sqill help     Show this help

Environment:
  DATABASE_URL      PostgreSQL connection string (or set in .env)

The sync command:
  1. Introspects your PostgreSQL database
  2. Creates .claude/skills/db/ with schema and instructions
  3. Enables the /db skill in Claude Code

After syncing, Claude can help you write queries with full schema context.
`);
  } else {
    console.error(`Unknown command: ${command}`);
    console.error("Run 'pg-sqill help' for usage.");
    process.exit(1);
  }
}

main();
