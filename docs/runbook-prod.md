# Runbook: prod root

`infra/prod` holds what runs in production: the ECR repository, the log group, the Lambda
execution role and, once an image digest is given, the Lambda function with its Function URL.
State: `s3://portfolio-tfstate-x7k2m9qd4t/prod/terraform.tfstate`. Everything is tagged
`Project=portfolio`, `Root=prod`.

| File | Manages |
|---|---|
| `ecr.tf` | Repository (immutable tags, scan on push, `force_delete` behind a variable) and the lifecycle policy that keeps the newest 3 images |
| `logs.tf` | The function's log group, 7-day retention (managed, so `destroy` removes it) |
| `iam.tf` | Execution role `portfolio-prod-lambda` (permission boundary, writes its own log group only) |
| `lambda.tf` | Function (container image by digest), Function URL (auth NONE) and the two public-invoke statements. All four exist only while `image_digest` is set |

## Variables worth knowing

| Variable | Default | Meaning |
|---|---|---|
| `image_digest` | `null` | `sha256:...` of the image to run. `null`: no function and no URL, only the repository and its pieces |
| `reserved_concurrency` | `2` | Parallel-execution cap. AWS keeps 10 unreserved, so this needs an account quota above 12 (it is 40 here since 2026-10-22). On an account with the default quota of 10 set `null`, which means no cap. `0` blocks every request (kill switch) |
| `images_to_keep` | `3` | At least 3, so pushing two newer images before a deploy cannot expire the running one |
| `force_delete_images` | `false` | Teardown only (see below) |

## Applying (locally, with the bootstrap admin session)

```bash
aws login --profile portfolio-bootstrap       # open a terminal tab, sign in as portfolio-admin
export AWS_PROFILE=portfolio-bootstrap AWS_REGION=us-east-1
tofu -chdir=infra/prod init
tofu -chdir=infra/prod plan -out=tfplan        # read it: `tofu show tfplan`
tofu -chdir=infra/prod apply tfplan
rm infra/prod/tfplan
aws logout --profile portfolio-bootstrap
```

1. First apply, no image: repository, lifecycle policy, log group, role and its policy.
2. The `build` workflow pushes an image to the repository and reports its digest (see
   "Building the image" below).
3. Second apply, with the digest: `tofu -chdir=infra/prod plan -var image_digest=sha256:... -out=tfplan`.
   The function URL is in the output `function_url`. The site calls it: put it, without a trailing
   slash, in `web/.env.production` (see "Recreating" below if it changed).

Pull requests that change `infra/prod/**` run `tofu plan` through the read-only role
(`plan.yml`). It plans with the digest that is deployed now (read from the state output), so the
plan shows only what the pull request changes.

## Building the image (task 14b)

`.github/workflows/build.yml` runs after a merge to `main` that changes the image's inputs (and
on demand from the Actions tab, from `main`). It assumes the `portfolio-ecr-push` role, which
trusts only `refs/heads/main`, so it cannot run from a branch. It builds with Compose, runs the
smoke test, and pushes **the image that passed** as `sha-<full commit hash>`. The tag is the
only one: the repository's tags are immutable. If the commit already has an image, the job
reuses it instead of rebuilding (builds are not reproducible bit for bit, so the first image
for a commit stays canonical). The job summary shows the tag, the digest and the manifest type;
the digest is what the deploy uses (`image_digest`). An image index or manifest list is
rejected, because Lambda cannot run one.

Find the digest of an image later (needs the AWS login, or the ecr-push role in a workflow):

```bash
aws ecr describe-images --repository-name portfolio-api \
  --query 'sort_by(imageDetails,&imagePushedAt)[-1].[imageTags[0],imageDigest]' --output text
```

`scripts/ecr-image.sh` holds the ECR steps and `scripts/test-ecr-image.sh` tests them with fake
`aws` and `docker` commands (`just test-scripts`, and in CI). The approval gate and the deploy
itself are the rest of task 15.

## Deploying (task 15, D41)

After every image push, `build.yml` calls `deploy.yml`, and the job **`deploy (prod)` waits for your
approval** in the Actions run (Review deployments, environment `prod`, `main` only). Rejecting it,
or not answering, changes nothing. A newer pending approval replaces an older one.

After you approve, it:

1. assumes `portfolio-apply` (the only role that accepts the `prod` environment),
2. finds the commit of the image from its `sha-<commit>` tag (and refuses a digest that is not in
   the repository),
3. plans `infra/prod` with `-var image_digest=<digest>`,
4. runs `scripts/check_deploy_plan.py` on the plan as JSON: the only allowed change is an in-place
   update of `aws_lambda_function.api[0]` whose **only** difference is `image_uri`, and it must end
   in the approved digest. Anything else (a destroy, a create, another resource, another attribute)
   fails with the reasons, and you apply by hand after reading the plan,
5. applies that exact saved plan (skipped when nothing would change),
6. calls `/health` on the function URL (with retries for the cold start) and requires `status: ok`
   and `git_sha` equal to the image's commit (`scripts/verify_deploy.py`).

The job summary lists the digest that was deployed before, the one requested and its commit.

**Dry run:** Actions, `deploy`, Run workflow, untick `apply`. It does steps 1 to 4 and shows the plan,
without changing production (the approval is still asked). Use it to read a plan first, or to
check the permissions of the `apply` role.

**Rollback:** Actions, `deploy`, Run workflow, with the digest of an older image. The last 3 images
stay in ECR; list them with the command under "Building the image". The same checks run, so it is
only done if the plan is an image swap.

**You approve before you see the plan**, because the read-only `plan` role only works on pull
requests. The safety check and the exact-saved-plan apply are the guard, and the dry run is the way
to read a plan first.

## Releasing (task 15a, D42)

A release is a version tag. Only cut one from a commit that is on `main` and newer than this
workflow.

```bash
git checkout main && git pull
git tag -a v0.1.0 -m "First release"      # x.y.z only: digits, no leading zeros, no suffix
git push origin v0.1.0                     # this starts the release
```

1. **`release-tag.yml`** runs on the tag push. It has no AWS access. It checks (`scripts/check-release.sh`)
   that the version is plain `x.y.z`, that the tag points at the commit, and that the commit is on `main`,
   then starts `release.yml` from `main`.
2. **`release.yml`** checks the same again (it can also be started by hand from the Actions tab for an
   existing tag), then builds the commit with `APP_VERSION=x.y.z`, runs the smoke test and the Trivy
   scan, and pushes the image as **`vx.y.z`** and **`sha-<commit>-vx.y.z`** (both immutable).
3. It creates the **GitHub Release** (`--verify-tag`, generated notes, plus a section with the image
   digest). If the release already exists it does nothing, so a failed run can be repeated.
4. It offers the image for deployment like any other: **`deploy (prod)` waits for your approval**.
   The post-deploy check requires `/health` to report that version and the commit.

**Why two workflows.** A job triggered by a tag push gets an AWS identity that names the *tag*, and a
tag can point at any commit, even one with a changed workflow. So the roles that push images trust
only runs from `main` (see the bootstrap runbook and D42), and the tag only starts a run on `main`. Anyone who can push tags
can start a release build of a commit that is on `main`, but not of anything else.

**If it fails:** fix the cause and run `release` again from the Actions tab with the same version and
commit. The image tags are reused, never overwritten; if `vx.y.z` already points at a different
image it fails, and a new version is needed. To undo a bad release, delete the GitHub Release and
the tag on GitHub, and use a new version number (the image tags stay in ECR until the keep-3
lifecycle removes them).

**Versioning:** semantic versions. `0.x` while the API can still change shape. Every image from
`main` reports `0.0.0-dev`, so only a release image reports a real version.

### The scan (D39)

Before the push, the smoke-tested image is scanned by Trivy (`scripts/scan-image.sh`). A
HIGH or CRITICAL vulnerability that has a fix, or a secret, fails the job and nothing reaches ECR.
The same scan runs in the CI `image` job on every pull request. What to do when it fails:

1. Read the table in the job log. Usually the fix is a newer base-image digest (Dependabot opens
   those) or a bumped dependency.
2. Only if the finding cannot be fixed or does not apply, add an entry to `.trivyignore.yaml`
   with an `id`, a `statement` saying why, and an `expired_at` at most 90 days away.

Trivy is installed by `scripts/install-trivy.sh`, pinned by version and archive checksum. To
update it, change `version` and `sha256` together and check the new archive against the release's
`trivy_<version>_checksums.txt` (`gh release download v<version> --repo aquasecurity/trivy
--pattern '*checksums.txt' --output -`). Dependabot does not see this pin. The image build and the
vulnerability-database download are retried (`scripts/retry.sh`) because the registries answer
`429` to the shared runners now and then; if all attempts fail, re-run the failed jobs.

## Public URL: two statements

Since October 2025 a Function URL with no authentication needs both `lambda:InvokeFunctionUrl`
and `lambda:InvokeFunction` in the function's resource policy
([AWS docs](https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html)). They are
`aws_lambda_permission.url` and `.invoke`. AWS also adds its own equivalent statements
(`FunctionURLAllowPublicAccess`, `FunctionURLAllowInvokeAction`) when the URL is created, so
the policy shows four statements. Ours duplicate them on purpose: the code states the
requirement. If the URL answers `403 Forbidden`, check that both actions exist
(`aws lambda get-policy --function-name portfolio-api`). A deleted URL also answers 403.

## Pausing or removing production (Level 1)

Delete the function but keep the repository: `tofu apply` with `image_digest` unset removes the
function, the URL and the public statements. To remove everything:

```bash
digest="$(tofu -chdir=infra/prod output -raw deployed_image_digest)"
# 1. Turn force_delete on. Pass the deployed digest, or this plan would also remove the function.
tofu -chdir=infra/prod plan -var "image_digest=${digest}" -var force_delete_images=true -out=tfplan
tofu -chdir=infra/prod apply tfplan                     # 1 change: force_delete false -> true
# 2. Plan the destroy AFTER step 1 (a plan saved before it would be stale), read it, then apply.
tofu -chdir=infra/prod plan -destroy -var "image_digest=${digest}" -var force_delete_images=true -out=tfplan-destroy
tofu -chdir=infra/prod apply tfplan-destroy             # 9 resources, including the images
rm infra/prod/tfplan infra/prod/tfplan-destroy
```

The repository holds images, so step 1 has to be applied before the destroy can delete it.
`just teardown-api` wraps this in task 18a.

## Destroy and recreate, rehearsed (2026-10-22)

Run once with the sequence above and then the steps below. Nothing was left after the destroy
(prod state empty, no tagged resources, no repository, function, log group or `portfolio-prod-*`
role), and the old URL answered 403.

| Step | Time |
|---|---|
| Destroy, 9 resources | 13 s |
| Phase 1 apply (repository, lifecycle policy, log group, role and policy) | 6 s |
| `build` workflow, started by hand (Actions, Run workflow, `main`) | 41 s |
| Phase 2 apply with the new digest (function, URL, two statements) | 17 s |

To recreate: apply with no `image_digest` (phase 1), run the `build` workflow, read the new
digest (see "Building the image"), then
`tofu plan -var image_digest=sha256:... -out=tfplan` and apply it. The new URL is different from
the old one: **update `web/.env.production` in a pull request**, or the site keeps calling the old
address and shows "API offline" until you do. Merging it rebuilds the site (`pages.yml`). Then run
`synthetic` by hand (see "Standing check"). A rebuild of the same commit has a different digest, so always take the digest from
ECR. If the build fails on a `429` from `public.ecr.aws`, re-run the failed jobs (D38).

## Standing check of the site and the API (task 17, D46)

The `synthetic` workflow runs every day at 06:17 UTC and on demand
(`gh workflow run synthetic.yml`). It runs `scripts/check_live.py` against
`https://sergo3030.github.io/devops-portfolio/` with no credentials:

| Check | Fails when |
|---|---|
| site policy | the page has no Content-Security-Policy, or `connect-src` does not name exactly one API origin |
| `/health` | not 200, status not `ok`, no valid version or 40-character commit, cacheable, no CORS header for the site, credentials allowed, or a security header missing (or a `uvicorn` banner) |
| `/content` | not 200, a required section missing, approval state in the answer, not cacheable for 5 minutes, no CORS header for the site |
| another website | the API sends a CORS header for `https://evil.example` |
| writes | a `POST` is not refused with 405 and `Allow: GET, OPTIONS` |

It repeats a failing run 3 times, 20 s apart, so a cold start or a CDN delay is not an alarm. A
failure looks like `FAIL /health: ...` lines, then `live check FAILED (n problem(s))` and a red
run. GitHub emails a failed scheduled run to whoever last edited the schedule. The job summary
lists every check with its result, including the version and commit the API reports.

Reading a failure: "no answer" for `/health` and `/content` with a site that is fine means the API
is down or the site points at an old address (compare `web/.env.production` with
`tofu output function_url`). One CORS line failing means the image's `CORS_ALLOW_ORIGINS` or a
platform change. GitHub pauses scheduled workflows in a repository with no activity for 60 days:
after a quiet spell, run it by hand.

After a teardown and recreate the function URL is new. Update `web/.env.production` in a pull
request, merge it (the site rebuilds), then run `synthetic` by hand. The deploy workflow also ends
with "Check that the site calls this API", which fails when the file and production disagree; the
deploy itself is already verified by then.

## Cold start

The first request after idle takes 3.9 to 4.6 s from the owner's laptop (about 2.8 s of that is
container start and Python import, shown as `Init Duration` in the log), and 0.5 s once warm. The
site waits 8 s for live data (D44), so a cold start still ends in "Live from API". If the start
grows, shorten it (a larger memory size gives more CPU; the function uses about 80 MB of 512). The adapter also warns that `HOST` is deprecated in favour of `AWS_LWA_HOST`.

## Cost and abuse

Normal use costs a few cents a month (ECR storage of 3 images). The URL is public, so a
sustained flood could cost real money before the $1 Budget email reaches anyone: a concurrency
cap only bounds it partly. The site calls the URL since task 16b; CORS does not protect it from other callers (D43). The cap
is 2; `reserved_concurrency = 0` is the emergency brake.
