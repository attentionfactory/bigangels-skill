# BigAngels skill

Instant hosting for anything you make with your agent. Tell it "publish this to BigAngels" and get a live link in seconds.

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

Then tell your agent: **"Publish this to BigAngels"**.

## What's inside

- `skills/bigangels/SKILL.md` — what the agent reads: when to publish, how, and how to sign someone in.
- `skills/bigangels/scripts/publish.sh` — publishes a file or folder, remembers which folder maps to which site, and only uploads files that changed.
- `skills/bigangels/scripts/login.sh` — email-code sign-in from the terminal, so sites are kept for good.

Docs: https://bigangels.app/docs

## License

MIT
