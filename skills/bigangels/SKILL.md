---
name: bigangels
description: >
  BigAngels publishes websites and files to a live URL in seconds. Use when the
  user asks to "publish this", "put this online", "host this", "deploy this",
  "share this on the web", "make a website", "give me a link", or "publish to
  BigAngels". Works for HTML sites, built apps (dist/ folders), documents,
  images, PDFs, CSV/JSON exports, and any static files.
---

# BigAngels

Publish a file or folder and get a live URL like `https://bright-canvas-a7k2.<sites-domain>/`. No hosting setup, DNS, or deploy pipeline for the user — you upload static artifacts and return the link.

**Publishing requires sign-in — never skip it.** Do not call the BigAngels API with `curl` or invent credentials. Use the skill scripts only.

On a publish/deploy request: run `publish.sh` (it starts browser sign-in automatically when needed on the user's machine). If you check first, `login.sh --status` exits 0 only when signed in; otherwise run `login.sh` (browser) or guide the user through `login.sh --email` on SSH, then publish.

## Agent workflow (checklist)

1. **Install** (once per machine): `curl -fsSL https://bigangels.app/install.sh | bash` or `npx skills add attentionfactory/bigangels-skill --skill bigangels -g`
2. **Sign in once** when credentials are missing: `login.sh` (browser on a normal terminal) or `login.sh --email` on SSH/headless — then continue publish in the same flow.
3. **Publish**: `publish.sh <path>` → read the line `published: https://…` and give that URL to the user (clickable).
4. **Verify**: the script already HTTP-checks the URL after finalize; if it fails, fix `BIGANGELS_API` and publish again.

## Starter prompt (share with the user)

Copy this into a new agent chat after install:

```text
I use BigAngels for instant static hosting (sites, demos, reports, exports).

1) Install the skill if needed: curl -fsSL https://bigangels.app/install.sh | bash
2) When I say "publish this to BigAngels", run publish.sh on the file or folder (run login.sh if sign-in is required) and return the published: URL.

Do not skip sign-in. Do not use curl against the API without the skill scripts.
```

## What to publish (artifact types)

| Kind | What to pass | Example |
|------|----------------|---------|
| **Site** | Folder with `index.html` | `./publish.sh ./my-site` |
| **SPA / static build** | `dist/`, `out/`, or `build/` + `--spa` | `./publish.sh ./dist --spa --name "My app"` |
| **Demo** | Single HTML or small folder | `./publish.sh demo.html` or `./publish.sh ./demo` |
| **Report** | PDF or HTML file | `./publish.sh report.pdf` |
| **Exports** | Folder of CSV, JSON, images | `./publish.sh ./export-folder` |
| **Single file** | PDF, image, markdown, JSON, CSV | `./publish.sh chart.png` |

Single-file uploads get an edge **viewer** (PDF, markdown, tables, images, code). Folder sites serve files directly; one file in a folder opens in the viewer automatically.

**URLs after publish**

| Goal | URL pattern |
|------|-------------|
| Site home | `published:` URL (folder with `index.html`) |
| SPA deep link | Same + path, with `--spa` on publish |
| Report (PDF/HTML) | Root URL for a single file; or `/report.pdf` / `/report.html` |
| Export raw file | `{site}/path/data.json` — correct `Content-Type` for scripts and `fetch` |
| Export download | `{site}/path/file.csv?download=1` — `Content-Disposition: attachment` |
| Export preview | `{site}/path/file.csv?view` or open from the folder listing |

Static files send `Access-Control-Allow-Origin: *` so demos can `fetch` assets from other origins.

`.env` files, `.git`, and `node_modules` are never uploaded.

## Publish

```bash
# Cursor: ~/.cursor/skills/bigangels/scripts/publish.sh
~/.claude/skills/bigangels/scripts/publish.sh <file-or-folder>
```

Options:
- `--name "My site"` — display name in the dashboard.
- `--spa` — single-page apps (client-side routes work on refresh).
- `--new` — new site instead of updating the remembered one.

Re-publishing the same path **updates the same site** (`~/.bigangels/sites.json`). Unchanged files are skipped.

## After publishing

Return the exact URL from `published:` as a clickable link. **Never** share a URL before finalize — only `published:` means the site is live.

Do not paste claim tokens into chat; they stay in local state. If you see `expires:` (anonymous), mention 24h expiry briefly and offer sign-in or the `keep it:` link.

## Sign in (required before publish)

**Default (one command):** run browser sign-in. The script opens BigAngels; if the user is already signed in on the web, it finishes in one click. Otherwise they sign in once in the browser (email code there—not in chat).

```bash
# Cursor: ~/.cursor/skills/bigangels/scripts/login.sh
~/.claude/skills/bigangels/scripts/login.sh
```

Tell the user a browser tab may open and they should approve connecting the terminal. When the terminal prints `signed in as …`, continue (or let `publish.sh` finish — it runs sign-in itself when credentials are missing).

**Headless / SSH fallback** (email code in chat):

```bash
login.sh --email you@example.com
login.sh --email you@example.com 123456
```

This saves a `ba_live_*` key in `~/.bigangels/credentials`. `login.sh --status` shows who is signed in; `login.sh --logout` signs out.

Never invent or guess an email or code.

### Client tagging (`BIGANGELS_CLIENT`)

Scripts send `X-BigAngels-Client` as `<agent>/publish-sh` or `<agent>/login-sh`. Detection: skill path (`~/.cursor/skills` → `cursor`, `~/.codex/skills` → `codex`, `~/.claude/skills` → `claude-code`) or Cursor env. Override: `export BIGANGELS_CLIENT=cursor` (prefix only; role is appended).

## Skill vs MCP

- **Skill (this guide):** `publish.sh` + `login.sh` + `~/.bigangels/credentials`. Installed by `install.sh`.
- **MCP (separate):** `https://api.bigangels.app/mcp` — OAuth in Cursor Settings. Not installed by `install.sh`.

Use skill scripts unless the user is explicitly testing MCP OAuth (then use MCP tools only, no `publish.sh`).

## Troubleshooting

- `sign in required before publishing` (headless / CI / SSH) — run `login.sh --email` with the user, or paste a key into `~/.bigangels/credentials`, then rerun `publish.sh`. On a normal terminal, `publish.sh` opens the browser for sign-in automatically.
- `could not reach …` — the API is down or `BIGANGELS_API` is wrong. Production is `https://api.bigangels.app` (sites on `*.bigangels.site`). Local dev uses `http://bigangels.localhost:8787` — those slugs are not on production.
- `API mismatch` or `site is not reachable` — `BIGANGELS_API` does not match the environment serving the URL. Fix the env var and publish again.
- `upload failed` — rerun the same command; finished files are reused.
- `413` errors — limits are 500 files, 25 MB per file, 100 MB per site.
