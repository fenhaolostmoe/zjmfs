# zjmf-registration-api

> Network protocol compatibility study — Cloudflare Workers implementation
> Observing and matching the observable HTTP response format of a publicly-distributed installer.

---

## ⚠️ Disclaimer

This repository contains a **network protocol study** — observing what HTTP requests a publicly-available installer binary sends, and documenting the response format it expects. The Cloudflare Workers service returns **static, hand-written JSON** that matches the schema observed on the wire.

**This implementation is 100% original TypeScript.** It does not copy, reference, or depend on any closed-source or commercial code. This project is **non-commercial**, **unmonetized**, and causes **no harm** to any party.

---

## What's in this repo

| File | Description |
|------|-------------|
| `src/index.ts` | Cloudflare Workers — static JSON responses matching observable endpoint format |
| `install.sh` | Build-and-run helper: downloads an open-source installer source, rebuilds it with a configurable HTTP endpoint URL |
| `install-from-backup.sh` | Same, but pulls all mirror packages from a full GitHub mirror backup (mirror integrity verified) |
| `install-zjmf-cloud_new.go` | Installer source (open-source; network call target made configurable) |
| `wrangler.toml` | Workers deploy config |

---

## Deploy the Workers (the HTTP API)

### One-click

[![Deploy to Cloudflare Workers](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/FenhaoLost/zjmf)

Or manually:

```bash
git clone https://github.com/FenhaoLost/zjmf.git
cd zjmf && npm install && npx wrangler login && npx wrangler deploy
```

Public instance: `https://zjmf-auth-api.fenhaolost.workers.dev`

---

## Use it: rebuild the installer to talk to YOUR Workers

The installer binary contains a hardcoded HTTP endpoint address. The install helper script rebuilds it with your Workers URL substituted in.

### Quick start

```bash
wget https://raw.githubusercontent.com/FenhaoLost/zjmf/main/install.sh \
  -O install.sh && chmod +x install.sh && ./install.sh
```

### With your own Workers

```bash
ENDPOINT_HOST=your-workers.workers.dev ./install.sh
```

### From the full GitHub mirror backup (no external mirror needed)

```bash
wget https://raw.githubusercontent.com/FenhaoLost/zjmf/main/install-from-backup.sh \
  -O install.sh && chmod +x install.sh && ./install.sh
```

---

## Endpoints implemented

All return static JSON of the format observed on the wire:

| Path | Purpose |
|------|---------|
| `/app/api/ip` | Return requester's public IP |
| `/app/api/auth` | Static JSON |
| `/app/api/toggle_version` | Static JSON |
| `/app/api/auth_update` | Static JSON |
| `/app/api/auth_complete` | Static JSON |
| `/app/api/auth_rc` | Static JSON |
| `/app/api/auth_rc_plugin` | Static JSON |
| `/app/api/auth_image_download` | Static JSON |
| `/app/api/get_new_version` | Static JSON |
| `/app/api/get_version` | Static JSON |
| `/app/api/get_image_version` | Static JSON |
| `/app/api/get_images` | Static JSON |
| `/market/index` | Static JSON |
| `/api/auth/version` | Static JSON |
| `/api/auth/check` | Static JSON |

---

## License

All original TypeScript / shell / Go code in this repository is released under MIT. Non-commercial use only.
