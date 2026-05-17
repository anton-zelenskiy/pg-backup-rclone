# Google Cloud + rclone setup

Configure Google Drive and rclone for **pg-backup-rclone**. Do this **once per server** as the user that owns the config (e.g. `aztech`).

## Step 1 — Google Cloud project

1. Open [Google Cloud Console](https://console.cloud.google.com/).
2. Create a project (or select an existing one), e.g. `my-backups`.
3. Enable billing if required (Drive API usage for personal backups is usually within free tier).

## Step 2 — Enable Google Drive API

1. **APIs & Services → Library**
2. Search for **Google Drive API**
3. Click **Enable**

## Step 3 — OAuth consent screen

1. **APIs & Services → OAuth consent screen**
2. User type:
  - **External** — personal Gmail
  - **Internal** — Google Workspace (only users in your org)
3. Fill required fields (app name, support email).
4. **Scopes → Add or remove scopes** → add:
  - `https://www.googleapis.com/auth/drive` (full Drive access)
5. If the app is in **Testing**:
  - **Test users** → add your Google account email
  - Re-auth is required every 7 days until the app is published (fine for private server use)
6. Save.

## Step 4 — OAuth client credentials

1. **APIs & Services → Credentials → Create credentials → OAuth client ID**
2. Application type: **Desktop app** (recommended for rclone on a server)
3. Name: e.g. `rclone-backups`
4. Create → copy **Client ID** and **Client secret** (you can also let rclone use its built-in client by leaving them blank during `rclone config`)

## Step 5 — Install rclone on the server

```bash
curl https://rclone.org/install.sh | sudo bash
rclone version
```

## Step 6 — Configure the `gdrive` remote

```bash
rclone config
```

Suggested answers:


| Prompt                                           | Value                                                      |
| ------------------------------------------------ | ---------------------------------------------------------- |
| New remote                                       | `n`                                                        |
| Name                                             | `gdrive`                                                   |
| Storage                                          | `drive` (Google Drive)                                     |
| client_id                                        | Paste from step 4, or **Enter** for rclone default         |
| client_secret                                    | Paste from step 4, or **Enter** for rclone default         |
| scope                                            | `**1` — Full access (`drive`)** — required                 |
| service_account_file                             | **Enter** (skip)                                           |
| Edit advanced config?                            | `n` (unless you need Shared drives)                        |
| Use auto config?                                 | `n` on headless server                                     |
| Copy the URL → open in browser → paste auth code | follow prompts                                             |
| Configure as Shared Drive?                       | `n` for personal My Drive, `y` for Workspace Shared drives |
| **root_folder_id**                               | **Leave empty** (press Enter)                              |


**Do not set `root_folder_id = xxxx`** — that field must be a **folder ID** from the Drive URL (`https://drive.google.com/drive/folders/1ABC...`), not a folder name.

Config file location: `~/.config/rclone/rclone.conf`

Example (no secrets shown):

```ini
[gdrive]
type = drive
scope = drive
# client_id / client_secret / token added by rclone config
# Do NOT set: root_folder_id = xxxx
```

## Step 7 — Verify on the host

```bash
rclone listremotes
# gdrive:

rclone lsd gdrive:
rclone mkdir gdrive:backups-test
rclone rmdir gdrive:backups-test
```

All commands must succeed before using Docker.

## Step 8 — Reconnect / refresh token (later)

Use a **colon** after the remote name:

```bash
rclone config reconnect gdrive:
```

Or edit via menu:

```bash
rclone config
# e) Edit existing remote → gdrive
```

## Shared drives (Google Workspace)

If backups must go to a **Shared drive**:

1. `rclone backend drives gdrive:` — note the drive ID
2. Edit `~/.config/rclone/rclone.conf`:

```ini
[gdrive]
type = drive
scope = drive
team_drive = YOUR_SHARED_DRIVE_ID
```

Or set in compose: `RCLONE_DRIVE_ROOT_FOLDER_ID=<folder_id>`.

## Headless server

When `Use auto config?` is `n`, rclone prints a URL. Open it on any machine where you can log into Google, then paste the verification code back into the SSH session.

## Mount config in Docker Compose

Mount the **directory**, not a single file:

```yaml
environment:
  RCLONE_CONFIG_SOURCE: /config/rclone/rclone.conf
  RCLONE_REMOTE: gdrive
  RCLONE_PATH: backups/my-project
volumes:
  - ${RCLONE_CONFIG_DIR:-/home/<user>/.config/rclone}:/config/rclone:ro
```

Optional in project `.env`:

```env
RCLONE_CONFIG_DIR=/home/<user>/.config/rclone
```

Use `RCLONE_CONFIG_SOURCE`, not `RCLONE_CONFIG`. The image copies the mounted file to a writable path on each backup.

## Troubleshooting


| Symptom                                   | Fix                                                           |
| ----------------------------------------- | ------------------------------------------------------------- |
| `rclone lsd gdrive:` → 404                | Remove bad `root_folder_id`; use scope `drive`; see below     |
| `reconnect` says `local: doesn't support` | Use `rclone config reconnect gdrive:` **with colon**          |
| Host `lsd` works, container fails         | Use `RCLONE_CONFIG_SOURCE` in compose only; rebuild image     |
| `read-only file system` on rclone.conf    | Image copies config to `/var/lib/rclone/rclone.conf` each run |


### Google Drive 404

```bash
rclone --config ~/.config/rclone/rclone.conf listremotes
rclone --config ~/.config/rclone/rclone.conf lsd gdrive:
```

If `lsd gdrive:` fails:

1. Remove `root_folder_id = xxxx` (or any non-ID value) from `rclone.conf`
2. Reconnect with full scope: `rclone config reconnect gdrive:`
3. For Shared drives, set `team_drive` or `RCLONE_DRIVE_ROOT_FOLDER_ID`

Verify inside the container:

```bash
docker compose exec db-backup rclone lsd gdrive: --config /var/lib/rclone/rclone.conf
docker compose exec db-backup grep -E '^(scope|root_folder_id|team_drive)' /config/rclone/rclone.conf
```

## Security

- Do not commit `rclone.conf` or OAuth secrets to git
- `chmod 600 ~/.config/rclone/rclone.conf`
- Rotate Google OAuth client secret if leaked

[← Back to README](../README.md)