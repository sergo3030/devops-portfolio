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
    actionlint
    uvx zizmor@1.30.1 --offline --config .github/zizmor.yml .
    uvx check-jsonschema@0.38.2 --builtin-schema vendor.dependabot .github/dependabot.yml

# Scan IaC, workflows and Dockerfiles (same check as CI)
iac-scan:
    PYTHONUTF8=1 uvx --from checkov==3.3.26 checkov --config-file .checkov.yaml

# Scan the whole git history for secrets (same check as CI)
secrets-history:
    gitleaks git --redact --no-banner

# Format, validate and test the OpenTofu roots without credentials (same checks as CI)
tofu-check:
    tofu fmt -check -recursive -diff infra
    for root in infra/bootstrap; do \
      tofu -chdir="$root" init -backend=false -input=false && \
      tofu -chdir="$root" validate && \
      tofu -chdir="$root" test; \
    done

# Lint and test the Python app (same checks as CI)
test-app:
    cd app && uv sync --locked
    cd app && uv run ruff check .
    cd app && uv run ruff format --check .
    cd app && uv run pytest

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
