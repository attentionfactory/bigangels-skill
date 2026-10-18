# BigAngels skill

Instant hosting for static artifacts: sites, demos, reports (HTML/PDF), and export folders (CSV, JSON, images). Tell your agent **"Publish this to BigAngels"** and get a live link in seconds — no DNS or deploy setup.

## Install

```bash
npx skills add attentionfactory/bigangels-skill --skill bigangels -g
```

Without npm:

```bash
curl -fsSL https://bigangels.app/install.sh | bash
```

Windows (PowerShell):

```powershell
irm https://bigangels.app/install.ps1 | iex
```

Then tell your agent: **"Publish this to BigAngels"**. Your site is public immediately, without signing in. Anonymous previews expire in six hours; sign in with `login.sh --email` when you want to keep them.

To test anonymous publishing while signed in, run `publish.sh <path> --anonymous`. It ignores saved and environment credentials and remembers anonymous previews separately from account-owned sites. `login.sh --logout` removes the shared local sign-in without uninstalling the skill.

**MCP (OAuth)** is separate: add `https://api.bigangels.app/mcp` in Cursor Settings → MCP or your client's Connectors UI. `install.sh` does not configure MCP.

## What's inside

- `skills/bigangels/SKILL.md` — what the agent reads: artifact types, publish workflow, sign-in, troubleshooting.
- `skills/bigangels/scripts/publish.sh` — publishes a file or folder, remembers which folder maps to which site, and only uploads files that changed.
- `skills/bigangels/scripts/login.sh` — email-code sign-in in chat by default (`--email`); optional `--browser` sign-in.
- `skills/bigangels/scripts/drive.sh` — keeps private files (notes, memory, plans, assets) in a BigAngels Drive: `ls`, `put`, `cat`, `import`, `export`, `share`, `publish`.

Docs: https://bigangels.app/docs

## Monorepo vs GitHub

Production install pulls **`attentionfactory/bigangels-skill`** on GitHub (`main`). This monorepo copy lives under `packages/skill/` — sync or tag releases there so `install.sh` and `npx skills add` match.

## License

MIT
