# Runbook: github root

The `infra/github` root manages the repository settings as code. It is planned
and applied **locally only**. CI cannot run it, because administering repository
settings needs an admin token and the built-in `GITHUB_TOKEN` cannot do that. No
token is ever stored in GitHub. A settings change is reviewed as a `.tf` diff in
the pull request, with the local plan output pasted into the description.

## Prerequisites

- `gh auth login` done (the token is read at run time with `gh auth token`)
- `aws login --profile portfolio-bootstrap` as the IAM user (the state is in S3)

## Plan and apply

```bash
just github-plan
```

Or by hand in `infra/github`, with `AWS_PROFILE=portfolio-bootstrap`,
`AWS_REGION=us-east-1` and `GITHUB_TOKEN` set from `gh auth token`:
`tofu init`, `tofu plan -out=tfplan`, read it, `tofu apply tfplan`.

## First-time import (done once)

The repository was created by hand. It was imported with:

```bash
tofu import github_repository.this devops-portfolio
tofu import github_repository_vulnerability_alerts.this devops-portfolio
```

An `import` block cannot be kept in the code, because `tofu test` crashes on it.

## Going public takes two applies

GitHub rejects secret scanning and push protection in the same update that makes a
private repository public (`422 Secret scanning is not available for this
repository`). The flip was therefore done in two steps, and the same order applies
if the repository is ever recreated as private:

```bash
tofu plan -var enable_secret_scanning=false -out=tfplan   # visibility only
tofu apply tfplan
tofu plan -out=tfplan                                     # now the security settings
tofu apply tfplan
```

Done on 2026-10-21 (visibility `public`, secret scanning and push protection `enabled`).

## Safety

- `prevent_destroy` on the repository. `tofu plan -destroy` fails with
  "Resource instance cannot be destroyed", so the repository can never be removed
  by this root. CI checks that the line stays in place.
- To retire the repository (Level 3 teardown), remove it from state first
  (`tofu state rm github_repository.this`) and delete it deliberately.
- Merge method is rebase-and-merge only. Branches are deleted after merge.

## Not managed here yet

The branch ruleset, the `prod` environment, Pages and the Actions permissions come
in task 7b.
