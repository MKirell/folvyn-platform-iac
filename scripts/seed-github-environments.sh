#!/usr/bin/env bash
set -euo pipefail

OWNER="${GITHUB_OWNER:-MKirell}"
PROJECT="${PROJECT:-folvyn}"
DOMAIN="${DOMAIN:-mkirell.com}"
REGION="${AWS_REGION:-eu-west-3}"
STATE_PREFIX="${STATE_BUCKET_PREFIX:-mkirell}"
ECR_REPOSITORY="${ECR_REPOSITORY:-mkirell-portfolio-ms}"

REPOS=("$PROJECT-platform-iac" "$PROJECT-portfolio-ms" "$PROJECT-portfolio-mf" "$PROJECT-console-mf")

need() { command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }; }
need gh
need aws
need terraform
need jq

if ! ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>&1); then
  echo "aws could not authenticate: $ACCOUNT" >&2
  echo "export AWS_PROFILE to a profile with access to this account, then re-run" >&2
  exit 1
fi
STATE_BUCKET="$STATE_PREFIX-tfstate-$ACCOUNT"

here=$(cd "$(dirname "$0")" && pwd)

read_output() {
  terraform -chdir="$here/../terraform/$1" output -json "$2" 2>/dev/null || true
}

CLIENT_IDS=$(read_output persistent cognito_console_client_ids)
if [ -z "$CLIENT_IDS" ] || [ "$CLIENT_IDS" = "null" ]; then
  echo "terraform/persistent has no cognito_console_client_ids output" >&2
  echo "run: terraform -chdir=terraform/persistent init" >&2
  exit 1
fi

put_env() { gh api -X PUT "repos/$OWNER/$1/environments/$2" --silent; }

put_var() {
  local repo=$1 env=$2 name=$3 value=$4
  [ -z "$value" ] && return 0
  local MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
  export MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL
  if gh api "repos/$OWNER/$repo/environments/$env/variables/$name" >/dev/null 2>&1; then
    gh api -X PATCH "repos/$OWNER/$repo/environments/$env/variables/$name" \
      -f name="$name" -f value="$value" --silent
  else
    gh api -X POST "repos/$OWNER/$repo/environments/$env/variables" \
      -f name="$name" -f value="$value" --silent
  fi
  echo "    $name = $value"
}

for env in dev prod; do
  host=$([ "$env" = prod ] && echo "$PROJECT" || echo "$PROJECT-$env")
  site="https://$host.$DOMAIN"
  role="arn:aws:iam::$ACCOUNT:role/$PROJECT-github-deploy-$env"
  spa="$PROJECT-spa-$env-$ACCOUNT"
  client=$(printf '%s' "$CLIENT_IDS" | jq -r --arg env "$env" '.[$env] // empty')

  dist=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?contains(Aliases.Items, '$host.$DOMAIN')].Id | [0]" \
    --output text 2>/dev/null || true)
  if [ "$dist" = "None" ]; then dist=""; fi
  if [ -z "$dist" ]; then echo "    (nothing is aliased to $host.$DOMAIN yet)" >&2; fi

  for repo in "${REPOS[@]}"; do
    echo "== $repo / $env =="
    put_env "$repo" "$env"
    put_var "$repo" "$env" AWS_REGION "$REGION"
    put_var "$repo" "$env" AWS_DEPLOY_ROLE_ARN "$role"

    case $repo in
      *-platform-iac)
        put_var "$repo" "$env" TF_STATE_BUCKET "$STATE_BUCKET"
        ;;
      *-portfolio-ms)
        put_var "$repo" "$env" API_BASE_URL "$site/api/v1"
        put_var "$repo" "$env" ECR_REPOSITORY "$ECR_REPOSITORY"
        put_var "$repo" "$env" LAMBDA_FUNCTION_NAME "$PROJECT-portfolio-ms-$env"
        ;;
      *-portfolio-mf)
        put_var "$repo" "$env" API_BASE_URL "$site/api/v1"
        put_var "$repo" "$env" SITE_URL "$site"
        put_var "$repo" "$env" S3_BUCKET "$spa"
        put_var "$repo" "$env" S3_SHELL_PREFIX portfolio
        put_var "$repo" "$env" S3_BUNDLE_PREFIX app/portfolio
        put_var "$repo" "$env" CLOUDFRONT_DISTRIBUTION_ID "$dist"
        put_var "$repo" "$env" PRERENDER_FUNCTION_NAME "$PROJECT-prerender-$env"
        ;;
      *-console-mf)
        put_var "$repo" "$env" API_BASE_URL "$site/api/v1"
        put_var "$repo" "$env" SITE_URL "$site"
        put_var "$repo" "$env" PORTFOLIO_URL "$site"
        put_var "$repo" "$env" COGNITO_DOMAIN "https://auth.$DOMAIN"
        put_var "$repo" "$env" COGNITO_CLIENT_ID "$client"
        put_var "$repo" "$env" S3_BUCKET "$spa"
        put_var "$repo" "$env" S3_SHELL_PREFIX console
        put_var "$repo" "$env" S3_BUNDLE_PREFIX app/console
        put_var "$repo" "$env" CLOUDFRONT_DISTRIBUTION_ID "$dist"
        put_var "$repo" "$env" PREVIEW_PATH /app/portfolio/preview.html
        ;;
    esac
  done
done

echo "done"
