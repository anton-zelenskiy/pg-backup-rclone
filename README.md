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
mkdir -p /opt/db-backups/config
rclone config   # create remote named e.g. "gdrive"
cp ~/.config/rclone/rclone.conf /opt/db-backups/config/rclone.conf
chmod 600 /opt/db-backups/config/rclone.conf
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
      - /opt/db-backups/config/rclone.conf:/config/rclone.conf:ro
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

## Security

- Do not commit `rclone.conf` or `.env` with passwords.
- Mount rclone config read-only.

## License

MIT
