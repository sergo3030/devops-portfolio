# End of life: pausing, removing and retiring the project

The deployment is meant to run only while it is useful. This page is the checklist for each way
of stopping it, what each state looks like, and how to come back. The commands that do the work
are in the [teardown section of the prod runbook](runbook-prod.md#teardown-three-levels-task-18a-d48);
this page says what else to do around them, and in what order.

## The four states

| State | What runs | Cost | The site shows | Enter it | Come back |
|---|---|---|---|---|---|
| **Running** | Site, API, pipelines, AWS roles | A few cents a month | "Live from API", with the version | n/a | n/a |
| **Paused** (Level 1) | Site and pipelines; no API, no image repository | About nothing | "API offline: showing the saved copy" | `just teardown-api apply` | `just up-prod apply`, then a pull request with the new API URL, then enable `synthetic` |
| **AWS removed** (Level 2) | Site and pipelines that need no AWS | $0 | The same saved copy | Level 1, then `just teardown-aws apply` | Rebuild the bootstrap root ([runbook](runbook-bootstrap.md)), re-apply `infra/github` for the secrets, then `just up-prod` |
| **Retired** (Level 3) | Only the static site and the code | $0 | The same saved copy | Level 2, then the checklist below | Un-archive, then as for "AWS removed" |

The site works in every state, because it carries its own copy of the content.

## Scheduled workflows

Scheduled workflows keep running by themselves and email you when they fail, so each one needs a
decision per state. List them with `gh workflow list --all`.

| Workflow | What it does | Needs AWS? | Turn off |
|---|---|---|---|
| `synthetic` (daily) | Calls the live API from outside | The API, not credentials | At Level 1. The teardown script does it. Enable it again after the URL pull request merges |
| `tool-versions` (weekly) | Compares pinned tools with their latest releases | No | At retirement (nothing is left to keep current) |
| `codeql` (weekly) | Scans the code | No | At retirement |
| The drift workflow | Would compare AWS with the code | Yes | **Does not exist** (task 22 is optional and not built). If it is ever built, disable it at Level 1, because it fails against a removed backend |

`gh workflow disable <name>.yml` turns one off; `gh workflow enable <name>.yml` brings it back. These
workflows may also be paused by GitHub itself after 60 days without repository activity.

Pipelines that **need AWS** also fail once it is gone: `plan` (on pull requests that change
`infra/`), `build`, `image` and `release`. Merges that touch image inputs fail at the push step while
the repository does not exist. None of them is a required check, and the registry login in `ci`
falls back softly, so expect red runs in those workflows, not a blocked repository.

## Checklist

### Paused (Level 1)

1. `just teardown-api` to read the plans, then `just teardown-api apply` in a terminal.
2. Confirm `just verify-clean level1` is clean and `synthetic` is disabled.
3. Put the **paused** banner in the README (below).

### AWS removed (Level 2)

1. Level 1 first.
2. `just teardown-aws` to read the plan, then `just teardown-aws apply` in a terminal.
3. Confirm `just verify-clean level2` is clean.
4. Remove what pointed at AWS from GitHub, in code: delete `github_actions_secret.aws_account_id`,
   `github_dependabot_secret.aws_account_id` and the `prod` environment resources from
   `infra/github`, plan, read the plan, apply. Doing it in code keeps the state honest. An empty
   `gh secret list` and no `prod` environment are the proof that no AWS access is left.
5. `aws logout --profile portfolio-bootstrap`, delete the local state files of the bootstrap root
   (they hold the alert email), and unset `TF_VAR_budget_alert_email`.
6. Put the **AWS removed** banner in the README.
7. Next day and a month later: look at the bill and Cost Explorer. Expect nothing.

### Retired (Level 3)

1. Level 2 done and verified.
2. Disable `tool-versions` and `codeql`: `gh workflow disable tool-versions.yml`,
   `gh workflow disable codeql.yml`.
3. Delete the `portfolio-admin` IAM user and its MFA device, in the console (see
   [manual steps](manual-steps.md)), and run `aws logout --all`.
4. The site can stay as a static page, or take Pages down through `infra/github`.
5. **No domain was bought**, so there is no auto-renew to turn off and no DNS record to remove. If a
   domain is added later: turn off auto-renew when you buy it and remove its DNS records before
   retiring.
6. Put the **retired** banner in the README, then archive the repository (see below).
7. Keep, on your own machine only: the private denylist (`~/.portfolio/denylist.txt`) and your
   notes. Nothing in the repository depends on them any more.

## Should the repository be archived?

**Not while the project is meant to run; yes when it is retired.** An archived repository is
read-only: pull requests, issues, Actions and Dependabot stop, and a banner on GitHub says so. The
code and the history stay visible and the Pages site keeps serving, which is what a showcase needs.
Archiving is reversible (Settings, General, Unarchive), so it costs nothing to try, but do it last,
after the banner is committed, because an archived repository cannot take the commit.

## README banner text

Put one of these at the top of the README, under the title, with the date filled in. The wording was
approved by the owner on 2026-10-26. The text is shown as raw Markdown to paste, because its links are
relative to the README and not to this page.

**Paused (Level 1)**

```markdown
> **The API is paused.** The AWS deployment was torn down on <date> to stop all cost. The site still
> works and shows its saved copy. Bring the API back with `just up-prod` (see the
> [teardown runbook](docs/runbook-prod.md#teardown-three-levels-task-18a-d48)).
```

**AWS removed (Level 2)**

```markdown
> **The AWS side has been removed** on <date>. The site is static and shows its saved copy. The
> infrastructure code, pipelines and documentation remain as a showcase, and the
> [runbooks](docs/runbook-bootstrap.md) describe how to rebuild it.
```

**Retired (Level 3)**

```markdown
> **This project is retired** (<date>). Nothing runs in AWS and the repository is archived. It stays
> here as a record of how it was built.
```

When the project runs again, remove the banner in the same pull request that restores it.

## Final check, in any state

```bash
just verify-clean level2        # after Level 2 or 3: nothing named portfolio- or tagged Project=portfolio
gh secret list                  # after Level 2: empty
gh workflow list --all          # the state of every scheduled workflow
```

And the bill: the next day, and again a month later.
