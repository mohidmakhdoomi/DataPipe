#!/bin/bash
# Create ConfigMap with security audit scripts

set -euo pipefail

echo "Creating ConfigMap with security audit scripts..."

kubectl create configmap security-audit-scripts \
  --namespace=data-ingestion \
  --from-file=task13-validate-cdc-permissions.sh \
  --from-file=task13-audit-s3-policies.sh \
  --from-file=task13-network-policy-validation.sh \
  --from-file=task13-rbac-audit.sh \
  --dry-run=client -o yaml > task13-security-audit-configmap.yaml

echo "ConfigMap manifest created: task13-security-audit-configmap.yaml"
echo
echo "To apply the ConfigMap:"
echo "kubectl apply -f task13-security-audit-configmap.yaml"
echo
echo "To run the security audit job:"
echo "kubectl apply -f task13-security-audit-job.yaml"
echo
echo "To check job status:"
echo "kubectl get jobs -n data-ingestion"
echo
echo "To view audit results:"
echo "kubectl logs -n data-ingestion job/data-pipeline-security-audit"