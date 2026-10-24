# API

A small read-only FastAPI service. It serves the published content and nothing else. It is
the container that runs on AWS Lambda behind the Lambda Web Adapter (tasks 11 and 14).

| Endpoint | Returns |
|---|---|
| `GET /health` | `{"status": "ok", "version": "...", "git_sha": "..."}`. The version is `0.0.0-dev` and `git_sha` is absent unless the build sets them. The Lambda Web Adapter readiness check points here. |
| `GET /content` | The published content (approved lines only) with `Cache-Control: public, max-age=300` |

`/docs`, `/redoc` and `/openapi.json` are off unless `ENABLE_DOCS=1`.

## Layout

```
app/portfolio_api/
  config.py    Settings, read from the environment when asked for
  models.py    Pydantic models of the published content (unknown fields rejected)
  content.py   load_content, the ContentStore singleton and the get_content dependency
  routers.py   health_router and content_router
  main.py      lifespan, the module-level `app`, and `uvicorn.run` under __main__
```

`app` is a plain module-level object. Routers live in their own module and are attached with
`include_router`, and the content is held by a module-level store that the lifespan fills and
clears. The route reads it through the `get_content` dependency, which tests can override.

## Version

The running version has one source: the environment variable `APP_VERSION`, baked into the image
as a build argument together with `GIT_SHA`. Every image built from `main` is `0.0.0-dev`; the
release workflow (`release.yml`, task 15a) builds a tagged commit again with the version of the
tag (`v1.2.3` gives `1.2.3`). `/health` and the OpenAPI document report it, so you can tell which
build is running, and the deploy checks that the live API reports the version and commit of the
image it deployed. Without the variables the app reports `0.0.0-dev`.
The `version` in `pyproject.toml` is a placeholder and is not authoritative. Both variables are
validated at start-up (a version like `1.4.2`, a lowercase hex SHA), and a test fails if a release
version is hardcoded anywhere in the package.

## Content

`just content-build` writes `app/content.public.json` (gitignored) from `content/content.yaml`,
using the checker in `scripts/check_content.py`. The lifespan validates that file with the
Pydantic models when the server starts and **refuses to start** if it is missing or invalid, so a
broken build never serves. Importing the module reads the environment but does no file I/O. A
contract test makes sure that what the build publishes is what the models accept, and a leak
guard test makes sure approval state and unapproved case studies never reach the response.

## Run it

```bash
just api-dev          # builds the content, then serves on http://127.0.0.1:8080
just test-app         # ruff, ruff format, mypy --strict, pytest
```

Environment: `CONTENT_FILE` (default `content.public.json`), `ENABLE_DOCS`, `APP_VERSION`,
`GIT_SHA`, `HOST` (default
`127.0.0.1`, a container sets `0.0.0.0`) and `PORT` (default 8080, the adapter default). The
container can also run `uvicorn portfolio_api.main:app --host 0.0.0.0 --port 8080`.

Docker is not available locally, so the container build and the Compose smoke test run in CI only.

## Container image

`app/Dockerfile` (build from the repository root with `docker build -f app/Dockerfile .`) has
four stages. A **content** stage runs the content checker and bakes `content.public.json` (the
private denylist cannot run in CI, so content must already have passed it locally through the
pre-commit hook). A **builder** stage installs the runtime dependencies only, compiled to
bytecode because the root filesystem is read-only on Lambda. The **runtime** stage copies in
the venv, the package, the JSON and the Lambda Web Adapter, and runs as a non-root user with
world-readable files. Every base image is pinned by digest, and Dependabot's docker ecosystem
keeps them current.

| Build argument | Meaning |
|---|---|
| `APP_VERSION` | The running version. CI uses `0.0.0-dev`, the release workflow (task 15a) uses the tag |
| `GIT_SHA` | The commit the image was built from |

Both become environment variables and OCI labels, and `/health` reports them. The adapter is set
up with readiness path `/health`, healthy status `200` and an 8 second readiness timeout, so a
broken start fails fast. Docker does not run on the developer's laptop, so the image is built and
tested in CI only: the `image (hadolint, build, smoke)` job lints the Dockerfile, brings the stack
up with `docker-compose.yml` (read-only root filesystem, no capabilities, no privilege
escalation, like the Lambda sandbox) and runs `scripts/smoke-test-container.sh`.

The image's `HEALTHCHECK` runs `python -m portfolio_api.healthcheck`, a small module that calls
`GET /health` on the port from the same settings as the app. It is not `curl`: the slim image has
no curl, installing it would add a package layer, attack surface and size, and Lambda ignores
`HEALTHCHECK` anyway. A module also follows a changed `PORT` and has unit tests.

What CI cannot prove, because it needs the real Lambda service (checked in task 14): the adapter
with `uvicorn`, whether Lambda honours the `USER` line, and that Lambda accepts the image
manifest. Builds switch provenance attestations off so the image is not an OCI index.
