---
name: bigangels
description: >
  BigAngels publishes websites and files to a live URL in seconds. Use when the
  user asks to "publish this", "put this online", "host this", "deploy this",
  "share this on the web", "make a website", "give me a link", or "publish to
  BigAngels". Works for HTML sites, built apps (dist/ folders), documents,
  images, PDFs, CSV/JSON exports, browser games and WebAssembly apps (Godot,
  Unity WebGL, Emscripten, Rust/wasm-bindgen, Pyodide), and any static files.
  Also use it to add forms that save sign-ups, RSVPs, messages or scores (Site
  Data) without a backend, to let a page call AI or other APIs with a secret
  key the visitor never sees (variables and proxy routes), to find, file into
  folders, or show off sites the user published before, to search for and buy
  a domain name (always after the user confirms the price), and to keep
  private files that are not a website (notes, memory, plans, context, assets)
  in a Drive that other sessions, tools and agents can use ("save this for
  later", "remember this", "share this folder with another agent").
---

# BigAngels

Publish a file or folder and get a live URL like `https://bright-canvas-a7k2.<sites-domain>/`. No hosting setup, DNS, or deploy pipeline for the user — you upload static artifacts and return the link.

**Publish without sign-in** for a live preview that **goes offline after 6 hours** (banner on the site); claiming it within 7 days brings it back for good. Use the skill scripts — do not invent credentials or raw `curl` unless implementing the full upload flow.

On a publish/deploy request: run `publish.sh` first. If the user wants the site kept permanently, run `login.sh --status` (exit 0 = already signed in) or sign in with `login.sh --email`, then publish again or use the `keep it:` / claim link. Share the private keep link only with the intended owner; never expose claim tokens publicly.

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

1. **Install** (once per machine): `curl -fsSL https://bigangels.app/install.sh | bash` or `npx skills add attentionfactory/bigangels-skill --skill bigangels -g`. Agents can also fetch setup from `https://bigangels.app/llms.txt`, `/llm-info.txt`, or `/llms-full.txt`.
2. **Publish**: `publish.sh <path>` → read the line `published: https://…` and give that URL to the user (clickable). Anonymous previews **go offline after 6 hours**; claim within 7 days to keep them. Give the user the private `keep it:` link as well as the public site URL, and explain that the public banner alone cannot keep the site. Treat the keep link as a secret: share it only with the intended owner, never publicly.
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
| **Game / WebAssembly** | Engine web export folder (has `index.html`) | `./publish.sh ./build/web --cross-origin-isolation` |
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

`.env` files, `.git`, `node_modules` and `.bigangels/` are never uploaded, except `.bigangels/data.json` (Site Data) and `.bigangels/proxy.json` (proxy routes). Neither is ever served to visitors.

## Publish

```bash
# Cursor: ~/.cursor/skills/bigangels/scripts/publish.sh
~/.claude/skills/bigangels/scripts/publish.sh <file-or-folder>
```

Options:
- `--name "My site"` — display name in the dashboard.
- `--spa` — single-page apps (client-side routes work on refresh).
- `--cross-origin-isolation` — turn on cross-origin isolation (COOP/COEP headers) so `SharedArrayBuffer` and WebAssembly threads work. Use it for threaded game exports; see below. It stays on for later publishes; `--no-cross-origin-isolation` turns it off.
- `--folder "Client work"` — file the site in a folder (made if new). Only when the user names a folder, project or client; don't invent folders. `--no-folder` takes it out. Needs sign-in.
- `--new` — new site instead of updating the remembered one.
- `--anonymous` — ignore saved and environment credentials, publish a public six-hour preview, and remember it separately from account-owned sites.

Re-publishing the same path **updates the same site** (`~/.bigangels/sites.json`). Unchanged files are skipped.

## Games and WebAssembly

Publish the folder the engine exports, as is. Every file is uploaded byte for byte and never recompressed.

- `.wasm` is served as `application/wasm`, so `WebAssembly.instantiateStreaming` works. Game files (`.pck`, `.data`, `.unityweb`, `.glb`, `.gltf`, `.ktx2`, `.basis`, `.ogg`, `.opus`, `.flac`, `.avif`, `.webp`, `.woff2`, `.wasm.map`, `.symbols.json`) get correct types.
- **Keep pre-compressed files.** `Build.wasm.br`, `Build.data.gz`, `Build.framework.js.br` are served with `Content-Encoding: br|gzip` and the type of the file inside, so the browser unpacks them. A request for `game.wasm` is answered from `game.wasm.br` when only the compressed file exists. Do not decompress or rename them first. Pages are the exception: keep `index.html` and other `.html` files uncompressed (an `.html.gz` is served as a download, not a page).
- **Threads need isolation.** If the game uses threads or `SharedArrayBuffer` (Godot 4 with Thread Support, Unity with WebAssembly threads, Emscripten `-pthread`, wasm-bindgen threads), publish with `--cross-origin-isolation`. Signs it is needed: the console says `SharedArrayBuffer is not defined` or `crossOriginIsolated` is false. The setting stays on for later publishes of the same site; turn it off with `--no-cross-origin-isolation`, in the dashboard (Settings → Access), or with `PATCH /api/v1/sites/:slug` and `{"crossOriginIsolation": false}`.
- With isolation on, files loaded from other websites (CDN scripts, fonts, ads, analytics, embedded videos) are blocked unless they send CORS or `Cross-Origin-Resource-Policy: cross-origin`. Keep game files inside the published folder.
- Threads only run when the game is opened in its own tab (or framed by another isolated page with `allow="cross-origin-isolated"`). The dashboard preview shows the page but a threaded game won't start there; give the user the site URL to play.
- Paths in the export must be relative (`Build/game.wasm`) or root-relative (`/Build/game.wasm`).
- Limits: 25 MB per file, 100 MB per site. Compressed exports count at their compressed size. If a file is too big, re-export with Brotli/Gzip compression or split the data.

## Find, file and show off sites

- **Find one:** when the user mentions a site you don't have the slug for ("the bakery one", "the page with the menu"), search instead of guessing: `curl "${BIGANGELS_API:-https://api.bigangels.app}/api/v1/sites/search?q=bakery%20menu" -H "Authorization: Bearer $(cat ~/.bigangels/credentials)"`. It matches names, addresses, file names and page text; each result has `site.slug`, `matchedFields`, `matchedPaths` and a `snippet`. MCP: `search_sites`.
- **Folders:** `--folder` on publish, or `PATCH /api/v1/sites/<slug>` with `{"folder": "Name"}` (`null` to unfile). `GET /api/v1/folders` lists them; up to 50, names up to 60 characters. MCP: `list_folders`, `move_site_to_folder`.
- **Profile:** every account has a username. The public profile at `https://bigangels.app/@<username>` shows only the sites the user picks, and is off until they turn it on in **Settings → Profile**. Point them there; don't add sites to it unless asked. Sites with a password or shared with specific people can never appear.
- **Personal address:** on Creator and Pro, `publish.sh` also prints `also at: https://<site-name>.<username>.bigangels.site/`. Share that one when it's there; the `published:` address keeps working too. Rename it with `PATCH /api/v1/sites/<slug>` `{"siteName": "my-bakery"}`; old names redirect.

## After publishing

Return the exact URL from `published:` as a clickable link. **Never** share a URL before finalize — only `published:` means the site is live.

Share the private keep link only with the intended owner; never expose claim tokens publicly. If you see `offline in:` or `expires:` (anonymous preview), **stress urgency**: the site **goes offline in 6 hours** unless they sign up and open the `keep it:` link. Tell them plainly that they have 7 days after that to bring it back, and that an unclaimed preview is then deleted for good. Don't make it sound permanent.

## Edit a site that's already live

Read what's live before changing it, instead of guessing (works on password-protected and invite-only sites too):

```bash
curl -sS https://api.bigangels.app/api/v1/sites/<slug>/files -H "Authorization: Bearer $(cat ~/.bigangels/credentials)"
curl -sS https://api.bigangels.app/api/v1/sites/<slug>/files/index.html -H "Authorization: Bearer $(cat ~/.bigangels/credentials)" -o index.html
```

For built projects, `publish.sh dist/` (or `out/`/`build/`) saves the adjacent project privately under `.bigangels/source/` when its parent has `package.json`. Use `--source DIR` for other layouts or `--no-source` to opt out. Source counts toward the same site limits as output. Dependencies, the build, `.env*`, and common credential paths and patterns are excluded; scanning is best effort, so review the source before publishing and never rely on it to find every secret. Fetch the saved source first, edit it, build it, and publish the output with the updated source. A fresh agent can use `--site SLUG --base-version VERSION` using the version returned by the files API. A conflict means reread and reconcile; `--overwrite` intentionally bypasses that check.

The listing gives each file's path, size, contentType, hash and url. For an anonymous preview, send its claim token as `X-Claim-Token: <token>` instead (a header, never the URL). Edit the files, then run `publish.sh` on the folder again: unchanged files are skipped, only your edits upload. Over MCP, `get_site` lists paths and `read_site_file` returns a text file.

## Password-protect a site

Every site has one way in: **anyone with the link** (the default), **a password**, or **specific people** (next section). Choosing one replaces the other, and it covers everything on the site: pages, files, Site Data and proxy routes, at the `published:` address and the personal `also at:` address alike.

When the user wants a site private, send them to set the password themselves: **dashboard → the site → Settings → Access → Password protection**. Don't ask them to type a password into chat. If they paste one anyway, use it once and never repeat, log, save or echo it back, including in summaries.

With a password the user gave you, the API call is:

```bash
curl -sS -X PATCH "${BIGANGELS_API:-https://api.bigangels.app}/api/v1/sites/<slug>" -H "Authorization: Bearer $(cat ~/.bigangels/credentials)" \
  -H "Content-Type: application/json" -d '{"password": "<password>"}'   # {"password": null} removes it
```

- Needs a signed-in account and the Creator or Pro plan. `402` means upgrade (link the user to the pricing page); `409` means the site is a temporary preview that has to be kept first.
- 4 to 128 characters. The password stays on when you publish again, and `publish.sh` prints `password: on`.
- Visitors see "This site is private" and enter the password once per browser (30 days). Changing or removing it signs everyone out.
- After publishing a protected site, share the link and remind the user to send the password separately.
- Site Data forms and proxy routes on a protected site only work for visitors who entered the password. The owner still sees entries in the dashboard, `list_site_data` or the API.

## Share with specific people

When the user wants only certain people to see a site ("just my team", "only Sam and Ade", "only me"), limit it to their emails. Visitors type their email on the site and get a 6-digit code; nobody else gets in. The easiest way for the user: **dashboard → the site → Settings → Access → Who can view → Specific people**.

From the agent (full-list replace: read first, merge, write the whole list back):

```bash
API="${BIGANGELS_API:-https://api.bigangels.app}/api/v1/sites/<slug>/access"; AUTH="Authorization: Bearer $(cat ~/.bigangels/credentials)"
curl -sS "$API" -H "$AUTH"   # {mode, accessPolicyVersion, allowedEmails, allowedDomains}
curl -sS -X PATCH "$API" -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"mode": "restricted", "allowedEmails": ["sam@example.com"], "allowedDomains": ["company.com"], "notify": true}'
```

- Modes: `anyone_with_link` (opens it, removes any password), `password` (with `"password"`), `restricted`. Restricted with both lists empty is **Only you**: the owner signs in on the site with their account email.
- **Ask before `notify: true`.** It emails an invite to each newly added address (max 200 per request; more is `400 too_many_invites` and nothing is saved). `POST .../access/invites {"emails": [...]}` re-sends to people already on the list. Each person gets at most one invite per site a day (`skipped: recently_invited`) and an account at most 1,000 a day (`daily_limit`).
- A list you leave out stays as it is; `[]` empties it. Up to 10,000 emails and 10,000 domains. `@company.com` or `company.com` lets everyone at that company in (exact domain, not subdomains).
- Needs the Creator or Pro plan (`402`, link the pricing page) and a kept site (`409 access_requires_account`). Every change signs everyone out. The list stays when you publish again, and `publish.sh` prints `access: specific people`.
- Share the link and tell the user their guests will be asked for their email. Never paste the guest list into public places.

## Undo a publish (versions) and duplicate a site

Every publish is kept. If the user says "go back", "undo that" or "the old one was better", restore the earlier version instead of re-publishing old files. It switches instantly on the same link.

```bash
API="${BIGANGELS_API:-https://api.bigangels.app}/api/v1"; KEY="$(cat ~/.bigangels/credentials)"
curl -sS "$API/sites/<slug>/versions" -H "Authorization: Bearer $KEY"                     # newest first; `current` marks the live one
curl -sS -X POST "$API/sites/<slug>/versions/<versionId>/restore" -H "Authorization: Bearer $KEY"
curl -sS -X POST "$API/sites/<slug>/duplicate" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"displayName": "Test copy"}'                  # new link, same files
```

- MCP has the same as `list_versions`, `restore_version` and `duplicate_site`.
- Restore brings back that version's files, app mode, cross-origin isolation and Site Data collections. The password, who-can-view list, domains and saved entries stay. Restoring the version that was live before undoes it.
- `409 already_live`: it's already live. `409 restore_event`: pick a real version, not a restore entry. `409 publish_in_progress`: a publish is still uploading; finish it first.
- To try a risky change, duplicate the site and publish to the copy. The copy has no entries, password, guest list or domains.
- Previews and deleting versions are for the user in the dashboard (the site's Versions tab). Don't delete versions unless they ask.

## Buy a domain

When the user wants their own address (example.com), search and buy it through BigAngels. Needs a signed-in account. **Money moves, so follow these rules every time:**

1. Search or check, then tell the user the exact domain, the **first-year price** (`price.totalCents`) and the **yearly renewal price** (`renewalPriceCents`), and that it renews automatically unless they say otherwise. Say "premium" plainly when `premium` is true.
2. **Buy only after the user explicitly says yes to that price** in this conversation. Never choose a name for them, never buy to test, never retry at a different price without asking again.
3. Purchase with that same total as `acknowledgedPriceCents` (required on every purchase).

```bash
API="${BIGANGELS_API:-https://api.bigangels.app}/api/v1/registrar"; AUTH="Authorization: Bearer $(cat ~/.bigangels/credentials)"
curl -sS "$API/search?q=golden%20crumb" -H "$AUTH"                # ranked names, estimated prices
curl -sS "$API/check/goldencrumb.com" -H "$AUTH"                  # exact price: price.totalCents, renewalPriceCents
curl -sS -X POST "$API/purchase" -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"domain": "goldencrumb.com", "acknowledgedPriceCents": 1099}' # only after the user said yes to $10.99 + renewal
```

- `409 price_changed`: nothing was charged; show the new `details.quote` price and ask again. `409 price_confirmation_required` / `premium_confirmation_required`: you forgot `acknowledgedPriceCents`. `409 domain_unavailable`: pick another name with the user.
- `402 payment_method_required`: the user adds a card in the dashboard (Settings → Billing). `402 payment_failed`: the card was declined, nothing was bought. `502 registration_failed`: the registry refused and the charge was refunded. `429`: purchase limit (Free 1, Creator 5, Pro 20 new domains per 30 days) or too many registrar calls; wait for `Retry-After`. `403 api_key_required`: buying and transfer codes need the API key from login.sh or the dashboard, not an MCP connection.
- Buying the same domain again returns the first purchase (`replayed: true`) without a second charge.
- After purchase, tell the user the domain is theirs and **ready to connect**: it will show one of their sites once custom domains arrive in BigAngels. Don't promise it serves the site today. Email and other DNS records work now.
- Manage: `GET $API/domains`, `PATCH $API/<domain>` with `{"autoRenew": false}`, records with `GET`/`PUT $API/<domain>/records` (replace-all: GET first, send back what to keep; MX/SRV need `priority`; `@` and `www` A/AAAA/CNAME are kept for the site, `409 serving_record`). `GET $API/<domain>/transfer` returns the transfer code after the 60-day lock and emails the owner: use it only when the user asks to move the domain away, and don't repeat the code beyond what they need.
- If the user already owns the domain somewhere else, buying is the wrong tool: connecting your own domain is coming soon in the dashboard.

## Save form submissions and data

Use **Site Data** when a static site or single-page app needs to save what visitors send: waitlists, RSVPs, contact forms, quiz scores, feedback, guestbooks. No backend, database or keys in the page.

1. Write `.bigangels/data.json` at the **site root** (for Vite/React/Vue/Next.js static export put it in `public/.bigangels/data.json` so the build copies it; SvelteKit: `static/.bigangels/data.json`). `publish.sh` uploads it; visitors can never download it.
2. Add the form (below) and publish. `publish.sh` prints `site data: on (waitlist)`. Any `warning:` lines mean the manifest has a mistake: the site is live but the schema did not change. Fix the manifest and publish again.
3. Show the person their entries: the site's **Data** tab in the dashboard, the MCP tool `list_site_data`, or `curl -H "Authorization: Bearer $(cat ~/.bigangels/credentials)" https://api.bigangels.app/api/v1/sites/<slug>/data/<collection>`. CSV: `…/data/<collection>/export.csv`.

Entries belong to the site and survive every republish. Omitting the manifest later keeps the schema; `{"collections": {}}` turns saving off (old entries stay for export).

**Manifest rules.** Field types: `string`, `number`, `integer`, `boolean`, `url`, `email`, `datetime`, `array`, `object`. Options: `required`, `default`, `minLength`, `maxLength`, `minimum`, `maximum`, `trim`, `allowedProtocols`. `access` per action (`read`, `insert`, `update`, `delete`) is `public`, `owner` or `none`; defaults are read owner, insert public, update owner, delete owner. Public `update`/`delete` also needs `"publicMutation": "open"`. `rateLimit` is `"10/hour/ip"` / `"5/minute/ip"` (writes) or `{"read": "600/hour/ip", "write": "10/hour/ip"}` (the defaults). Limits: 64 KB manifest, 10 collections, 50 fields, 16 KB per entry (lists and objects nested at most 10 levels), 25,000 entries per collection, 100,000 per site. Site Data only works on sites saved to an account: on an anonymous preview, publish prints `site data: off` with a warning, and the data routes answer `403 account_required` until the site is claimed. Keep anything private (emails, phone numbers) on `"read": "owner"`.

### Ready-made manifests

Waitlist (only the owner sees emails):

```json
{"collections": {"waitlist": {
  "fields": {"email": {"type": "email", "required": true, "maxLength": 254}, "name": {"type": "string", "maxLength": 100}},
  "access": {"read": "owner", "insert": "public"}, "rateLimit": "5/hour/ip"}}}
```

RSVP:

```json
{"collections": {"rsvps": {
  "fields": {"name": {"type": "string", "required": true, "maxLength": 100}, "email": {"type": "email", "required": true},
             "attending": {"type": "boolean", "required": true}, "guests": {"type": "integer", "minimum": 0, "maximum": 5, "default": 0},
             "dietary": {"type": "string", "maxLength": 200}},
  "access": {"read": "owner", "insert": "public"}, "rateLimit": "5/hour/ip"}}}
```

Contact / lead form:

```json
{"collections": {"leads": {
  "fields": {"name": {"type": "string", "required": true, "maxLength": 100}, "email": {"type": "email", "required": true},
             "company": {"type": "string", "maxLength": 120}, "website": {"type": "url", "allowedProtocols": ["https"]},
             "message": {"type": "string", "required": true, "minLength": 10, "maxLength": 2000}},
  "access": {"read": "owner", "insert": "public"}, "rateLimit": "3/hour/ip"}}}
```

Quiz scores (public leaderboard):

```json
{"collections": {"scores": {
  "fields": {"player": {"type": "string", "required": true, "maxLength": 30},
             "score": {"type": "integer", "required": true, "minimum": 0, "maximum": 1000}, "answers": {"type": "array", "maxLength": 50}},
  "access": {"read": "public", "insert": "public"}, "rateLimit": {"read": "600/hour/ip", "write": "20/hour/ip"}}}}
```

Feedback / guestbook (everyone can read):

```json
{"collections": {"guestbook": {
  "fields": {"name": {"type": "string", "required": true, "maxLength": 60}, "message": {"type": "string", "required": true, "maxLength": 500},
             "rating": {"type": "integer", "minimum": 1, "maximum": 5}},
  "access": {"read": "public", "insert": "public"}, "rateLimit": "10/hour/ip"}}}
```

### The form

```html
<form data-bigangels="waitlist">
  <label>Email <input name="email" type="email" required></label>
  <input name="_gotcha" tabindex="-1" autocomplete="off" hidden>  <!-- bots fill this; it is dropped -->
  <button type="submit">Join the waitlist</button>
  <p data-bigangels-message></p>  <!-- shows "Thanks, it's saved." or the problem -->
</form>
<script src="/.bigangels/data.js"></script>
```

Input `name`s must match the manifest fields (names starting with `_` are ignored). Without JavaScript: `<form method="post" action="/.bigangels/data/waitlist">` plus `<input type="hidden" name="_next" value="/thanks.html">`.

### Single-page apps (React Router, Vue, Svelte)

Always call the site root, so nested routes work (a relative `./.bigangels/data/x` from `/app/settings` also works: the last `/.bigangels/data/` in the path wins).

```js
// After <script src="/.bigangels/data.js"> in index.html (or: import { data } from "/.bigangels/data.mjs")
const scores = window.BigAngels.data("scores");
await scores.create({ player: "Ada", score: 870 });          // -> { id, data, createdAt, updatedAt }
const { records, nextCursor } = await scores.list({ limit: 10 }); // newest first; pass { cursor: nextCursor } for more
// also scores.get(id), scores.update(id, fields), scores.remove(id); errors have .message, .code, .fields, .retryAfter

// Plain fetch works too:
const res = await fetch("/.bigangels/data/scores", {
  method: "POST",
  headers: { "content-type": "application/json", "idempotency-key": crypto.randomUUID() },
  body: JSON.stringify({ player: "Ada", score: 870 }),
});
```

Writes must come from a page on the same site (the browser's `Origin`); other websites and plain `curl` without a key are refused. Errors are JSON `{error, code, message, retry_after?}`; show `message` to people. `account_required` means the site is an unclaimed preview: have the user claim it. Do not use Site Data for passwords, payments or secrets.

## Call AI and other APIs without exposing keys
Use **proxy routes** when a page needs an API key: an AI chat (OpenRouter, OpenAI, Anthropic), a database (Supabase), weather, maps. The key is saved once as a **variable** on the account; the page calls a path on its own site (`fetch("/api/chat")`) and BigAngels adds the key on the server. Visitors never see it. Never put an API key in HTML or JavaScript.

1. **Save the key as a variable.** Best: ask the user to add it themselves in the dashboard under **Variables** ("Keys your sites can use without showing them to visitors"), so it stays out of the chat. If they paste it to you instead, save it without printing it back:
   ```bash
   curl -sS -X PUT "${BIGANGELS_API:-https://api.bigangels.app}/api/v1/me/variables/OPENROUTER_API_KEY" \
     -H "Authorization: Bearer $(cat ~/.bigangels/credentials)" -H "content-type: application/json" \
     -d '{"value": "<the key>", "allowedUpstreams": ["openrouter.ai"]}'
   ```
   Names are `A-Z`, digits and `_`, starting with a letter (64 max). Up to 50 per account, 4 KB each. `allowedUpstreams` (hostnames; subdomains match) pins where the value may go: any other upstream gets `403 variable_not_allowed`. Send it on every update; leaving it out removes the pin. `GET /api/v1/me/variables` lists names, never values; `DELETE /api/v1/me/variables/NAME` removes one. Add `?space=<spaceId>` to set a value for one space's sites only (it wins over the account-wide value there). MCP: `list_variables`, `set_variable`.
2. **Write `.bigangels/proxy.json`** at the site root (Vite/React/Next.js static export: `public/.bigangels/proxy.json`) and publish. `publish.sh` prints `proxy routes: on (/api/chat)`. Any `warning:` line is a problem to fix: an invalid file still publishes, but **every route stays off** until it's fixed. A warning that a variable is missing means the route answers `503` until it's added.

**Route rules.** Keys are site paths starting with `/`: exact (`/api/chat`) or a prefix ending in `/*` (`/api/db/*` sends `/api/db/todos` to `<upstream>/todos`). `upstream` must be `https://` and a public hostname (no IP addresses, localhost, private or BigAngels addresses). `method`: one or a list of `GET POST PUT PATCH DELETE` (default `GET` and `POST`; `GET` also answers `HEAD`). `headers`: sent upstream; `${NAME}` becomes the variable, at request time. `forward`: visitor headers to pass through (Cookie and Authorization are dropped otherwise). `rateLimit`: `"20/hour/ip"`, `"5/minute/ip"` or `"500/day/ip"` (default `100/hour/ip`). The visitor's query string is passed on; so are its `Content-Type` and `Accept`, nothing else. Bodies up to 10 MB. Streaming responses (SSE) arrive as they're sent. Only pages on the same site can call a route (other websites get `403 cross_origin`), upstream `Set-Cookie` and CORS headers are dropped, and a password-protected site's routes need the password like every page. Routes belong to the version: publishing without the file removes them. Routes only run on sites saved to an account (`403 account_required` on a preview). Errors are JSON `{error, code, message}`; show `message`.

### AI chat with OpenRouter (streaming)

`.bigangels/proxy.json`:

```json
{"proxies": {"/api/chat": {
  "upstream": "https://openrouter.ai/api/v1/chat/completions",
  "method": "POST",
  "headers": {"Authorization": "Bearer ${OPENROUTER_API_KEY}", "X-Title": "My chat"},
  "rateLimit": "20/hour/ip"}}}
```

`index.html`:

```html
<form id="ask"><input name="q" placeholder="Ask anything" required autocomplete="off"><button>Send</button></form>
<p id="answer" aria-live="polite"></p>
<script>
const messages = [];
document.getElementById("ask").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.target, out = document.getElementById("answer");
  messages.push({ role: "user", content: form.q.value });
  form.reset(); out.textContent = "";
  const res = await fetch("/api/chat", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ model: "openai/gpt-4o-mini", messages, stream: true }),
  });
  if (!res.ok) { out.textContent = (await res.json()).message ?? "Something went wrong. Try again."; return; }
  const reader = res.body.getReader(), decoder = new TextDecoder();
  let buffer = "", reply = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n"); buffer = lines.pop();
    for (const line of lines) {
      if (!line.startsWith("data: ") || line === "data: [DONE]") continue;
      reply += JSON.parse(line.slice(6)).choices?.[0]?.delta?.content ?? "";
      out.textContent = reply;
    }
  }
  messages.push({ role: "assistant", content: reply });
});
</script>
```

Anyone who can open the page can use the route, so keep `rateLimit` low and set a spending limit on the OpenRouter key itself. Password-protect the site to keep it to people you invite.

### Supabase

Keeps the project address and key out of the page and lets you rate-limit. Use the **anon** (publishable) key with Row Level Security on your tables. Never put the `service_role` key behind a prefix route: every visitor could then read and change everything.

```json
{"proxies": {"/api/db/*": {
  "upstream": "https://YOUR-PROJECT.supabase.co/rest/v1/",
  "method": ["GET", "POST"],
  "headers": {"apikey": "${SUPABASE_ANON_KEY}", "Authorization": "Bearer ${SUPABASE_ANON_KEY}"},
  "rateLimit": "300/hour/ip"}}}
```

```js
const todos = await (await fetch("/api/db/todos?select=id,title&done=eq.false")).json();
await fetch("/api/db/todos", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ title: "Buy milk" }) });
```

Save the variable with `"allowedUpstreams": ["YOUR-PROJECT.supabase.co"]`. Signed-in Supabase users: add `"forward": ["Authorization"]` and drop the declared `Authorization` so each visitor's own token reaches Supabase.

## Keep files in a Drive

A **Drive** is a private cloud folder on the user's account. Nothing in it is public. Use it for files that are **not a website**, or not one yet, and that should outlive this session:

- notes, memory and preferences you want to find again in a later conversation or another tool;
- plans, specs, research and context to hand to another agent;
- assets (images, data, exports) a later task will need;
- a site's working files, published later with `drive.sh publish`.

Use `publish.sh` for anything people should open in a browser now. Use Site Data for what visitors submit. Every account has a default Drive, **My Drive**; create more with `drive.sh create "Name"` (up to 20).

```bash
D=~/.claude/skills/bigangels/scripts/drive.sh     # Cursor: ~/.cursor/skills/…, Codex: ~/.codex/skills/…
$D ls                                  # top level of My Drive; $D ls notes/ for a folder, -r for everything
$D put plan.md plans/launch.md         # prints saved: … etag …
$D cat plans/launch.md                 # or: $D get <path> [local-file]
$D import ./research research/         # a whole folder; unchanged files are skipped
$D export research/ ./research-copy
$D mv plans/launch.md plans/done/launch.md   # folders: $D mv old/ new/
$D rm plans/old.md                     # a folder: $D rm drafts -r
$D link assets/chart.png               # a download link that works for 15 minutes
$D publish site/                       # publish the site/ folder as a website (prints published:)
$D ls --drive Research                 # any command works on another Drive, by name or drv_ id
```

**Never lose someone else's change.** Every file has an `etag`, printed by `put` and `ls`. When you update a file another agent or session might also edit, read it first, then write with `--if-match <etag>`. If it changed in between, the write is refused (`412 etag_mismatch`) and nothing is overwritten: read it again, merge, retry. `--create-only` refuses to overwrite an existing file. Every write makes a new Drive version (`drive.sh versions`); replaced and deleted files stay readable for 30 days through `?version=dv_…` (up to as much again as the plan's storage, oldest let go first) and can be published from.

**Share with another agent.** Give it a token, never your own key:

```bash
$D share --perms read --prefix research/ --ttl 7d --label "review agent"   # prints token: drv_live_…
$D share --perms write --prefix inbox/ --ttl 1d --manage                   # --manage lets it mint narrower tokens
$D tokens                                                                  # list
$D revoke dtok_…                                                           # stops it (and tokens it made) at once
```

The other agent runs `BIGANGELS_DRIVE_TOKEN=drv_live_… drive.sh cat research/notes.md` (same commands, limited to that Drive and folder). Tokens are shown once: hand them over privately, do not paste them into public places, and prefer the narrowest folder, read-only, and a short `--ttl`. A token can't create Drives, publish sites or reach any other Drive.

**Chat clients (MCP):** `drive_list`, `drive_read` and `drive_write` keep small text files (up to 256 KB) such as memory and notes in a Drive. Pass the `etag` from `drive_read` as `ifMatch` to `drive_write`.

**Limits.** Drive storage is shared by all Drives on the account: 500 MB on Free, 5 GB on Creator, 50 GB on Pro. Each file can be up to 25 MB on Free, 100 MB on Creator and Pro. Up to 10,000 files per Drive and 20 Drives per account. `413 storage_full` means delete files or upgrade.

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

**No `login.sh` here?** The same flow is two HTTP calls: `POST https://api.bigangels.app/api/v1/auth/request-code {"email"}`, ask the person for the emailed code, then `POST .../auth/verify-code {"email","code","keyName":"<your-tool>"}`. The reply's `apiKey` is shown once: write it to `~/.bigangels/credentials` (mode 600) and never print it. A new email creates a free account.

**Browser alternative:** if the user prefers browser sign-in, run `login.sh --browser` and let them approve the connection. **OAuth alternative:** for agents without shell access, connect `https://api.bigangels.app/mcp` through the client's connector settings and OAuth. Do not claim to install or run scripts in an environment that cannot execute commands.

`login.sh --logout` signs out locally. Never guess an email or code.

For an anonymous test, use `publish.sh <path> --anonymous`; there is no need to uninstall the skill or erase credentials. Previews made this way use `~/.bigangels/anonymous-sites.json` and can still be recovered into the account after sign-in from the same device.

### Client tagging (`BIGANGELS_CLIENT`)

### Environment (`BIGANGELS_API`, `BIGANGELS_API_KEY`, …)

- `BIGANGELS_API` — API origin (default `https://api.bigangels.app`; local dev: `http://bigangels.localhost:8787`).
- `BIGANGELS_API_KEY` — optional `ba_live_*` key for CI or headless agents; overrides `~/.bigangels/credentials` in `publish.sh` and `login.sh --status` (never paste keys into chat).
- `BIGANGELS_APP` — web app origin when using browser sign-in against a non-production API.
- `BIGANGELS_HOME` — state directory (default `~/.bigangels`).
- `BIGANGELS_CLIENT` — analytics/auth key name prefix; scripts send `X-BigAngels-Client` as `<agent>/publish-sh` or `<agent>/login-sh`. Detection: skill path (`~/.cursor/skills` → `cursor`, `~/.codex/skills` → `codex`, `~/.claude/skills` → `claude-code`) or Cursor env. Override: `export BIGANGELS_CLIENT=cursor` (prefix only; role is appended).

**Headless / cloud agents:** use `login.sh --status` before sign-in; prefer `login.sh --email` (no browser). Install via `curl … | bash` skips optional sign-in prompts when stdout is not a TTY.

## Skill vs MCP

- **Skill (this guide):** `publish.sh` + `login.sh` + `drive.sh` + `~/.bigangels/credentials`. Installed by `install.sh`.
- **MCP (separate):** `https://api.bigangels.app/mcp` — OAuth in Cursor Settings. Not installed by `install.sh`. Its tools cover publishing, `get_site`, `read_site_file`, Site Data, versions, search and folders, variables and small Drive files; buying domains and transfer codes need the API key from `login.sh`.

Use skill scripts unless the user is explicitly testing MCP OAuth (then use MCP tools only, no `publish.sh`).

## Troubleshooting

- `sign in required before publishing` — this is an outdated skill. Update it, then run `publish.sh` again. Anonymous publishing must show a public site without sign-in; use `--anonymous` to bypass saved credentials.
- `could not reach …` — the API is down or `BIGANGELS_API` is wrong. Production is `https://api.bigangels.app` (sites on `*.bigangels.site`). Local dev uses `http://bigangels.localhost:8787` — those slugs are not on production.
- `API mismatch` or `site is not reachable` — `BIGANGELS_API` does not match the environment serving the URL. Fix the env var and publish again.
- `upload failed` — rerun the same command; finished files are reused.
- `413` errors — limits are 500 files, 25 MB per file, 100 MB per site. The error names the file and its size.
- Game shows `SharedArrayBuffer is not defined` — publish again with `--cross-origin-isolation`.
- `proxy routes: off` or a `warning:` about `.bigangels/proxy.json` — fix the file and publish again; until then every route is off. `503 variable_missing`: add the named variable. `403 variable_not_allowed`: the variable is pinned to another host.
- `401 access_required` (or `password_required`) on a page, a Site Data call or a proxy route — the site is shared with specific people (or has a password). Visitors confirm their email (or enter the password) on the site first; the owner reads entries through the API.
- `Incorrect response MIME type. Expected 'application/wasm'` — publish the export folder with this skill (not a zip of it), and keep `.br`/`.gz` names as exported.
