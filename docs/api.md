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
  security.py  the security-headers and read-only middlewares
  main.py      lifespan, the module-level `app`, the middlewares and `uvicorn.run` under __main__
```

`app` is a plain module-level object. Routers live in their own module and are attached with
`include_router`, and the content is held by a module-level store that the lifespan fills and
clears. The route reads it through the `get_content` dependency, which tests can override.

## Hardening (task 16, D43)

The API is public and has no authentication, so it is built to do as little as possible.

**Read-only** (`ReadOnlyMiddleware`, checked before anything else sees a request):

| Request | Answer |
|---|---|
| a method other than `GET` and `OPTIONS` | `405`, with `Allow: GET, OPTIONS` |
| a body (a `Content-Length` other than 0, or `Transfer-Encoding`) | `413` |
| headers larger than 16 KB in total | `431` |
| a URL (path and query) longer than 2048 bytes | `414` |

uvicorn runs without the `server:` banner. Its own header limit (16 KB) only catches a request
that arrives in pieces, which is why the middleware checks sizes too (found when the smoke checks
were run against the real server: a 20 KB header was accepted by uvicorn alone).

**Security headers** (`SecurityHeadersMiddleware`) on every response, errors and CORS answers
included: `X-Content-Type-Options: nosniff`, `Content-Security-Policy: default-src 'none';
frame-ancestors 'none'`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`,
`Strict-Transport-Security: max-age=31536000`. A response without its own `Cache-Control` gets
`no-store`; only `/content` is cacheable (`public, max-age=300`).

**CORS** lets one website read the API in a browser. `CORS_ALLOW_ORIGINS` is a comma-separated
list of origins (scheme, host and optional port, lower case, no path and no wildcard; plain
`http` only for `localhost` and `127.0.0.1`). An invalid value stops the start-up. The image sets
`https://sergo3030.github.io`. Methods are `GET` and `OPTIONS`, the only extra request headers are
`Accept` and `Cache-Control`, credentials are never allowed, and a preflight is cached for 10
minutes. Without the variable (local development) there are no CORS headers at all.

**CORS is not access control.** It only stops other websites' scripts from reading the API in a
visitor's browser. Anyone can still call the URL with `curl`. What bounds abuse is the concurrency
cap of 2 on the function, the rule that a request can carry nothing, and the budget alert.

**No secrets in the image.** `.dockerignore` is an allowlist, the smoke test checks that the image
sets no secret-looking variable, has none of the usual secret files and that `/app` holds only the
app and its content, and Trivy scans the image for secrets before it is pushed (D39). A test pins
the `.dockerignore` as an allowlist.

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

The image also sets `CORS_ALLOW_ORIGINS=https://sergo3030.github.io` (see Hardening).

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
