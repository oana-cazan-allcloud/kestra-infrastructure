# Docker Compose Setup

This directory contains the Docker Compose configuration for running Kestra locally.

## Quick Start

1. **Copy the environment file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` with your values:**
   ```bash
   nano .env  # or use your preferred editor
   ```

3. **Start the services:**
   ```bash
   docker-compose up -d
   ```

4. **View logs:**
   ```bash
   docker-compose logs -f
   ```

5. **Stop the services:**
   ```bash
   docker-compose down
   ```

## Environment Variables

All configuration is managed through environment variables. See `.env.example` for all available variables.

### Key Variables

- **PostgreSQL**: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- **Git-Sync**: `GITSYNC_REPO`, `GITSYNC_REF`, `GITSYNC_PERIOD`
- **Kestra**: `KESTRA_URL`, `KESTRA_BASIC_AUTH_USERNAME`, `KESTRA_BASIC_AUTH_PASSWORD`
- **SSH Keys**: `SSH_KEY_PATH`, `SSH_KNOWN_HOSTS_PATH`

### Default Values

All variables have default values (shown in `.env.example`), so you can run `docker-compose up` without creating a `.env` file. However, it's recommended to create a `.env` file for production use.

## Services

- **postgres**: PostgreSQL database
- **git-sync**: Git repository synchronizer
- **repo-syncer**: File watcher and synchronizer
- **kestra**: Kestra workflow orchestration server

## Volumes

- `postgres-data`: PostgreSQL data persistence
- `kestra-data`: Kestra storage
- `git-flows`: Git repository cache
- `repo-watch`: Watched repository directory

## Access

- **Kestra UI**: http://localhost:8080
- **Kestra Metrics**: http://localhost:8081

## Notes

- The `.env` file is gitignored and should not be committed
- Use `.env.example` as a template for your `.env` file
- SSH keys are mounted from your host `~/.ssh` directory by default

