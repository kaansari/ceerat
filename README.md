# ceerat

This repository is the Render deployment root for Ceerat. The application code lives in private Git submodules and is built through the root `go.work`.

## Modules

- `apps-repo/ai/ceerat-agent-service`
- `apps-repo/apps/ceerat-web-ui`
- `apps-repo/apps/ceerat-admin-ui`
- `apps-repo/apps/ceerat-customer-ui`
- `services-repo/services/ceerat-user-service`
- `contracts-repo/packages/ceerat-contracts`
- `atscrawler`

## Local setup

### Prerequisites

- Go `1.26.2` or the Go version listed in `go.work`
- Git access to the private submodules
- PostgreSQL 14 command-line tools (`pg_ctl`, `initdb`, `psql`)
- Docker or Colima if you want local Typesense
- An OpenAI API key if you want to use the agent service

On macOS with Homebrew:

```sh
brew install go postgresql@14
brew install --cask docker
```

If you use Colima instead of Docker Desktop:

```sh
brew install colima docker
colima start
```

### Clone and initialize

```sh
git clone <repo-url> ceerat
cd ceerat
git submodule update --init --recursive
```

The root repo is only the deployment/build wrapper. The application source is in:

- `apps-repo`
- `services-repo`
- `contracts-repo`
- `atscrawler`

### Environment files

Create a local `.env` file in the repo root. Do not commit it.

```sh
cat > .env <<'EOF'
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4.1-mini

CEERAT_ENV=development
CEERAT_PGDATA=.local/postgres-14

CEERAT_DB_HOST=localhost
CEERAT_DB_PORT=55434
CEERAT_DB_USER=postgres
CEERAT_DB_PASSWORD=postgres
CEERAT_DB_NAME=postgres
DB_HOST=${CEERAT_DB_HOST}
DB_PORT=${CEERAT_DB_PORT}
DB_USER=${CEERAT_DB_USER}
DB_PASSWORD=${CEERAT_DB_PASSWORD}
DB_NAME=${CEERAT_DB_NAME}

CEERAT_SERVICE_PORT=50051
CEERAT_USER_ADMIN_PORT=8081
CEERAT_AGENT_PORT=8088
CEERAT_WEB_UI_PORT=3000
CEERAT_ADMIN_UI_PORT=3010
CEERAT_CUSTOMER_UI_PORT=3005

USER_SERVICE_ADDR=localhost:${CEERAT_SERVICE_PORT}
CEERAT_USER_SERVICE_ADDR=${USER_SERVICE_ADDR}
CEERAT_API_BASE_URL=${USER_SERVICE_ADDR}
CEERAT_AGENT_BASE_URL=http://localhost:${CEERAT_AGENT_PORT}
CEERAT_ADMIN_API_BASE_URL=http://localhost:${CEERAT_USER_ADMIN_PORT}

CEERAT_JWT_SECRET=dev-secret
JWT_SECRET=${CEERAT_JWT_SECRET}
JWT_AUTH_ENABLED=true

INITIAL_ADMIN_EMAIL=admin@local
INITIAL_ADMIN_PASSWORD=admin
INITIAL_ADMIN_NAME="Local Admin"

TYPESENSE_HOST=localhost
TYPESENSE_PORT=8108
TYPESENSE_PROTOCOL=http
TYPESENSE_API_KEY=dev_typesense_key
TYPESENSE_COLLECTION_JOBS=jobs
TYPESENSE_DISABLED=false
EOF
```

Create `typesense.env` if you want local job search indexing/search:

```sh
cat > typesense.env <<'EOF'
TYPESENSE_HOST=localhost
TYPESENSE_PORT=8108
TYPESENSE_PROTOCOL=http
TYPESENSE_API_KEY=dev_typesense_key
TYPESENSE_COLLECTION_JOBS=jobs
TYPESENSE_DISABLED=false
EOF
```

To run without Typesense, set this in `typesense.env`:

```text
TYPESENSE_DISABLED=true
```

### Build and test

Download module dependencies:

```sh
make deps
```

Run all module tests:

```sh
make test
```

Build all Render service binaries into `./bin`:

```sh
make build
```

Recommended pre-push check:

```sh
make local-check
```

Build a single service:

```sh
make render-build SERVICE=user-service
make render-build-web-ui
make render-build-ats-crawler
```

### Run locally

Start the full local stack:

```sh
make local-start
```

This builds the same binaries Render uses, then starts:

- local Postgres
- local Typesense, unless disabled
- `ceerat-user-service`
- `ceerat-agent-service`
- `ceerat-web-ui`
- `ceerat-admin-ui`
- `ceerat-customer-ui`

The ATS crawler is not a long-running local service. After the user service is running, import configured Greenhouse jobs with:

```sh
./bin/ceerat-ats-crawler \
  -greenhouse-config=atscrawler/config/greenhouse-companies.csv \
  -import \
  -ceerat-service-addr="$USER_SERVICE_ADDR"
```

Check status:

```sh
make local-status
```

Stop everything:

```sh
make local-stop
```

Useful script options:

```sh
./start-stack.sh --skip-build
./start-stack.sh --with-tests
./start-stack.sh --skip-typesense
./stop-stack.sh --keep-db
./stop-stack.sh --keep-typesense
```

### Local URLs and ports

- Web UI: `http://localhost:3000`
- Admin UI: `http://localhost:3010`
- Customer UI: `http://localhost:3005`
- Agent service: `http://localhost:8088`
- User service gRPC: `localhost:50051`
- User admin API: `http://localhost:8081`
- Postgres: `localhost:55434`
- Typesense: `http://localhost:8108`

### Local files

The local scripts write runtime files under:

- `.local/` for local Postgres data
- `.run/` for pid files
- `logs/` for service logs
- `bin/` for built binaries

These paths are ignored by git.

### Troubleshooting

If Postgres tools are installed somewhere else, set:

```sh
export PG_CTL=/path/to/pg_ctl
export INITDB=/path/to/initdb
export PSQL=/path/to/psql
```

If Docker is not running, Typesense startup is skipped. Start Docker/Colima or set `TYPESENSE_DISABLED=true`.

If a port is already in use, either stop the conflicting process or override the matching variable in `.env`, such as `CEERAT_WEB_UI_PORT`, `CEERAT_ADMIN_UI_PORT`, `CEERAT_CUSTOMER_UI_PORT`, `CEERAT_SERVICE_PORT`, or `CEERAT_AGENT_PORT`.

Use logs for service startup failures:

```sh
tail -f logs/user-service.log
tail -f logs/agent-service.log
tail -f logs/web-ui.log
```

## Render deployment

`render.yaml` defines:

- PostgreSQL database: `ceerat-postgres`
- Private services: `ceerat-user-service`, `ceerat-agent-service`
- Web services: `ceerat-web-ui`, `ceerat-admin-ui`, `ceerat-customer-ui`
- Cron jobs: `ceerat-ats-crawler`

Create a Render Blueprint from this repository. Render runs the service-specific scripts in `scripts/` and starts the matching binary from `./bin`.

Set these secret values in Render after creating the Blueprint:

- `INITIAL_ADMIN_PASSWORD` on `ceerat-user-service`
- `OPENAI_API_KEY` on `ceerat-agent-service`
- `TYPESENSE_HOST`, `TYPESENSE_PORT`, and `TYPESENSE_API_KEY` on `ceerat-user-service` if Typesense is enabled
- `CEERAT_AGENT_TOKEN`, or `CEERAT_AGENT_EMAIL` and `CEERAT_AGENT_PASSWORD`, on `ceerat-ats-crawler`

## ATS crawler

`ceerat-ats-crawler` is deployed as a Render cron job. It builds from the `atscrawler` submodule and writes:

```text
./bin/ceerat-ats-crawler
```

The cron job runs every 30 minutes:

```text
*/30 * * * *
```

Render starts it with:

```sh
./bin/ceerat-ats-crawler \
  -greenhouse-config=atscrawler/config/greenhouse-companies.csv \
  -import \
  -ceerat-service-addr=$CEERAT_SERVICE_ADDR
```

`CEERAT_SERVICE_ADDR` is wired from `ceerat-user-service` with Render `fromService.property: hostport`, so the crawler imports jobs over the private gRPC network.

For authentication, set either:

- `CEERAT_AGENT_TOKEN`
- or `CEERAT_AGENT_EMAIL` and `CEERAT_AGENT_PASSWORD`

## Typesense

The user service reads Typesense settings from:

- `TYPESENSE_HOST`
- `TYPESENSE_PORT`
- `TYPESENSE_PROTOCOL`
- `TYPESENSE_API_KEY`
- `TYPESENSE_COLLECTION_JOBS`
- `TYPESENSE_DISABLED`

For local development, use:

```sh
docker compose --env-file typesense.env -f docker-compose.typesense.yml up -d
```

For Render production, deploy Typesense separately because Render does not provide a native managed Typesense database. Common options are:

- Typesense Cloud
- A separate Render private service using the `typesense/typesense` Docker image with a persistent disk

Then set the `ceerat-user-service` Render environment variables:

```text
TYPESENSE_HOST=<typesense host>
TYPESENSE_PORT=443
TYPESENSE_PROTOCOL=https
TYPESENSE_API_KEY=<production key>
TYPESENSE_COLLECTION_JOBS=jobs
TYPESENSE_DISABLED=false
```

If Typesense is not ready, set `TYPESENSE_DISABLED=true` so job search indexing/search is disabled without blocking the rest of the deployment.
