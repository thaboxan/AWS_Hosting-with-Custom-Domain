#!/usr/bin/env bash
set -euo pipefail

# Edit DOMAIN if you want a different domain
DOMAIN="thabojafta.co.za"
export TF_VAR_domain="${DOMAIN}"

# Check dependencies
command -v terraform >/dev/null 2>&1 || { echo "terraform not found. Install terraform and retry."; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws cli not found. Install aws-cli and configure credentials."; exit 1; }

# Run from script directory (assumes you place script in week_9)
cd "$(dirname "$0")"

echo "1) Initializing Terraform..."
terraform init

echo
echo "2) Creating only the Route53 hosted zone (so you can update your registrar's nameservers)..."
terraform apply -target=aws_route53_zone.primary -auto-approve

echo
echo "3) Route53 nameservers (copy these and update them at your registrar):"
# prints each NS on a new line if possible
terraform output -json route53_name_servers | jq -r '.[]' 2>/dev/null || terraform output route53_name_servers

echo
echo "IMPORTANT: Login to your domain registrar (where thabojafta.co.za is registered) and set the domain's nameservers to the values above."
echo "Wait for them to propagate (can be minutes to a few hours)."
read -p "Press Enter to continue once you've updated the registrar nameservers and they're propagated..."

# Optional quick check if dig exists
if command -v dig >/dev/null 2>&1; then
  echo "Checking current NS from 8.8.8.8..."
  dig @8.8.8.8 NS ${DOMAIN} +short || true
fi

echo
echo "4) Creating remaining resources: S3 bucket, ACM cert, CloudFront, DNS validation records..."
terraform apply -auto-approve

echo
echo "5) Uploading site contents (if you have a ./site folder) to the S3 bucket..."
if [ -d "./site" ]; then
  aws s3 sync ./site s3://${DOMAIN} --delete
  echo "Files uploaded to s3://${DOMAIN}"
else
  echo "No ./site folder found. Create week_9/site/index.html then re-run the aws s3 sync command:"
  echo "  aws s3 sync ./site s3://${DOMAIN} --delete"
fi

# Invalidate cache so new files appear immediately
DIST_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || terraform output cloudfront_distribution_id)
if [ -n "${DIST_ID}" ]; then
  echo "Invalidating CloudFront distribution ${DIST_ID} (/*)..."
  aws cloudfront create-invalidation --distribution-id "${DIST_ID}" --paths "/*" >/dev/null
  echo "Invalidation requested."
fi

echo
echo "Done. CloudFront domain:"
terraform output cloudfront_domain
echo "Visit https://${DOMAIN} after a few minutes (CloudFront and cert propagation can take a short while)."
