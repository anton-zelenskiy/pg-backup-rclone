# pg-backup-rclone

Scheduled **PostgreSQL** backups to Google Drive (via [rclone](https://rclone.org/)) in a Docker image. Add a `db-backup` service to any Docker Compose stack.

## Documentation

- [Google Cloud + rclone setup](docs/google-cloud-rclone-setup.md) — OAuth, Drive API, `rclone config`, Docker mount
- [Publish to Docker Hub](docs/docker-hub.md) — build, tag, push, use published image

## Features

- In-container scheduling with [supercronic](https://github.com/aptible/supercronic) (`BACKUP_CRON`)
- Upload to Google Drive or any rclone remote
- Local volume retention (`BACKUP_KEEP_DAYS`)
- Remote retention (`RCLONE_KEEP_DAYS`) — old timestamp folders only; `latest/` is kept
- Backup all databases on an instance (`BACKUP_ALL_DATABASES=true`)
- One-shot mode for manual runs (`RUN_ONCE=true`)
- Dump format compatible with standard `pg_restore` / `psql` restore

## Quick start

1. Complete [Google Cloud + rclone setup](docs/google-cloud-rclone-setup.md) on the server.
2. Add the `db-backup` service (see below).
3. Run:

```bash
docker compose --profile backup up -d
docker compose run --rm -e RUN_ONCE=true -e SCHEDULE_ENABLED=false db-backup
docker compose logs -f db-backup
```

## Docker Compose

```yaml
services:
  db-backup:
    image: YOUR_USER/pg-backup-rclone:latest   # or build: ../pg-backup-rclone
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
      RCLONE_PATH: backups/my-project
      RCLONE_CONFIG_SOURCE: /config/rclone/rclone.conf
      BACKUP_KEEP_DAYS: "7"
      RCLONE_KEEP_DAYS: "30"
    volumes:
      - ${RCLONE_CONFIG_DIR:-/home/aztech/.config/rclone}:/config/rclone:ro
      - db_backup_data:/backups
    networks: [app-network]
    depends_on: [db]

volumes:
  db_backup_data:
```

See [docker-compose.example.yml](docker-compose.example.yml) and [.env.example](.env.example).

### Commands

```bash
docker compose --profile backup up -d
docker compose logs -f db-backup
docker compose run --rm -e RUN_ONCE=true -e SCHEDULE_ENABLED=false db-backup
docker compose run --rm -e RUN_ONCE=true -e SCHEDULE_ENABLED=false -e UPLOAD_ENABLED=false db-backup
```

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
| `BACKUP_CRON` | `0 3 * * 0` | Cron schedule (weekly Sunday 03:00 UTC) |
| `SCHEDULE_ENABLED` | `true` | `false` = run once and exit |
| `RUN_ONCE` | `false` | Force one-shot backup |
| `BACKUP_ON_START` | `false` | Run backup when container starts |
| `BACKUP_DIR` | `/backups` | Local backup directory |
| `BACKUP_KEEP_DAYS` | `7` | Delete local run folders older than N days |
| `UPLOAD_ENABLED` | `true` | Set `false` for local-only |
| `RCLONE_CONFIG_SOURCE` | `/config/rclone/rclone.conf` | Mounted read-only config on host |
| `RCLONE_REMOTE` | `gdrive` | rclone remote name (from `rclone listremotes`) |
| `RCLONE_PATH` | `Backups/default` | Folder under Drive, e.g. `backups/market-crm` |
| `RCLONE_KEEP_DAYS` | `30` | Remove remote timestamp folders older than N days |
| `RCLONE_DRIVE_ROOT_FOLDER_ID` | — | Optional Shared drive / folder root ID |
| `RCLONE_CONFIG_DIR` | — | Host path mounted to `/config/rclone` (compose only) |

## Backup layout & restore

```
gdrive:backups/market-crm/
  20260517_090800/
    market_crm.sql.gz
  latest/
    market_crm.sql.gz
```

```bash
gunzip -c market_crm.sql.gz | docker compose exec -T db psql -U market_crm -d market_crm
```

## Build (local)

```bash
docker build -t pg-backup-rclone:local .
```

To publish: [docs/docker-hub.md](docs/docker-hub.md)

## Troubleshooting

Logs: `docker compose logs db-backup`

| Symptom | Fix |
|---------|-----|
| Google Drive / rclone issues | [docs/google-cloud-rclone-setup.md](docs/google-cloud-rclone-setup.md) |
| `rclone config not found` | Set `RCLONE_CONFIG_DIR` to host `~/.config/rclone` |
| Mount error / `not a directory` | Mount directory `~/.config/rclone`, not a missing file path |
| PostgreSQL connection failed | `DB_HOST=db`, same network, password matches `db` service |
| `directory not empty` on retention | Update image — retention skips `latest/` |

## License

MIT
