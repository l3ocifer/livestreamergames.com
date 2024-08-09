#!/bin/bash

set -euo pipefail

export AWS_PAGER=""

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

for cmd in terraform aws; do
  if ! command_exists "$cmd"; then
    echo "Error: $cmd is not installed. Please install it and try again."
    exit 1
  fi
done

if [ -f .domain ]; then
  previous_domain=$(cat .domain)
  read -p "Enter your domain name (press Enter to use $previous_domain): " domain_name
  domain_name=${domain_name:-$previous_domain}
else
  read -p "Enter your domain name: " domain_name
fi

echo "$domain_name" > .domain

bucket_name="${domain_name}-tf-state"

# Replace placeholders in Terraform files
sed -i.bak "s/BUCKET_NAME_PLACEHOLDER/${bucket_name}/g" backend.tf
rm backend.tf.bak

# Check if S3 bucket for Terraform state exists
if ! aws s3api head-bucket --bucket "${bucket_name}" 2>/dev/null; then
  echo "Creating S3 bucket for Terraform state..."
  aws s3api create-bucket --bucket "${bucket_name}" --region us-east-1 >/dev/null 2>&1
  aws s3api wait bucket-exists --bucket "${bucket_name}" >/dev/null 2>&1
  aws s3api put-bucket-versioning --bucket "${bucket_name}" --versioning-configuration Status=Enabled >/dev/null 2>&1
  aws s3api put-bucket-encryption --bucket "${bucket_name}" --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}' >/dev/null 2>&1
else
  echo "S3 bucket for Terraform state already exists."
fi

# Initialize Terraform
echo "Initializing Terraform..."
terraform init -reconfigure -input=false

# Import the existing S3 bucket if it wasn't created by Terraform
terraform import aws_s3_bucket.terraform_state ${bucket_name} || true

echo "domain_name = \"${domain_name}\"" > terraform.auto.tfvars

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
terraform apply -auto-approve

if ! aws s3 ls "s3://${domain_name}/index.html" &>/dev/null; then
  echo "<html><body><h1>Welcome to ${domain_name}</h1></body></html>" | aws s3 cp - "s3://${domain_name}/index.html" >/dev/null 2>&1
fi

if ! aws s3 ls "s3://${domain_name}/error.html" &>/dev/null; then
  echo "<html><body><h1>Error - Page Not Found</h1></body></html>" | aws s3 cp - "s3://${domain_name}/error.html" >/dev/null 2>&1
fi

distribution_id=$(terraform output -raw cloudfront_distribution_id)
aws cloudfront create-invalidation --distribution-id "${distribution_id}" --paths "/*" >/dev/null 2>&1

echo "Deployment complete! Your website should be accessible at https://${domain_name}"
echo "Please allow some time for the DNS changes to propagate."
