#!/bin/bash
# Setup script for AWS S3 access configuration
# Batch Analytics Layer - Task 3 Implementation
# 
# This script configures AWS S3 access for the batch analytics layer
# including credentials, lifecycle policies, and connectivity testing

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
readonly NAMESPACE="batch-analytics"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
BUCKET_NAME="${AWS_S3_BUCKET:-data-s3-bucket}"
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo -e "${BLUE}=== AWS S3 Access Configuration Setup ===${NC}"
echo "Namespace: $NAMESPACE"
echo "S3 Bucket: $BUCKET_NAME"
echo "AWS Region: $AWS_REGION"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
if ! command_exists kubectl; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

if ! command_exists aws; then
    echo -e "${YELLOW}Warning: AWS CLI is not installed. Some features may not work.${NC}"
fi

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
    echo -e "${RED}Error: Namespace $NAMESPACE does not exist${NC}"
    echo "Please run tasks 1 and 2 first to create the namespace and basic infrastructure"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"

# Step 1: Apply AWS credentials and configuration
echo -e "\n${YELLOW}Step 1: Applying AWS S3 credentials and configuration...${NC}"

# Check if user has set AWS credentials
if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
    echo -e "${YELLOW}Warning: AWS credentials not found in environment variables${NC}"
    echo "Please set the following environment variables before running this script:"
    echo "  export AWS_ACCESS_KEY_ID='your-access-key'"
    echo "  export AWS_SECRET_ACCESS_KEY='your-secret-key'"
    echo "  export AWS_DEFAULT_REGION='us-east-1'"
    echo "  export AWS_S3_BUCKET='your-bucket-name'"
    echo ""
    echo "For now, applying configuration with placeholder values..."
fi

# Apply the secrets and configuration (service accounts are in batch-02-service-accounts.yaml)
kubectl apply -f task3-aws-s3-secrets.yaml

# Ensure S3 service account exists (should be created by batch-02-service-accounts.yaml)
if ! kubectl get serviceaccount s3-access-sa -n $NAMESPACE >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: s3-access-sa service account not found${NC}"
    echo "Please ensure batch-02-service-accounts.yaml has been applied (Task 2)"
    echo "Applying service accounts configuration..."
    kubectl apply -f batch-02-service-accounts.yaml
fi

# Update the secret with actual values if environment variables are set
if [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]]; then
    echo "Updating secret with actual AWS credentials..."
    kubectl create secret generic aws-s3-credentials \
        --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
        --from-literal=AWS_DEFAULT_REGION="$AWS_REGION" \
        --from-literal=AWS_S3_BUCKET="$BUCKET_NAME" \
        --from-literal=AWS_S3_ENDPOINT="https://s3.amazonaws.com" \
        --from-literal=ICEBERG_WAREHOUSE_PATH="s3://$BUCKET_NAME/" \
        --from-literal=ICEBERG_CATALOG_TYPE="hadoop" \
        --namespace=$NAMESPACE \
        --dry-run=client -o yaml | kubectl apply -f -
fi

echo -e "${GREEN}✓ AWS S3 credentials and configuration applied${NC}"

# Step 2: Create S3 bucket if it doesn't exist (optional)
if command_exists aws && [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
    echo -e "\n${YELLOW}Step 2: Checking S3 bucket existence...${NC}"
    
    if aws s3 ls "s3://$BUCKET_NAME" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ S3 bucket '$BUCKET_NAME' exists${NC}"
    else
        echo -e "${YELLOW}S3 bucket '$BUCKET_NAME' does not exist${NC}"
        read -p "Do you want to create it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Creating S3 bucket..."
            if [[ "$AWS_REGION" == "us-east-1" ]]; then
                aws s3 mb "s3://$BUCKET_NAME"
            else
                aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"
            fi
            echo -e "${GREEN}✓ S3 bucket created${NC}"
        else
            echo -e "${YELLOW}Skipping bucket creation. Make sure the bucket exists before running tests.${NC}"
        fi
    fi
    
    # Apply lifecycle policy
    echo -e "\n${YELLOW}Step 3: Applying S3 lifecycle policy...${NC}"
    if aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" \
        --lifecycle-configuration file://task3-s3-lifecycle-policy.json; then
        echo -e "${GREEN}✓ S3 lifecycle policy applied${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to apply lifecycle policy. You may need to apply it manually.${NC}"
    fi
    
    # Configure server-side encryption
    echo -e "\n${YELLOW}Step 4: Configuring server-side encryption...${NC}"
    if aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }'; then
        echo -e "${GREEN}✓ Server-side encryption configured${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to configure encryption. You may need to configure it manually.${NC}"
    fi
else
    echo -e "\n${YELLOW}Skipping S3 bucket operations (AWS CLI not available or credentials not set)${NC}"
fi

# Step 5: Run connectivity test
echo -e "\n${YELLOW}Step 5: Running S3 connectivity test...${NC}"
echo "Applying S3 connectivity test job..."
kubectl apply -f task3-s3-connectivity-test.yaml

echo "Waiting for test job to start..."
sleep 5

# Wait for job completion and show logs
echo "Monitoring test job progress..."
kubectl wait --for=condition=complete job/s3-connectivity-test -n $NAMESPACE --timeout=300s || {
    echo -e "${YELLOW}Test job did not complete within timeout. Checking status...${NC}"
    kubectl describe job s3-connectivity-test -n $NAMESPACE
}

echo -e "\n${BLUE}=== S3 Connectivity Test Logs ===${NC}"
kubectl logs job/s3-connectivity-test -n $NAMESPACE

# Check job status
if kubectl get job s3-connectivity-test -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' | grep -q "True"; then
    echo -e "\n${GREEN}✓ S3 connectivity test completed successfully${NC}"
else
    echo -e "\n${YELLOW}⚠ S3 connectivity test may have failed. Check the logs above.${NC}"
fi

# Step 6: Apply Spark S3 Iceberg test (optional)
echo -e "\n${YELLOW}Step 6: Preparing Spark S3 Iceberg integration test...${NC}"
kubectl apply -f task3-spark-s3-iceberg-test.yaml

echo -e "\n${BLUE}=== Setup Complete ===${NC}"
echo "Next steps:"
echo "1. Review the S3 connectivity test logs above"
echo "2. If tests passed, you can run the Spark S3 Iceberg test:"
echo "   kubectl apply -f task3-spark-s3-iceberg-test.yaml"
echo "   kubectl logs -f sparkapplication/spark-s3-iceberg-test -n $NAMESPACE"
echo "3. Monitor the Spark job in the history server: http://localhost:18080"
echo "4. Proceed to Task 4: Set up Snowflake connection"
echo ""
echo -e "${GREEN}AWS S3 access configuration is now complete!${NC}"

# Cleanup function
cleanup_test_resources() {
    echo -e "\n${YELLOW}Cleaning up test resources...${NC}"
    kubectl delete job s3-connectivity-test -n $NAMESPACE --ignore-not-found=true
    kubectl delete sparkapplication spark-s3-iceberg-test -n $NAMESPACE --ignore-not-found=true
    echo -e "${GREEN}✓ Test resources cleaned up${NC}"
}

# Ask if user wants to clean up test resources
echo ""
read -p "Do you want to clean up test resources now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cleanup_test_resources
fi