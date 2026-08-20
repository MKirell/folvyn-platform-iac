# folvyn-platform-iac

> Terraform for the whole Folvyn AWS estate. One `apply` brings it up, one `destroy` takes the billable
> half down, and applying again restores it without losing data.

[![Terraform](https://img.shields.io/badge/Terraform-%E2%89%A5%201.10-7b42bc?style=flat-square&logo=terraform)](https://developer.hashicorp.com/terraform)
[![AWS](https://img.shields.io/badge/AWS-eu--west--3-ff9900?style=flat-square&logo=amazonwebservices)](https://aws.amazon.com)
[![MongoDB Atlas](https://img.shields.io/badge/Atlas-M0-47a248?style=flat-square&logo=mongodb)](https://www.mongodb.com/atlas)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue?style=flat-square)](LICENSE)

## Table of contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [The three stacks](#the-three-stacks)
- [Destroy and reapply](#destroy-and-reapply)
- [Project structure](#project-structure)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security](#security)
- [Related repositories](#related-repositories)
- [License](#license)
- [Author](#author)

## Overview

Every AWS resource behind mkirell.com is created from this repository. Nothing was clicked together in a
console. It is the only one of the four that references credentials, even though it stores none — and it
is public, so anything written into it is published. Check `.gitignore` before adding a file here.

It also manages **its own CI configuration**: Actions variables and secrets across all four repositories
are written by `terraform apply`, so they are code rather than console state.

## Architecture

One host serves everything. A CloudFront Function reads the first path segment and picks a shell; the
ordered behaviours take the rest.

```text
                                    ┌─ /            ──► console shell    ◄── console-mf
                                    ├─ /fol/<slug>  ──► portfolio shell  ◄── portfolio-mf
         folvyn.mkirell.com ──► CF ─┼─ /app/*       ──► both bundles
                                    ├─ /imgs /files ──► S3 assets
                                    └─ /api /collect──► API Gateway ─► Lambda  ◄── portfolio-ms
                                                                          └──► MongoDB Atlas
           auth.mkirell.com ──────► Cognito ─────► Google, LinkedIn
```

Everything above is created by this repository. The `◄──` markers show which repository supplies the code
that runs on it: two SPA bundles in S3, and the container image the Lambda runs.

`auth` is deliberately outside `folvyn.` — it is domain-level sign-in meant to be shared by every future
project, and an OAuth issuer cannot move without invalidating every token.

| URL                                     | Serves                        |
| --------------------------------------- | ----------------------------- |
| `https://folvyn.mkirell.com`            | the console                   |
| `https://folvyn.mkirell.com/fol/<slug>` | one published portfolio       |
| `https://folvyn.mkirell.com/api/v1`     | the microservice              |
| `https://auth.mkirell.com`              | Cognito, for the OAuth dances |

## Tech stack

| Layer     | Choice                                                   |
| --------- | -------------------------------------------------------- |
| IaC       | Terraform ≥ 1.10, S3 backend with native state locking   |
| Cloud     | AWS eu-west-3 — Lambda, API Gateway, CloudFront, S3, ECR |
| Identity  | AWS Cognito with Google federation                       |
| Database  | MongoDB Atlas M0 (free tier)                             |
| DNS / TLS | Route53 hosted zone, ACM certificates                    |
| CI auth   | GitHub OIDC → IAM role, no stored AWS keys               |

Everything sits inside a free tier. `compute_mode = "lambda"` costs approximately nothing at portfolio
traffic; the one standing charge is the Route53 hosted zone at about $0.50/month.

## Quick start

**Prerequisites** — Terraform ≥ 1.10, AWS CLI configured as profile `mkirell`, and a
`secrets.auto.tfvars` in each stack (see [Configuration](#configuration)).

```bash
export AWS_PROFILE=mkirell

cd terraform/persistent
terraform apply -var-file=environments/prod.tfvars

cd ../main
terraform apply -var-file=environments/prod.tfvars
```

`persistent` first — `main` reads its outputs through a `terraform_remote_state` data source, so IDs flow
one way and the two stacks never fight over a resource.

`secrets.auto.tfvars` is picked up automatically because of the `.auto.` suffix, so credentials never
appear on a command line or in shell history.

## Configuration

Environment configuration lives in `terraform/*/environments/*.tfvars` and **is committed**. Credentials
live in `secrets.auto.tfvars` and **are not**. Which environment you are targeting is therefore visible in
review while the credentials are not.

One file per environment — `environments/dev.tfvars`, `environments/prod.tfvars` — plus a matching
`backends/<env>.hcl` holding that environment's state key. Both are passed explicitly, so the target
is visible in the command, in review and in shell history. `persistent` has neither: it is shared by
every environment and has one state.

**The first apply of a new environment has no image to point a function at.** ECR is empty, so
`app_image_tag` must be empty too — that skips the Lambda, its role, its log group and the API routes.
Apply without compute, push an image, apply again with its tag:

```bash
terraform apply -var-file=environments/dev.tfvars -var 'app_image_tag='
```

> There is no second tfvars file for this. It was `no-compute.tfvars`, a copy of the production file
> differing in one line, and a copy of an environment file reads like a second environment. A flag on
> the command line says what it is.

| Variable                | Default  | Effect                                                            |
| ----------------------- | -------- | ----------------------------------------------------------------- |
| `compute_mode`          | `lambda` | `lambda` or `fargate` — same ECR image, no application change     |
| `app_image_tag`         | —        | Which image to deploy. Empty skips compute entirely               |
| `dns_validated`         | `true`   | Gate for the first apply, before the zone was delegated           |
| `lambda_memory_mb`      | `512`    | Lambda CPU scales with memory, so this is the speed dial          |
| `fargate_desired_count` | `1`      | Set to `0` to keep the task definition without paying for compute |
| `github_token`          | —        | Leave empty and nothing GitHub-related is touched                 |

Switching compute is one line:

```hcl
compute_mode = "fargate"
```

`apply` then builds a VPC, ECS cluster, ALB and VPC link, and repoints the API Gateway integration.
Nothing in the microservice changes — the image carries the AWS Lambda Web Adapter, so it is an ordinary
HTTP server either way.

### Credentials

`secrets.auto.tfvars` holds the Atlas API key, the Google client secret and the GitHub token. Required in
both `persistent/` and `main/`:

```hcl
mongodbatlas_org_id      = "..."
mongodbatlas_public_key  = "..."
mongodbatlas_private_key = "..."
google_client_id         = "..."
google_client_secret     = "..."
github_token             = "github_pat_..."
```

The GitHub token needs a fine-grained PAT scoped to the four repositories with **Actions**, **Secrets**,
**Variables** and **Contents** at read and write. It is the one credential Terraform cannot create for
itself — a token able to mint tokens would be a bootstrap hole.

`persistent/secrets.auto.tfvars` additionally carries the LinkedIn client pair and who operates the
platform:

```hcl
linkedin_client_id          = "..."
linkedin_client_secret      = "..."
platform_operator_usernames = ["Google_<subject>", "<cognito-sub>"]
```

Operator usernames are not credentials, but they are Google subject identifiers, so they stay out of the
committed environment files. **The variable defaults to an empty list**: applying `persistent` without
them removes every member of the `platform` group, so read the current membership back before an apply
from a fresh clone —

```bash
aws cognito-idp list-users-in-group --user-pool-id <id> --group-name platform \
  --query "Users[].Username" --output table
```

## The three stacks

| Stack        | State                          | Holds                                                              | Safe to destroy       |
| ------------ | ------------------------------ | ------------------------------------------------------------------ | --------------------- |
| `bootstrap`  | local                          | State bucket, backup bucket                                        | no, `prevent_destroy` |
| `persistent` | `persistent/terraform.tfstate` | Route53 zone, Cognito, ECR, Atlas cluster, OIDC role, CI config    | rarely                |
| `main`       | `env/<env>/main.tfstate`       | ACM, API Gateway, Lambda/Fargate, CloudFront, S3 site, DNS records | yes                   |

The split exists for one reason: **everything that holds state or identity lives outside the destroy blast
radius.**

- Destroying the **Route53 zone** would hand you four new nameservers and force a registrar change on
  every cycle.
- Destroying the **Cognito pool** would delete every user. Federated users would return with a different
  `sub`.
- Destroying the **Atlas cluster** would delete the portfolio content.
- Destroying **ECR** would delete the images, forcing a rebuild before the next apply could finish.

None of those cost anything meaningful to keep, so keeping them is strictly better than backing them up
and restoring them.

**Why `bootstrap` exists.** `persistent` and `main` keep their state in
`<legacy_name_prefix>-tfstate-<account-id>`. Something has to create that bucket before Terraform can use
it as a backend, and it cannot be the stacks that depend on it. `bootstrap` is that something: a small
stack with **local** state that runs once and is then left alone. Its own state is gitignored, with a copy
at `s3://<legacy_name_prefix>-backups-<account-id>/bootstrap/terraform.tfstate`. Losing the local copy
costs nothing material — the buckets carry `prevent_destroy` and would simply need re-importing.

**The bucket name is never written down here.** It contains the AWS account id, and these repositories are
public, so it is supplied at `init` instead of being committed in the backend block. Locally that is a
gitignored `backends/bucket.hcl` in each stack, written once:

```bash
export AWS_PROFILE=mkirell
for stack in terraform/main terraform/persistent; do
  printf 'bucket = "mkirell-tfstate-%s"\n' \
    "$(aws sts get-caller-identity --query Account --output text)" > "$stack/backends/bucket.hcl"
done
```

In CI the same value arrives as the `TF_STATE_BUCKET` environment variable, which `persistent` writes onto
the IaC repository's environments. Everything else that would name the account — bucket names, role ARNs,
log groups — is derived from `data "aws_caller_identity"`, never a literal.

## Destroy and reapply

Run this locally — CI has no permission to destroy or create infrastructure.

```bash
export AWS_PROFILE=mkirell
cd terraform/main

# tear down, reviewing the plan before committing to it
terraform plan -destroy -var-file=environments/prod.tfvars -out=tfdestroy
terraform apply tfdestroy

# rebuild
terraform apply -var-file=environments/prod.tfvars

# refill the bucket: Terraform owns it, not its contents
gh workflow run ci.yml --repo MKirell/folvyn-console-mf
gh workflow run ci.yml --repo MKirell/folvyn-portfolio-mf
```

- Route53 records go, the zone and its nameservers stay — the registrar never changes, and certificates
  re-validate automatically because the zone still answers.
- Cognito users, Atlas data and the container image are never touched.
- **The rebuild apply fails once** on `aws_s3_bucket_policy.spa` (`couldn't find resource`, S3 eventual
  consistency). Re-run it. Only a `time_sleep` would remove this, taxing every apply to fix a
  first-create-only problem.
- Redeploy the front ends **after** the API is up — the portfolio build calls the live API to bake in SEO
  tags. Both read `S3_BUCKET` and `CLOUDFRONT_DISTRIBUTION_ID`, which the apply rewrites; the rebuilt
  distribution has a new id.
- Deploy **both** front ends. Each owns its own prefixes in the shared bucket, so redeploying one leaves
  the other's shell missing and half the host serving nothing.

**Be clear-eyed about what this saves.** With `compute_mode = "lambda"` the running cost of `main` is
approximately zero, so destroying it saves nothing today. The destroy path earns its keep in two cases:

1. `compute_mode = "fargate"`, where an always-on task plus its load balancer runs about $25/month.
2. Wanting a provably clean slate — a rebuild from nothing but code, proving the IaC is complete.

If you truly want zero, destroy `persistent` as well and accept re-entering nameservers next time.

## Project structure

```text
terraform/
├── bootstrap/          # run once, local state, creates the state bucket
├── persistent/
│   ├── route53.tf      # hosted zone
│   ├── cognito.tf      # user pool, resource server, Google federation
│   ├── ecr.tf          # container registry
│   ├── database.tf     # Atlas project, M0 cluster, user, allowlist
│   ├── github-oidc.tf  # IAM role GitHub Actions assumes
│   └── github-actions.tf   # Actions variables and secrets, all four repos
└── main/
    ├── acm.tf                  # the wildcard certificate
    ├── api.tf                  # API Gateway, fronted by CloudFront at /api
    ├── lambda.tf               # container-image function
    ├── fargate.tf              # VPC, ECS, ALB — only when compute_mode = fargate
    ├── frontend.tf             # the SPA bucket, the distribution, the router function
    ├── cloudfront-policies.tf  # the managed cache and origin-request policies
    ├── assets.tf               # uploaded images and documents
    ├── cognito.tf              # the auth domain
    ├── route53.tf              # DNS records
    ├── remote.tf               # reads persistent's outputs
    ├── locals.tf               # the environment handed to the application
    ├── functions/              # the CloudFront Function source
    └── templates/              # robots.txt
```

## Testing

There is no unit-test suite — the verification is the plan itself, run in CI on every change under
`terraform/`:

```bash
terraform fmt -check -recursive
terraform validate
terraform plan
```

The plan job runs with a read-only AWS role, so it can never mutate anything while reviewing a change.

## Deployment

| Workflow    | Trigger                          | Does                                             |
| ----------- | -------------------------------- | ------------------------------------------------ |
| `main.yml`  | push to `main`, PR, or by hand   | scans the history for secrets once, then plans **dev and prod** |

**CI plans; it never applies.** One branch, because a branch whose job is "apply this environment" has
no job to do here: the deploy role has no `iam:PutRolePolicy` or `DeleteRolePolicy` and the stack creates
four inline role policies, the apply policy is granted to `dev` alone, and nothing supplies
`APP_IMAGE_TAG` to CI — so an apply computes an empty tag, decides the application is not deployed, and
plans the Lambda, its policies, the prerender function and the API integration away.

Both environments are planned on every change, including on the pull request, because the plan worth
reading is the one for the environment you are **not** merging into. `APPLY_ENABLED` stays `false`; the
apply path is kept in `terraform.yml` for whoever grants those permissions, and it re-plans rather than
consuming an artefact from the plan job — a saved plan file embeds the resolved Atlas URI, GitHub token
and Google secret in plaintext.

**Applies run locally**, which is also where the four commands in [Quick start](#quick-start) live.

**The role cannot reach the persistent stack.** `github_terraform_apply = true` grants writes only to what
`main` manages: ACM, CloudFront, Route53 records **in this zone only**, Lambda, API Gateway, the site
buckets, log groups, and the Cognito _domain_ on the pool. It cannot touch the user pool itself, the Atlas
cluster, the hosted zone, ECR or the state bucket beyond what the artefact policy already allowed.

Role creation is bounded too: `iam:CreateRole` is limited to `folvyn-*-lambda`, and `iam:AttachRolePolicy`
carries an `iam:PolicyARN` condition pinning it to `AWSLambdaBasicExecutionRole` — so CI cannot grant a
Lambda role broader rights and escalate through it.

**`persistent` is still applied locally, never from CI**, and is not even planned there. It holds the
things that cannot be rebuilt: the user pool with the admin account, the Atlas cluster, the hosted zone.

**The CI variables are per environment, not per repository.** Two environments cannot share one repository
variable — the second apply overwrites the first, and the front ends end up pointing at the other
environment's bucket and distribution. They are `github_actions_environment_variable`, keyed by
`var.environment`.

Writing them needs a token carrying the **Environments: read and write** permission. A fine-grained token
without it cannot create an environment or its variables, and every apply fails on a 403 with the rest of
the environment already converged. `manage_github_ci` exists for exactly that case:

- **`true`** (default) — Terraform owns the deploy workflows' variables, which is the intended state.
- **`false`** — Terraform leaves them alone, and `scripts/seed-github-environments.sh` writes the same
  values from the same sources. Both environment files set it to `false` today because the current token
  lacks the permission; grant it, flip the flag, and Terraform takes ownership back.

The script is idempotent and derives every value rather than restating it — the account id from STS, the
client ids from `persistent`'s outputs, the distribution from whichever one carries that environment's
alias. Run it after the `main` apply for an environment:

```bash
export AWS_PROFILE=mkirell
./scripts/seed-github-environments.sh
```

**What Terraform writes when `manage_github_ci` is true**, across the four repositories:

| Stack        | Writes                                                                                                                                                            |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `persistent` | `AWS_REGION`, `AWS_DEPLOY_ROLE_ARN`, `API_BASE_URL`, `SITE_URL`, `PORTFOLIO_URL`, `COGNITO_DOMAIN`, `COGNITO_CLIENT_ID`, `ECR_REPOSITORY`, `LAMBDA_FUNCTION_NAME` |
| `main`       | `S3_BUCKET`, `S3_SHELL_PREFIX`, `S3_BUNDLE_PREFIX`, `PREVIEW_PATH`, `CLOUDFRONT_DISTRIBUTION_ID`, `APP_IMAGE_TAG`                                                 |

The split follows the resources: `persistent` owns the role, the registry and the user pool, `main` owns
the bucket and the distribution, so each writes the variables it can actually derive. Both front ends
share one bucket and one distribution, so the only per-repo values are the two prefixes each one owns —
which is why no workflow spells out `console/`, `portfolio/` or `app/` for itself.

## Security

**No stored AWS keys in CI.** GitHub Actions assumes an IAM role through OIDC; credentials expire with the
job. The trust policy pins both the immutable repository-id subject claim and the repository name.

**State is treated as a credential.** State files record resolved secret values in plaintext, so the
bucket is encrypted, versioned, and has public access blocked.

**Least privilege by job.** There is one CI role and it cannot change infrastructure: `ReadOnlyAccess`
for planning, plus a narrow artefact policy for deploys. Infrastructure writes require local credentials.

**The microservice holds no secret.** Its configuration is a region, a user pool id and a list of public
app client ids; it verifies tokens against a public JWKS.

**Database access** is gated on a Terraform-generated password. The Atlas network allowlist is `0.0.0.0/0`
by necessity — Lambda has no fixed egress IP and Atlas M0 supports neither PrivateLink nor peering.

## Related repositories

| Repository                                                              | Role                           |
| ----------------------------------------------------------------------- | ------------------------------ |
| [folvyn-portfolio-mf](https://github.com/MKirell/folvyn-portfolio-mf) | Every published portfolio      |
| [folvyn-console-mf](https://github.com/MKirell/folvyn-console-mf)     | The owner and operator console |
| [folvyn-portfolio-ms](https://github.com/MKirell/folvyn-portfolio-ms) | The API both of them talk to   |

## License

[Apache 2.0](LICENSE)

## Author

**Mohamed Khalil ZRELLY** — [LinkedIn](https://www.linkedin.com/in/mohamed-khalil-zrelly/) ·
[mkirell.com](https://mkirell.com/)
