# pg-backup-rclone

Scheduled **PostgreSQL** backups to Google Drive (via [rclone](https://rclone.org/)) in a Docker image. Add a `db-backup` service to any Docker Compose stack.

## Features

- In-container scheduling with [supercronic](https://github.com/aptible/supercronic) (`BACKUP_CRON`)
- Upload to Google Drive or any rclone remote
- Local volume retention (`BACKUP_KEEP_DAYS`)
- Remote retention (`RCLONE_KEEP_DAYS`)
- Backup all databases on an instance (`BACKUP_ALL_DATABASES=true`)
- One-shot mode for manual runs (`RUN_ONCE=true`)
- Dump format compatible with standard `pg_restore` / `psql` restore

## Quick start

### 1. Configure rclone (once per server)

```bash
rclone config   # create remote named e.g. "gdrive"
rclone listremotes   # use this name for RCLONE_REMOTE
```

Default config path: `~/.config/rclone/rclone.conf` (e.g. `/home/aztech/.config/rclone/rclone.conf`).

Mount the **directory** (not the file — Docker creates a folder if the file path is missing):

```yaml
environment:
  RCLONE_CONFIG: /config/rclone/rclone.conf
volumes:
  - ${RCLONE_CONFIG_DIR:-/home/aztech/.config/rclone}:/config/rclone:ro
```

Optional in project `.env`:

```env
RCLONE_CONFIG_DIR=/home/aztech/.config/rclone
RCLONE_REMOTE=gdrive
```

### 2. Add service to your `docker-compose.yml`

```yaml
services:
  db-backup:
    build: /path/to/pg-backup-rclone
    image: pg-backup-rclone:local
    profiles: ["backup"]
    restart: unless-stopped
    env_file: [.env]
    environment:
      DB_HOST: db
      DB_PORT: "5432"
      DB_USER: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_NAME: ${POSTGRES_DB}
      BACKUP_ALL_DATABASES: "true"
      BACKUP_CRON: "0 3 * * 0"
      RCLONE_REMOTE: gdrive
      RCLONE_PATH: Backups/my-project
    volumes:
      - ${RCLONE_CONFIG_DIR:-/home/aztech/.config/rclone}:/config/rclone:ro
      - db_backup_data:/backups
    networks: [app-network]
    depends_on: [db]

volumes:
  db_backup_data:
```

### 3. Run

```bash
docker compose --profile backup up -d
docker compose run --rm -e RUN_ONCE=true -e SCHEDULE_ENABLED=false db-backup
docker compose logs -f db-backup
```

See [docker-compose.example.yml](docker-compose.example.yml) and [.env.example](.env.example).

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` / `PGHOST` | `db` | PostgreSQL host |
| `DB_PORT` / `PGPORT` | `5432` | PostgreSQL port |
| `DB_USER` / `PGUSER` | — | PostgreSQL user |
| `DB_PASSWORD` / `PGPASSWORD` | — | PostgreSQL password |
| `DB_NAME` / `PGDATABASE` | — | Single database (when `BACKUP_ALL_DATABASES=false`) |
| `BACKUP_ALL_DATABASES` | `false` | Dump every user database on the server |
| `PGDUMP_EXTRA` | `--clean --if-exists --no-owner --no-acl` | Extra `pg_dump` flags |
| `BACKUP_CRON` | `0 3 * * 0` | Cron schedule (weekly Sunday 03:00) |
| `SCHEDULE_ENABLED` | `true` | `false` = run once and exit |
| `RUN_ONCE` | `false` | Force one-shot backup |
| `BACKUP_ON_START` | `false` | Run backup when container starts |
| `BACKUP_DIR` | `/backups` | Local backup directory |
| `BACKUP_KEEP_DAYS` | `7` | Delete local run folders older than N days |
| `UPLOAD_ENABLED` | `true` | Set `false` for local-only |
| `RCLONE_CONFIG` | `/config/rclone.conf` | Path to rclone config inside container |
| `RCLONE_REMOTE` | `gdrive` | rclone remote name |
| `RCLONE_PATH` | `Backups/default` | Remote folder prefix |
| `RCLONE_KEEP_DAYS` | `30` | Delete remote files older than N days |

## Backup layout

```
/backups/
  20260516_030001/
    your_db_name.sql.gz
    your_db_name_2.sql.gz
```

Remote: `{RCLONE_REMOTE}:{RCLONE_PATH}/{timestamp}/` plus `latest/` mirror.

## Restore

```bash
gunzip -c your_db_name.sql.gz | docker compose exec -T db psql -U user -d your_db_name
```

## Build

```bash
docker build -t pg-backup-rclone:local .
```

## Troubleshooting

Backup logs go to `docker compose logs db-backup` (stdout).

| Symptom | Fix |
|---------|-----|
| `rclone config not found` | Set `RCLONE_CONFIG_DIR` to the host rclone folder; mount dir not file |
| `not a directory` / mount error | Host path was missing — Docker created a directory named `rclone.conf`; remove it and mount `~/.config/rclone` instead |
| Google Drive `404: File not found` | Almost always **rclone scope** or **Shared drive** config — see below |
| `read-only file system` on rclone.conf | Config copied to writable `/var/lib/rclone/rclone.conf` each backup |
| Host `lsd` works, container fails | Do not set `RCLONE_CONFIG` in compose — use `RCLONE_CONFIG_SOURCE` only; rebuild image |

### Google Drive 404 — fix on the host

Run as the user whose config you mount (`aztech`):

```bash
rclone --config ~/.config/rclone/rclone.conf listremotes
rclone --config ~/.config/rclone/rclone.conf lsd gdrive:
```

If `lsd gdrive:` fails with 404:

1. **Re-authorize with full Drive scope** (not `drive.file`):
   ```bash
   rclone config reconnect gdrive
   ```
   When asked for scope, pick **full access** (`drive`). `drive.file` cannot list/create arbitrary folders → 404.

2. **Shared drive (Google Workspace):** edit `~/.config/rclone/rclone.conf` and set `team_drive = <shared_drive_id>`, or set in compose:
   ```env
   RCLONE_DRIVE_ROOT_FOLDER_ID=<folder_id_from_drive_url>
   ```

3. **Smoke test** after reconnect:
   ```bash
   rclone mkdir gdrive:backups-test
   rclone rmdir gdrive:backups-test
   ```

Then recreate `db-backup` container.
| `rclone config not readable` | Image runs as `root`; keep `chmod 600` on the host file |
| `cannot connect to PostgreSQL` | Check `DB_HOST=db`, same compose network, `DB_PASSWORD` matches `db` service |
| `exit status 1` with no detail | Rebuild image after updates; run `docker compose run --rm -e RUN_ONCE=true -e SCHEDULE_ENABLED=false db-backup` |

Test without upload:

```bash
docker compose run --rm -e RUN_ONCE=true -e SCHEDULE_ENABLED=false -e UPLOAD_ENABLED=false db-backup
```

## Security

- Do not commit `rclone.conf` or `.env` with passwords.
- Mount rclone config read-only.

## License

MIT
