#!/bin/bash
# Task 13: S3 Bucket Policy Validation
# Validates S3 bucket policies follow least privilege principles

set -euo pipefail

# Configuration
S3_BUCKET_NAME="${S3_BUCKET_NAME:-datapipe-ingestion-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== S3 Bucket Policy Validation ==="
echo "Bucket: $S3_BUCKET_NAME"
echo "Region: $AWS_REGION"
echo

# Function to check if AWS CLI is configured
check_aws_config() {
    echo -n "Checking AWS CLI configuration... "
    
    if aws sts get-caller-identity >/dev/null 2>&1; then
        echo -e "${GREEN}✓ CONFIGURED${NC}"
        local identity=$(aws sts get-caller-identity --query 'Arn' --output text)
        echo "  Identity: $identity"
        return 0
    else
        echo -e "${RED}✗ NOT CONFIGURED${NC}"
        echo "Please configure AWS credentials"
        return 1
    fi
}

# Function to check if bucket exists
check_bucket_exists() {
    local bucket=$1
    echo -n "Checking if bucket '$bucket' exists... "
    
    if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
        echo -e "${GREEN}✓ EXISTS${NC}"
        return 0
    else
        echo -e "${RED}✗ NOT FOUND${NC}"
        return 1
    fi
}

# Function to get bucket policy
get_bucket_policy() {
    local bucket=$1
    echo -n "Retrieving bucket policy... "
    
    local policy_file="/tmp/s3-policy-$bucket.json"
    
    if aws s3api get-bucket-policy --bucket "$bucket" --query 'Policy' --output text > "$policy_file" 2>/dev/null; then
        echo -e "${GREEN}✓ RETRIEVED${NC}"
        echo "  Policy saved to: $policy_file"
        echo "$policy_file"
        return 0
    else
        echo -e "${YELLOW}⚠ NO POLICY FOUND${NC}"
        echo "Bucket has no explicit policy (using default permissions)"
        return 1
    fi
}

# Function to analyze bucket policy for least privilege
analyze_bucket_policy() {
    local policy_file=$1
    
    if [ ! -f "$policy_file" ]; then
        echo -e "${YELLOW}⚠ No policy file to analyze${NC}"
        return 0
    fi
    
    echo "Analyzing bucket policy for least privilege compliance:"
    
    # Check for overly permissive actions
    echo -n "  - Checking for wildcard actions (s3:*)... "
    if grep -q '"s3:\*"' "$policy_file"; then
        echo -e "${RED}✗ FOUND WILDCARD ACTIONS${NC}"
        echo "    Recommendation: Use specific actions like s3:PutObject, s3:GetObject"
    else
        echo -e "${GREEN}✓ NO WILDCARD ACTIONS${NC}"
    fi
    
    # Check for overly permissive resources
    echo -n "  - Checking for wildcard resources... "
    if grep -q '"arn:aws:s3:::\*"' "$policy_file"; then
        echo -e "${RED}✗ FOUND WILDCARD RESOURCES${NC}"
        echo "    Recommendation: Restrict to specific bucket and paths"
    else
        echo -e "${GREEN}✓ NO WILDCARD RESOURCES${NC}"
    fi
    
    # Check for public access
    echo -n "  - Checking for public access... "
    if grep -q '"Principal": "\*"' "$policy_file"; then
        echo -e "${RED}✗ FOUND PUBLIC ACCESS${NC}"
        echo "    Recommendation: Restrict to specific IAM users/roles"
    else
        echo -e "${GREEN}✓ NO PUBLIC ACCESS${NC}"
    fi
    
    # Check for required actions for Kafka Connect S3 Sink
    echo "  - Checking required actions for Kafka Connect:"
    local required_actions=("s3:PutObject" "s3:PutObjectAcl" "s3:ListBucket")
    
    for action in "${required_actions[@]}"; do
        echo -n "    - $action: "
        if grep -q "\"$action\"" "$policy_file"; then
            echo -e "${GREEN}✓ ALLOWED${NC}"
        else
            echo -e "${YELLOW}⚠ NOT EXPLICITLY ALLOWED${NC}"
        fi
    done
    
    # Check for unnecessary actions
    echo "  - Checking for potentially unnecessary actions:"
    local unnecessary_actions=("s3:DeleteObject" "s3:DeleteBucket" "s3:CreateBucket")
    
    for action in "${unnecessary_actions[@]}"; do
        echo -n "    - $action: "
        if grep -q "\"$action\"" "$policy_file"; then
            echo -e "${YELLOW}⚠ ALLOWED (may be unnecessary)${NC}"
        else
            echo -e "${GREEN}✓ NOT ALLOWED${NC}"
        fi
    done
}

# Function to check bucket encryption
check_bucket_encryption() {
    local bucket=$1
    echo -n "Checking bucket encryption... "
    
    if aws s3api get-bucket-encryption --bucket "$bucket" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ ENCRYPTION ENABLED${NC}"
        
        # Get encryption details
        local encryption=$(aws s3api get-bucket-encryption --bucket "$bucket" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)
        echo "  Algorithm: $encryption"
    else
        echo -e "${RED}✗ NO ENCRYPTION${NC}"
        echo "  Recommendation: Enable server-side encryption (SSE-S3 or SSE-KMS)"
    fi
}

# Function to check bucket versioning
check_bucket_versioning() {
    local bucket=$1
    echo -n "Checking bucket versioning... "
    
    local versioning=$(aws s3api get-bucket-versioning --bucket "$bucket" --query 'Status' --output text)
    
    case "$versioning" in
        "Enabled")
            echo -e "${GREEN}✓ ENABLED${NC}"
            ;;
        "Suspended")
            echo -e "${YELLOW}⚠ SUSPENDED${NC}"
            ;;
        "None"|"null")
            echo -e "${YELLOW}⚠ DISABLED${NC}"
            echo "  Recommendation: Consider enabling versioning for data protection"
            ;;
        *)
            echo -e "${YELLOW}⚠ UNKNOWN STATUS: $versioning${NC}"
            ;;
    esac
}

# Function to check bucket public access block
check_public_access_block() {
    local bucket=$1
    echo -n "Checking public access block settings... "
    
    if aws s3api get-public-access-block --bucket "$bucket" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ CONFIGURED${NC}"
        
        local pab=$(aws s3api get-public-access-block --bucket "$bucket" --query 'PublicAccessBlockConfiguration')
        echo "  Settings:"
        echo "$pab" | jq -r 'to_entries[] | "    \(.key): \(.value)"'
    else
        echo -e "${YELLOW}⚠ NOT CONFIGURED${NC}"
        echo "  Recommendation: Configure public access block for security"
    fi
}

# Function to check bucket lifecycle configuration
check_lifecycle_policy() {
    local bucket=$1
    echo -n "Checking lifecycle policy... "
    
    if aws s3api get-bucket-lifecycle-configuration --bucket "$bucket" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ CONFIGURED${NC}"
        
        local rules_count=$(aws s3api get-bucket-lifecycle-configuration --bucket "$bucket" --query 'length(Rules)' --output text)
        echo "  Rules configured: $rules_count"
    else
        echo -e "${YELLOW}⚠ NOT CONFIGURED${NC}"
        echo "  Recommendation: Configure lifecycle rules for cost optimization"
    fi
}

# Function to generate security recommendations
generate_recommendations() {
    local bucket=$1
    
    echo
    echo "=== Security Recommendations ==="
    echo
    echo "1. Bucket Policy Best Practices:"
    echo "   - Use specific actions instead of s3:*"
    echo "   - Restrict resources to specific paths: arn:aws:s3:::$bucket/topics/*"
    echo "   - Use IAM roles instead of IAM users when possible"
    echo "   - Implement condition statements for additional security"
    echo
    echo "2. Encryption:"
    echo "   - Enable server-side encryption (SSE-S3 minimum, SSE-KMS preferred)"
    echo "   - Consider bucket key for cost optimization with SSE-KMS"
    echo
    echo "3. Access Control:"
    echo "   - Enable public access block settings"
    echo "   - Use VPC endpoints for private access from Kubernetes"
    echo "   - Implement MFA delete for critical buckets"
    echo
    echo "4. Monitoring:"
    echo "   - Enable CloudTrail for API logging"
    echo "   - Configure S3 access logging"
    echo "   - Set up CloudWatch alarms for unusual access patterns"
    echo
    echo "5. Data Management:"
    echo "   - Configure lifecycle policies for cost optimization"
    echo "   - Enable versioning for data protection"
    echo "   - Consider cross-region replication for disaster recovery"
}

# Main validation
main() {
    local exit_code=0
    
    echo "Starting S3 bucket policy validation..."
    echo
    
    # Check AWS configuration
    if ! check_aws_config; then
        echo -e "${RED}ERROR: AWS CLI not configured${NC}"
        exit 1
    fi
    
    echo
    
    # Check bucket exists
    if ! check_bucket_exists "$S3_BUCKET_NAME"; then
        echo -e "${RED}ERROR: Bucket does not exist${NC}"
        exit 1
    fi
    
    echo
    
    # Get and analyze bucket policy
    local policy_file
    if policy_file=$(get_bucket_policy "$S3_BUCKET_NAME"); then
        echo
        analyze_bucket_policy "$policy_file"
    fi
    
    echo
    
    # Check encryption
    check_bucket_encryption "$S3_BUCKET_NAME"
    
    echo
    
    # Check versioning
    check_bucket_versioning "$S3_BUCKET_NAME"
    
    echo
    
    # Check public access block
    check_public_access_block "$S3_BUCKET_NAME"
    
    echo
    
    # Check lifecycle policy
    check_lifecycle_policy "$S3_BUCKET_NAME"
    
    # Generate recommendations
    generate_recommendations "$S3_BUCKET_NAME"
    
    # Generate audit report
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local report_file="/tmp/s3-policy-audit-$timestamp.json"
    
    cat > "$report_file" << EOF
{
  "audit_type": "s3_bucket_policy",
  "timestamp": "$timestamp",
  "bucket": "$S3_BUCKET_NAME",
  "region": "$AWS_REGION",
  "status": "COMPLETED",
  "checks_performed": [
    "bucket_exists",
    "bucket_policy_analysis",
    "encryption_status",
    "versioning_status",
    "public_access_block",
    "lifecycle_policy"
  ],
  "policy_file": "$([ -n "${policy_file:-}" ] && echo "$policy_file" || echo "null")"
}
EOF
    
    echo
    echo "=== Validation Summary ==="
    echo -e "${GREEN}✓ S3 bucket policy validation completed${NC}"
    echo "Audit report saved to: $report_file"
    
    exit $exit_code
}

# Run main function
main "$@"