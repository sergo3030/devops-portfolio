# The portfolio API as a container image. It runs on AWS Lambda behind the Lambda Web
# Adapter and also as a plain container (Compose smoke test in CI).
#
# Build from the repository root:  docker build -f app/Dockerfile .
# Every base image is pinned by digest. Dependabot (docker ecosystem) keeps them current.

# ------------------------------------------------------------------ tool images
FROM ghcr.io/astral-sh/uv:0.13.5@sha256:32a7bb39b496babbd997b0a39a4d66c126bdaf5661b302bf6f06abda8deca6ff AS uv
FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 AS lwa

# ------------------------------------------------------------------ content stage
# Builds the published content (approved lines only). The private denylist cannot run in
# CI, so the content must already have passed it locally, where the pre-commit hook runs it.
FROM python:3.13-slim@sha256:cf50a4f6ac4f026458b08d5222023d700ac806410dff5e9ca8728fa44f2b850f AS content
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/content-venv
WORKDIR /build
COPY app/pyproject.toml app/uv.lock ./
RUN uv sync --locked --only-group content --no-install-project
COPY content/content.yaml content/allowed-numbers.txt ./content/
COPY content/schema/content.schema.json ./content/schema/
COPY scripts/check_content.py ./scripts/
RUN /opt/content-venv/bin/python scripts/check_content.py \
    --allow-missing-denylist --build /build/content.public.json

# ------------------------------------------------------------------ builder stage
# The runtime dependencies only, compiled to bytecode: the root filesystem is read-only on
# Lambda, so nothing can be compiled at run time.
FROM python:3.13-slim@sha256:cf50a4f6ac4f026458b08d5222023d700ac806410dff5e9ca8728fa44f2b850f AS builder
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /build
COPY app/pyproject.toml app/uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

# ------------------------------------------------------------------ runtime stage
FROM python:3.13-slim@sha256:cf50a4f6ac4f026458b08d5222023d700ac806410dff5e9ca8728fa44f2b850f AS runtime

# Set by the build: CI uses 0.0.0-dev and the commit, the release workflow uses the git tag.
ARG APP_VERSION=0.0.0-dev
ARG GIT_SHA=

LABEL org.opencontainers.image.title="portfolio-api" \
      org.opencontainers.image.description="Read-only API that serves the portfolio content" \
      org.opencontainers.image.source="https://github.com/sergo3030/devops-portfolio" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

# The adapter turns Lambda invocations into HTTP requests to this app. It is inert outside
# Lambda. Readiness: /health must answer 200, and a broken start fails after 8 seconds
# instead of waiting for ever.
COPY --from=lwa /lambda-adapter /opt/extensions/lambda-adapter

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:${PATH}" \
    HOST=0.0.0.0 \
    PORT=8080 \
    AWS_LWA_PORT=8080 \
    AWS_LWA_READINESS_CHECK_PATH=/health \
    AWS_LWA_READINESS_CHECK_HEALTHY_STATUS=200 \
    AWS_LWA_READINESS_CHECK_TIMEOUT_SECONDS=8 \
    CONTENT_FILE=/app/content.public.json \
    APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA}

# A non-root user. Files stay root-owned and world-readable, because Lambda runs the code as
# its own default user, which only needs to read them.
#
# pip is removed in the same step. It only installs packages, and every dependency is copied in
# from the builder stage, so nothing at run time needs it. It also bundles copies of certifi,
# urllib3, msgpack and setuptools, which the image scan reports whenever one of them has an
# advisory. Removing it removes those findings, a tool an attacker could use, and some size.
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin app \
    && python -m pip uninstall --yes pip

COPY --from=builder /opt/venv /opt/venv
WORKDIR /app
COPY app/portfolio_api ./portfolio_api
COPY --from=content /build/content.public.json ./content.public.json
RUN python -m compileall -q /app/portfolio_api

USER 10001
EXPOSE 8080

# Plain Docker and Compose use this. Lambda ignores it. It is a small Python module instead
# of curl, which the slim image does not have and would only add attack surface and size.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-m", "portfolio_api.healthcheck"]

CMD ["python", "-m", "portfolio_api.main"]
