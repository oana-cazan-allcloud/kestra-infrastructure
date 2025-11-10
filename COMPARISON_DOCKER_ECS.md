# Comparison: Docker Compose vs ECS Task Definition

## Summary
❌ **They do NOT fully match** - Several important differences exist

---

## 1️⃣ PostgreSQL Container

### ✅ Matches:
- Image: `postgres:17` ✅
- Environment: `POSTGRES_DB: kestra`, `POSTGRES_USER: kestra` ✅
- Volume mount: `/var/lib/postgresql/data` ✅
- Health check: `pg_isready` ✅

### ❌ Differences:
- **Password**: 
  - Docker Compose: Hardcoded `POSTGRES_PASSWORD: k3str4`
  - ECS: Uses Secrets Manager (`kestra/postgres`)
- **Health check command**:
  - Docker Compose: `pg_isready -d $${POSTGRES_DB} -U $${POSTGRES_USER}`
  - ECS: `pg_isready -U kestra` (simpler, no DB check)

---

## 2️⃣ Git-Sync Container

### ✅ Matches:
- Image: `registry.k8s.io/git-sync/git-sync:v4.4.2` ✅
- User: `root` ✅
- Environment: `GITSYNC_ROOT: /git`, `GITSYNC_LINK: repo`, `GITSYNC_PERIOD: 10s`, `GITSYNC_MAX_FAILURES: -1` ✅
- Volume mount: `/git` ✅

### ❌ Differences:
- **Repository URL**:
  - Docker Compose: `git@github.com:oana-cazan-allcloud/cargo-partners.git` (SSH)
  - ECS: `https://github.com/oana-cazan-allcloud/cargo-partners.git` (HTTPS)
- **Branch reference**:
  - Docker Compose: `GITSYNC_REF: main`
  - ECS: `GITSYNC_BRANCH: main` (different env var name)
- **SSH Configuration**:
  - Docker Compose: Has SSH key mounts (`~/.ssh/id_rsa`, `~/.ssh/known_hosts`) and SSH env vars
  - ECS: Uses Secrets Manager for credentials (`GITSYNC_USERNAME`, `GITSYNC_PASSWORD`)
- **Missing in ECS**:
  - `GITSYNC_SSH_KEY_FILE`
  - `GITSYNC_SSH_KNOWN_HOSTS`
  - `GITSYNC_SSH_KNOWN_HOSTS_FILE`
  - `GITSYNC_ADD_USER`

---

## 3️⃣ Repo-Syncer Container

### ✅ Matches:
- Image: `alpine:3.18` ✅
- Entrypoint: `["/bin/sh", "-c"]` ✅
- Command logic: Same rsync and inotify logic ✅
- Volume mounts: `/git` (ro), `/repo` ✅

### ⚠️ Minor Differences:
- **Command formatting**:
  - Docker Compose: Includes timestamps in echo statements
  - ECS: Simpler echo statements without timestamps
- **Logging**: Both work, Docker Compose is more verbose

---

## 4️⃣ Kestra Container

### ✅ Matches:
- Image: `kestra/kestra:latest` ✅
- User: `root` ✅
- Command: `server standalone --no-tutorials` ✅
- Port: `8080` ✅
- Volume mounts: `/repo` (ro), `/app/storage` ✅
- Database config: PostgreSQL connection ✅

### ❌ Major Differences:

#### **Storage Type**:
- Docker Compose: `storage.type: local` with `basePath: "/app/storage"`
- ECS: `KESTRA_STORAGE_TYPE: s3` with S3 bucket

#### **Configuration Method**:
- Docker Compose: Uses `KESTRA_CONFIGURATION` YAML block
- ECS: Uses individual environment variables (`KESTRA_DATABASE_JDBC_URL`, etc.)

#### **Docker Socket**:
- Docker Compose: Mounts `/var/run/docker.sock:/var/run/docker.sock`
- ECS: **NOT AVAILABLE** (security restriction) - Uses ECS Executor instead

#### **Temporary Directory**:
- Docker Compose: Mounts `/tmp/kestra-wd:/tmp/kestra-wd`
- ECS: Uses container's tmpfs (not explicitly mounted)

#### **Watch Configuration**:
- Docker Compose: `micronaut.io.watch.paths: ["/repo/examples/flows"]`
- ECS: **NOT CONFIGURED** in environment variables

#### **Basic Auth**:
- Docker Compose: Commented out (disabled)
- ECS: Not configured

#### **Port 8081**:
- Docker Compose: Exposes port `8081` (metrics)
- ECS: Only exposes `8080`

---

## 🔧 Recommendations to Align

### 1. **Git-Sync**: Update ECS to match Docker Compose
```typescript
// Change HTTPS to SSH
GITSYNC_REPO: 'git@github.com:oana-cazan-allcloud/cargo-partners.git'

// Change GITSYNC_BRANCH to GITSYNC_REF
GITSYNC_REF: 'main'  // instead of GITSYNC_BRANCH

// Add SSH configuration (if using SSH keys in ECS)
// Note: ECS would need SSH keys mounted differently than Docker Compose
```

### 2. **Kestra Watch Path**: Add to ECS environment
```typescript
KESTRA_WATCH_PATH: '/repo/examples/flows'
// Or configure via KESTRA_CONFIGURATION YAML
```

### 3. **Kestra Storage**: Consider making it configurable
- Docker Compose uses local storage (good for development)
- ECS uses S3 (good for production)
- Could make this configurable via environment variable

### 4. **PostgreSQL Health Check**: Align commands
- Update ECS to match Docker Compose: `pg_isready -d kestra -U kestra`

### 5. **Port 8081**: Add metrics port to ECS
```typescript
portMappings: [
  { containerPort: 8080 },
  { containerPort: 8081 }  // Add metrics port
]
```

---

## ✅ What's Already Aligned

- Container images (all match)
- User permissions (`root` where needed)
- Volume mount paths
- Basic container dependencies
- Core functionality

