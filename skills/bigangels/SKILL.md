---
name: bigangels
description: >
  BigAngels publishes websites and files to a live URL in seconds. Use when the
  user asks to "publish this", "put this online", "host this", "deploy this",
  "share this on the web", "make a website", "give me a link", or "publish to
  BigAngels". Works for HTML sites, built apps (dist/ folders), documents,
  images, PDFs, videos, and any static files.
---

# BigAngels

Publish a file or folder and get a live URL like `https://bright-canvas-a7k2.<sites-domain>/`.

## Publish

```bash
~/.claude/skills/bigangels/scripts/publish.sh <file-or-folder>
```

Options:
- `--name "My site"` — a display name for the dashboard.
- `--spa` — for single-page apps (React/Vue/Svelte builds) so client-side routes work on refresh.
- `--new` — publish as a brand-new site instead of updating the previous one.

Publishing the same folder again **updates the same site** — the script remembers it in `~/.bigangels/sites.json`. Unchanged files are skipped automatically.

## What to publish

- A plain HTML site: publish the folder that contains `index.html`.
- A built app (Vite, Next static export, etc.): build first, then publish the output folder (`dist/`, `out/`, `build/`) with `--spa` if it uses client-side routing. Asset paths should be root-relative (`/assets/app.js`) — Vite does this by default.
- A single file (PDF, image, video, markdown): publish the file directly; it gets a clean viewer page.

`.env` files, `.git`, and `node_modules` are never uploaded.

## After publishing

Tell the user the exact URL printed after `published:`, as a clickable link. Do not paste the claim token into chat — it is saved locally.

If the output has an `expires:` line, the site is anonymous and disappears in 24 hours. Say so in one short line and offer two ways to keep it: open the `keep it:` link (copy it exactly), or sign in right here (below).

## Sign in (keeps sites permanently)

Signing in happens inside this conversation; the user never has to visit a website.

1. Ask the user for their email, then run:
   ```bash
   ~/.claude/skills/bigangels/scripts/login.sh you@example.com
   ```
2. Ask them for the 6-digit code from the email, then run:
   ```bash
   ~/.claude/skills/bigangels/scripts/login.sh you@example.com 123456
   ```

This saves a key in `~/.bigangels/credentials`. From then on every publish is permanent, and sites published earlier from this computer are kept automatically. `login.sh --status` shows who is signed in; `login.sh --logout` signs out.

Only start sign-in when the user wants it (they asked to keep a site, or to sign in). Never invent or guess an email or code.

## Troubleshooting

- `could not reach …` — the API is down or `BIGANGELS_API` is wrong.
- `upload failed` — rerun the same command; finished files are reused.
- `413` errors — limits are 500 files, 25 MB per file, 100 MB per site.
