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

**Publish without sign-in** for a live preview **deleted in 6 hours** unless claimed (banner on the site). Use the skill scripts — do not invent credentials or raw `curl` unless implementing the full upload flow.

On a publish/deploy request: run `publish.sh` first. If the user wants the site kept permanently, run `login.sh --status` (exit 0 = already signed in) or sign in with `login.sh --email`, then publish again or use the `keep it:` / claim link. Never paste claim tokens into chat.

## Before starting a project that needs a build

Run this preflight **before generating or modifying source files** for Next.js, React/Vite, TypeScript, or any project requiring dependency installation or compilation.

1. Check actual capabilities: command execution, writable project files, Node.js (`node --version`), the appropriate package manager and version, access to the project's package registry (a lightweight metadata request), and an available BigAngels publishing connection. Do not install dependencies just to probe. Never print credentials. An MCP connection alone does not prove terminal or network access.
2. If all checks pass, proceed without asking the user to switch. Plain HTML/CSS/JavaScript and already-built static output do not require Node.js or this build preflight; publish them normally.
3. If a required capability is missing or cannot be checked, **pause before creating the build-based project** and say:

   > This project needs a build environment. Switch to ChatGPT Work with computer access so I can check the tools, install dependencies, build it and publish to BigAngels. Alternatively, continue in Codex, Claude Code or another coding agent with terminal and network access.

4. Supply a copyable handoff containing the project brief, framework, existing source files if any, and the existing BigAngels site URL/slug if updating. Exclude credentials. Tell the next agent to repeat the preflight, build, then publish the output to the same site. Do not claim you switched modes or assume a named mode guarantees access.
5. Confirm hosting compatibility before starting: BigAngels hosts static files, not a Next.js server. Next.js must support static export (`output: 'export'`); server-dependent features need a different hosting solution or an explicitly agreed scope change. Work fixes build access, not hosting compatibility. Never silently substitute plain HTML for a requested framework.
6. If a later install/build fails, report the real error. Offer the Work handoff for an environment access blocker; do not suggest switching will fix source-code errors. Keep the existing site live and publish only after a successful build. Upload `dist/`, `out/`, or the appropriate static output, never raw framework source or `.next/` as a working website.

## Agent workflow (checklist)

1. **Install** (once per machine): `curl -fsSL https://bigangels.app/install.sh | bash` or `npx skills add attentionfactory/bigangels-skill --skill bigangels -g`. Agents can also fetch setup from `https://bigangels.app/llms.txt` or `/llm-info.txt`.
2. **Publish**: `publish.sh <path>` → read the line `published: https://…` and give that URL to the user (clickable). Anonymous previews are **deleted in 6 hours** unless claimed.
3. **Sign in to keep**: `login.sh --email` or `login.sh --browser` when the user wants permanent hosting on their account.
4. **Verify**: the script already HTTP-checks the URL after finalize; if it fails, fix `BIGANGELS_API` and publish again.

## Starter prompt (share with the user)

Copy this into a new agent chat after install:

```text
I use BigAngels for instant static hosting (sites, demos, reports, exports).

1) Install the skill if needed: curl -fsSL https://bigangels.app/install.sh | bash
2) When I say "publish this to BigAngels", run publish.sh on the file or folder and return the published: URL. Without saved credentials, publish a public six-hour preview.

Show me the live site first. Ask me to sign in only when I want to keep it permanently. Use the skill scripts for publishing.
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
- `--anonymous` — ignore saved and environment credentials, publish a public six-hour preview, and remember it separately from account-owned sites.

Re-publishing the same path **updates the same site** (`~/.bigangels/sites.json`). Unchanged files are skipped.

## After publishing

Return the exact URL from `published:` as a clickable link. **Never** share a URL before finalize — only `published:` means the site is live.

Do not paste claim tokens into chat; they stay in local state. If you see `deleted in:` or `expires:` (anonymous preview), **stress urgency**: the site is **deleted in 6 hours** unless they sign up and open the `keep it:` link. Do not say “turn off”, “scheduled off”, or “we’re not deleting.”

## Sign in (to keep sites permanently)

**Default: email code in this chat.** Check `login.sh --status` first. Reuse valid credentials; if the prompt specifies another account, ask before switching. A network/service error is not an invalid sign-in.

If not signed in, ask for the user's email (or use the email they already provided), then run:

```bash
login.sh --email you@example.com
```

Ask the user to paste the emailed 6-digit code into this chat. Wait for their response; never invent a code or fetch it from their inbox. Then run:

```bash
login.sh --email you@example.com 123456
```

On success, a `ba_live_*` key is saved privately in `~/.bigangels/credentials`. Do not print or paste the key. Confirm `login.sh --status`, then continue publishing automatically. Invalid or expired codes: ask for a corrected code or request a fresh one; don't switch flows silently.

**Browser alternative:** if the user prefers browser sign-in, run `login.sh --browser` and let them approve the connection. **OAuth alternative:** for agents without shell access, connect `https://api.bigangels.app/mcp` through the client's connector settings and OAuth. Do not claim to install or run scripts in an environment that cannot execute commands.

`login.sh --logout` signs out locally. Never guess an email or code.

For an anonymous test, use `publish.sh <path> --anonymous`; there is no need to uninstall the skill or erase credentials. Previews made this way use `~/.bigangels/anonymous-sites.json` and can still be recovered into the account after sign-in from the same device.

### Client tagging (`BIGANGELS_CLIENT`)

Scripts send `X-BigAngels-Client` as `<agent>/publish-sh` or `<agent>/login-sh`. Detection: skill path (`~/.cursor/skills` → `cursor`, `~/.codex/skills` → `codex`, `~/.claude/skills` → `claude-code`) or Cursor env. Override: `export BIGANGELS_CLIENT=cursor` (prefix only; role is appended).

## Skill vs MCP

- **Skill (this guide):** `publish.sh` + `login.sh` + `~/.bigangels/credentials`. Installed by `install.sh`.
- **MCP (separate):** `https://api.bigangels.app/mcp` — OAuth in Cursor Settings. Not installed by `install.sh`.

Use skill scripts unless the user is explicitly testing MCP OAuth (then use MCP tools only, no `publish.sh`).

## Troubleshooting

- `sign in required before publishing` — this is an outdated skill. Update it, then run `publish.sh` again. Anonymous publishing must show a public site without sign-in; use `--anonymous` to bypass saved credentials.
- `could not reach …` — the API is down or `BIGANGELS_API` is wrong. Production is `https://api.bigangels.app` (sites on `*.bigangels.site`). Local dev uses `http://bigangels.localhost:8787` — those slugs are not on production.
- `API mismatch` or `site is not reachable` — `BIGANGELS_API` does not match the environment serving the URL. Fix the env var and publish again.
- `upload failed` — rerun the same command; finished files are reused.
- `413` errors — limits are 500 files, 25 MB per file, 100 MB per site.
