#!/bin/bash

set -e

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if Terraform is installed
if ! command_exists terraform; then
  echo "Terraform is not installed. Please install Terraform and try again."
  exit 1
fi

# Check if AWS CLI is installed and configured
if ! command_exists aws; then
  echo "AWS CLI is not installed. Please install and configure AWS CLI and try again."
  exit 1
fi

# Prompt for the domain name
read -p "Enter your domain name: " domain_name

# Set the bucket name
bucket_name="${domain_name}-tf-state"

# Replace placeholders in Terraform files
sed -i.bak "s/livestreamergames.com-tf-state/${bucket_name}/g" backend.tf
rm backend.tf.bak

# Initialize Terraform with local backend
echo "Initializing Terraform with local backend..."
terraform init

# Create S3 bucket for Terraform state
echo "Creating S3 bucket for Terraform state..."
terraform apply -auto-approve -target=aws_s3_bucket.terraform_state

# Wait for the S3 bucket to be available
echo "Waiting for S3 bucket to be available..."
aws s3api wait bucket-exists --bucket "${bucket_name}"

# Verify the bucket exists
if aws s3api head-bucket --bucket "${bucket_name}" 2>/dev/null; then
  echo "S3 bucket is now available."
else
  echo "Failed to create S3 bucket. Please check your AWS credentials and permissions."
  exit 1
fi

# Add backend configuration to main.tf
cat <<EOF >> main.tf

terraform {
  backend "s3" {
    bucket = "${bucket_name}"
    key    = "terraform/state"
    region = "us-east-1"
  }
}
EOF

# Reinitialize Terraform with S3 backend
echo "Reinitializing Terraform with S3 backend..."
terraform init -force-copy

# Apply the main infrastructure
echo "Applying the main infrastructure..."
terraform apply -var="domain_name=${domain_name}" -auto-approve

echo "Deployment complete! Your website should be accessible at https://${domain_name}"
echo "Please allow some time for the DNS changes to propagate."
