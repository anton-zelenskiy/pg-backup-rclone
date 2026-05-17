# Publish to Docker Hub

How to build and publish **pg-backup-rclone** to [Docker Hub](https://hub.docker.com/).

## Prerequisites

- Docker Hub account
- Docker installed locally or on CI
- Repository created on Hub: `https://hub.docker.com/r/YOUR_USER/pg-backup-rclone`

Replace `YOUR_USER` with your Docker Hub username in all commands below.

## 1. Log in

```bash
docker login
```

Use your Docker Hub username and password, or an [access token](https://hub.docker.com/settings/security) (recommended).

## 2. Build the image

From the repository root:

```bash
cd /path/to/pg-backup-rclone

docker build -t YOUR_USER/pg-backup-rclone:latest .
```

Optional version tag:

```bash
VERSION=1.0.0
docker build -t YOUR_USER/pg-backup-rclone:latest -t YOUR_USER/pg-backup-rclone:${VERSION} .
```

## 3. Push to Docker Hub

```bash
docker push YOUR_USER/pg-backup-rclone:latest
docker push YOUR_USER/pg-backup-rclone:1.0.0   # if tagged
```

## 4. Use the published image

In your project's `docker-compose.yml`:

```yaml
services:
  db-backup:
    image: YOUR_USER/pg-backup-rclone:latest
    # remove build: section if you only pull from Hub
    profiles: ["backup"]
    restart: unless-stopped
    # ... rest of db-backup config
```

Pull on the server:

```bash
docker compose --profile backup pull db-backup
docker compose --profile backup up -d
```

## 5. Multi-arch build (optional)

For AMD64 and ARM64 (e.g. Raspberry Pi, Apple Silicon servers):

```bash
docker buildx create --use --name multi 2>/dev/null || docker buildx use multi

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t YOUR_USER/pg-backup-rclone:latest \
  -t YOUR_USER/pg-backup-rclone:1.0.0 \
  --push \
  .
```

## 6. CI (GitHub Actions sketch)

On release tag, build and push using repository secrets:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

Typical workflow steps: checkout → `docker/login-action` → `docker/build-push-action` with `push: true`.

## Security

- Only the **image** is published to Docker Hub
- OAuth tokens and `rclone.conf` stay on the server (`~/.config/rclone/`)
- Never commit `client_secret` or `rclone.conf` to git

[← Back to README](../README.md)
