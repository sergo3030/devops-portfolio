# Task runner. On Windows, recipes run in Git Bash (not the WSL stub in System32).
set windows-shell := ["C:/Program Files/Git/bin/bash.exe", "-uc"]

# List all recipes
default:
    @just --list

# Run the secret scanner on the working tree
secrets-scan:
    gitleaks dir --no-banner --redact .

# Run all pre-commit hooks on every file
check:
    pre-commit run --all-files

# Lint GitHub Actions workflows (same checks as CI)
lint-workflows:
    uv run --project tools --locked actionlint
    uv run --project tools --locked zizmor --offline --config .github/zizmor.yml .
    uv run --project tools --locked check-jsonschema --builtin-schema vendor.dependabot .github/dependabot.yml
    ! grep -rnE 'vars\.AWS_ACCOUNT_ID|arn:aws:[a-z0-9-]*::[0-9]{12}' --exclude=ci.yml .github/workflows

# Test the image push, retry and scan scripts against fake commands (same as CI)
test-scripts:
    bash scripts/test-ecr-image.sh
    bash scripts/test-retry-and-trivy.sh
    bash scripts/test-check-release.sh
    bash scripts/test-check-site-link.sh
    bash scripts/test-verify-clean.sh
    bash scripts/test-teardown.sh
    bash scripts/test-tool-pins.sh
    bash scripts/check-tool-pins.sh

# How many runs of the ci workflow on main in a row were green (the goal in task 20 is ten)
ci-streak:
    python scripts/ci_streak.py

# Are the tools that Dependabot cannot update behind their latest release? (needs `gh` logged in)
tool-versions:
    bash scripts/tool-versions.sh

# Relative links and heading anchors in README and docs/ (also run by the Python tests in CI)
docs-check:
    python scripts/check_doc_links.py

# shellcheck for the scripts (same as CI)
lint-scripts:
    uv run --project tools --locked shellcheck -x -S warning scripts/*.sh

# Level 1 (pause the API). Previews by default; `just teardown-api apply` really does it, in a terminal
teardown-api mode="preview":
    bash scripts/teardown-api.sh {{mode}}

# Level 2 (remove AWS, after Level 1). Previews by default
teardown-aws mode="preview":
    bash scripts/teardown-aws.sh {{mode}}

# Recreate production after Level 1. Previews by default
up-prod mode="preview":
    bash scripts/up-prod.sh {{mode}}

# Read-only: what is left in the AWS account (level1 = only the bootstrap root, level2 = nothing)
verify-clean level="level2":
    bash scripts/verify-clean.sh {{level}}

# Scan IaC, workflows and Dockerfiles (same check as CI)
iac-scan:
    PYTHONUTF8=1 uv run --project tools --locked python -m checkov.main --config-file .checkov.yaml

# Scan the whole git history for secrets (same check as CI)
secrets-history:
    gitleaks git --redact --no-banner

# Format, validate and test the OpenTofu roots without credentials (same checks as CI)
tofu-check:
    tofu fmt -check -recursive -diff infra
    grep -q 'prevent_destroy = true' infra/github/repository.tf
    bash scripts/check-required-checks.sh
    for root in infra/bootstrap infra/github infra/prod; do \
      tofu -chdir="$root" init -backend=false -input=false && \
      tofu -chdir="$root" validate && \
      tofu -chdir="$root" test; \
    done

# Plan the bootstrap root from a local `aws login --profile portfolio-bootstrap` session
bootstrap-plan:
    AWS_PROFILE=portfolio-bootstrap AWS_REGION=us-east-1 tofu -chdir=infra/bootstrap plan

# Plan the github root. Needs `aws login` (state) and `gh auth login` (token, read at run time)
github-plan:
    GITHUB_TOKEN="$(gh auth token)" AWS_PROFILE=portfolio-bootstrap AWS_REGION=us-east-1 tofu -chdir=infra/github plan

# Read-only check of the repository settings the OpenTofu provider cannot manage
github-settings-check:
    @echo "private vulnerability reporting must be on, fork PR approval must cover all external contributors"
    test "$(gh api repos/sergo3030/devops-portfolio/private-vulnerability-reporting --jq .enabled)" = "true"
    test "$(gh api repos/sergo3030/devops-portfolio/actions/permissions/fork-pr-contributor-approval --jq .approval_policy)" = "all_external_contributors"
    @echo "ok"

# Lint and test the Python app (same checks as CI)
test-app:
    cd app && uv sync --locked
    cd app && uv run ruff check . ../scripts
    cd app && uv run ruff format --check . ../scripts
    cd app && uv run mypy
    cd app && uv run pytest

# Build the published content (approved lines only) that the API serves
content-build:
    uv run --project app python scripts/check_content.py --build app/content.public.json

# Run the API natively on the Lambda Web Adapter's default port (no Docker needed)
api-dev: content-build
    cd app && uv run python -m portfolio_api.main

# Lint the Dockerfile with a locally installed hadolint (container builds run in CI only)
hadolint:
    hadolint app/Dockerfile

# Export the JSON Schema of the published content (the contract between the API and the web app)
schema-export:
    cd app && uv run python -m portfolio_api.schema_export

# Build the content snapshot that the site embeds (approved lines only)
web-content:
    uv run --project app python scripts/check_content.py --build web/src/generated/content.json

# Run the site in development. Start `just api-dev` in another terminal for live data.
web-dev: web-content
    cd web && npm run dev

# End-to-end test of the built site against a running API, in the Chrome installed here.
# Start the API first, allowing the test site: CORS_ALLOW_ORIGINS=http://127.0.0.1:4173 just api-dev
web-e2e: web-content
    cd web && npm run e2e

# All web checks, the same as CI
web-check: web-content
    cd web && npm ci && npm run lint && npm run format && npm run typecheck && npm test && npm run build && npm run check:size && npm run check:page

# Check the public content including the PRIVATE denylist (not available in CI)
content-check:
    uv run --project app python scripts/check_content.py

# Show installed tool versions
versions:
    git --version
    gh --version | head -1
    uv --version
    node --version
    tofu version | head -1
    gitleaks version
    actionlint -version | head -1
    just --version
    pre-commit --version
