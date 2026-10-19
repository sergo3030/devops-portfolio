# devops-portfolio

A deliberately over-engineered portfolio whose real goal is to demonstrate
DevOps skills: OpenTofu on AWS, keyless GitHub OIDC, secure CI, and secrets
handling.

Status: work in progress (baseline task 1). The architecture, the cost model and
the teardown procedure are described in [docs/aws-lambda-baseline-plan.md](docs/aws-lambda-baseline-plan.md).

## Quick start (Windows, Git Bash)

See [docs/toolchain.md](docs/toolchain.md) for the tools and how to install them.

```bash
just --list
pre-commit install
```

## License

MIT
