---
inclusion: always
---

# Security Guidelines

## Data Protection Standards

### Data Classification
All data must be classified according to sensitivity:

- **Public**: Non-sensitive data that can be freely shared
- **Internal**: Data for internal use only, not for external sharing
- **Confidential**: Sensitive business data requiring access controls
- **Restricted**: Highly sensitive data (PII, financial) requiring strict controls

### Encryption Requirements

#### Data at Rest
```yaml
# Database encryption
postgres:
  encryption:
    enabled: true
    key_management: "aws-kms"
    algorithm: "AES-256"

# File system encryption
storage:
  encryption:
    enabled: true
    provider: "luks"
    key_rotation: "90d"
```

#### Data in Transit
```python
# Always use TLS for database connections
DATABASE_URL = "postgresql://user:pass@host:5432/db?sslmode=require&sslcert=client.crt&sslkey=client.key"

# API communications
import requests
import ssl

# Configure TLS context
context = ssl.create_default_context()
context.check_hostname = True
context.verify_mode = ssl.CERT_REQUIRED

# Make secure requests
response = requests.get('https://api.example.com/data', 
                       verify=True, 
                       cert=('client.crt', 'client.key'))
```

### Data Masking and Anonymization
```python
import hashlib
import re
from typing import Optional

class DataMasker:
    """Utility class for data masking and anonymization"""
    
    @staticmethod
    def mask_email(email: str) -> str:
        """Mask email addresses for non-production environments"""
        if '@' not in email:
            return email
        
        local, domain = email.split('@', 1)
        masked_local = local[0] + '*' * (len(local) - 2) + local[-1] if len(local) > 2 else local
        return f"{masked_local}@{domain}"
    
    @staticmethod
    def mask_phone(phone: str) -> str:
        """Mask phone numbers"""
        digits_only = re.sub(r'\D', '', phone)
        if len(digits_only) >= 10:
            return f"***-***-{digits_only[-4:]}"
        return "***-****"
    
    @staticmethod
    def hash_pii(value: str, salt: str = "default_salt") -> str:
        """Hash PII data for analytics while preserving uniqueness"""
        return hashlib.sha256(f"{value}{salt}".encode()).hexdigest()[:16]

# Usage in data processing
def process_user_data(user_data: dict, environment: str) -> dict:
    """Process user data with appropriate masking for environment"""
    if environment != 'production':
        user_data['email'] = DataMasker.mask_email(user_data['email'])
        user_data['phone'] = DataMasker.mask_phone(user_data.get('phone', ''))
        user_data['user_id'] = DataMasker.hash_pii(user_data['user_id'])
    
    return user_data
```

## Access Control

### Role-Based Access Control (RBAC)
```yaml
# Kubernetes RBAC configuration
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: data-pipeline
  name: pipeline-operator
rules:
- apiGroups: [""]
  resources: ["pods", "configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "update", "patch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pipeline-operators
  namespace: data-pipeline
subjects:
- kind: User
  name: data-engineer@company.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pipeline-operator
  apiGroup: rbac.authorization.k8s.io
```

### Database Access Control
```sql
-- Create role-based database access
CREATE ROLE data_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO data_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA staging TO data_reader;

CREATE ROLE data_writer;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA staging TO data_writer;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO data_writer;

CREATE ROLE data_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO data_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA staging TO data_admin;

-- Create users with appropriate roles
CREATE USER analytics_service WITH PASSWORD 'secure_password';
GRANT data_reader TO analytics_service;

CREATE USER etl_service WITH PASSWORD 'secure_password';
GRANT data_writer TO etl_service;
```

### API Authentication and Authorization
```python
from functools import wraps
from flask import request, jsonify
import jwt
import os

def require_auth(required_role: str = None):
    """Decorator to require authentication and optional role"""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            token = request.headers.get('Authorization')
            if not token:
                return jsonify({'error': 'No token provided'}), 401
            
            try:
                # Remove 'Bearer ' prefix
                token = token.replace('Bearer ', '')
                payload = jwt.decode(token, os.getenv('JWT_SECRET'), algorithms=['HS256'])
                
                # Check role if required
                if required_role and payload.get('role') != required_role:
                    return jsonify({'error': 'Insufficient permissions'}), 403
                
                # Add user info to request context
                request.user = payload
                return f(*args, **kwargs)
                
            except jwt.ExpiredSignatureError:
                return jsonify({'error': 'Token expired'}), 401
            except jwt.InvalidTokenError:
                return jsonify({'error': 'Invalid token'}), 401
        
        return decorated_function
    return decorator

# Usage
@app.route('/admin/users')
@require_auth(required_role='admin')
def get_users():
    return jsonify({'users': get_all_users()})
```

## Secrets Management

### Kubernetes Secrets
```yaml
# Create secrets securely
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: data-pipeline
type: Opaque
data:
  username: <base64-encoded-username>
  password: <base64-encoded-password>
  
---
# Use secrets in deployments
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: app
        env:
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: database-credentials
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: database-credentials
              key: password
```

### External Secret Management
```python
import boto3
from botocore.exceptions import ClientError

class SecretManager:
    """Secure secret management using AWS Secrets Manager"""
    
    def __init__(self, region_name: str = 'us-west-2'):
        self.client = boto3.client('secretsmanager', region_name=region_name)
    
    def get_secret(self, secret_name: str) -> dict:
        """Retrieve secret from AWS Secrets Manager"""
        try:
            response = self.client.get_secret_value(SecretId=secret_name)
            return json.loads(response['SecretString'])
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                raise ValueError(f"Secret {secret_name} not found")
            raise
    
    def rotate_secret(self, secret_name: str):
        """Trigger secret rotation"""
        try:
            self.client.rotate_secret(SecretId=secret_name)
        except ClientError as e:
            raise ValueError(f"Failed to rotate secret {secret_name}: {e}")

# Usage
secret_manager = SecretManager()
db_credentials = secret_manager.get_secret('prod/database/credentials')
```

## Network Security

### Network Policies
```yaml
# Restrict network traffic between namespaces
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: data-pipeline-network-policy
  namespace: data-pipeline
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: data-pipeline
    - namespaceSelector:
        matchLabels:
          name: monitoring
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: data-storage
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - namespaceSelector:
        matchLabels:
          name: data-storage
    ports:
    - protocol: TCP
      port: 8123
```

### TLS Configuration
```yaml
# TLS termination at ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: airflow-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - airflow.company.com
    secretName: airflow-tls
  rules:
  - host: airflow.company.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: airflow-webserver
            port:
              number: 8080
```

## Audit Logging

### Security Event Logging
```python
import logging
import json
from datetime import datetime
from enum import Enum

class SecurityEventType(Enum):
    LOGIN_SUCCESS = "login_success"
    LOGIN_FAILURE = "login_failure"
    UNAUTHORIZED_ACCESS = "unauthorized_access"
    DATA_ACCESS = "data_access"
    PRIVILEGE_ESCALATION = "privilege_escalation"
    CONFIGURATION_CHANGE = "configuration_change"

class SecurityAuditor:
    """Security event auditing"""
    
    def __init__(self):
        self.logger = logging.getLogger('security_audit')
        handler = logging.FileHandler('/var/log/security/audit.log')
        handler.setFormatter(logging.Formatter('%(message)s'))
        self.logger.addHandler(handler)
        self.logger.setLevel(logging.INFO)
    
    def log_event(self, event_type: SecurityEventType, user_id: str, 
                  resource: str = None, **kwargs):
        """Log security event"""
        event = {
            'timestamp': datetime.utcnow().isoformat(),
            'event_type': event_type.value,
            'user_id': user_id,
            'resource': resource,
            'source_ip': kwargs.get('source_ip'),
            'user_agent': kwargs.get('user_agent'),
            'session_id': kwargs.get('session_id'),
            'additional_data': {k: v for k, v in kwargs.items() 
                              if k not in ['source_ip', 'user_agent', 'session_id']}
        }
        
        self.logger.info(json.dumps(event))

# Usage
auditor = SecurityAuditor()

def authenticate_user(username: str, password: str, request_info: dict):
    """Authenticate user with audit logging"""
    try:
        user = validate_credentials(username, password)
        auditor.log_event(
            SecurityEventType.LOGIN_SUCCESS,
            user_id=user.id,
            source_ip=request_info.get('remote_addr'),
            user_agent=request_info.get('user_agent')
        )
        return user
    except AuthenticationError:
        auditor.log_event(
            SecurityEventType.LOGIN_FAILURE,
            user_id=username,
            source_ip=request_info.get('remote_addr'),
            reason="invalid_credentials"
        )
        raise
```

## Vulnerability Management

### Container Security Scanning
```yaml
# Security scanning in CI/CD pipeline
name: Security Scan
on: [push, pull_request]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Build Docker image
      run: docker build -t app:latest .
    
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: 'app:latest'
        format: 'sarif'
        output: 'trivy-results.sarif'
    
    - name: Upload Trivy scan results
      uses: github/codeql-action/upload-sarif@v1
      with:
        sarif_file: 'trivy-results.sarif'
```

### Dependency Scanning
```python
# requirements-security.txt - security-focused dependencies
bandit==1.7.4          # Security linting
safety==2.3.1          # Dependency vulnerability checking
pip-audit==2.4.14      # Audit Python packages

# Add to CI/CD pipeline
# pip install -r requirements-security.txt
# bandit -r . -f json -o bandit-report.json
# safety check --json --output safety-report.json
# pip-audit --format=json --output=pip-audit-report.json
```

### Runtime Security Monitoring
```yaml
# Falco rules for runtime security
- rule: Unauthorized Process in Container
  desc: Detect unauthorized processes in data pipeline containers
  condition: >
    spawned_process and
    container.image.repository contains "data-pipeline" and
    not proc.name in (python, dbt, airflow, postgres)
  output: >
    Unauthorized process in data pipeline container
    (user=%user.name command=%proc.cmdline container=%container.name)
  priority: WARNING

- rule: Sensitive File Access
  desc: Detect access to sensitive files
  condition: >
    open_read and
    fd.name in (/etc/passwd, /etc/shadow, /root/.ssh/id_rsa) and
    container.image.repository contains "data-pipeline"
  output: >
    Sensitive file accessed in container
    (file=%fd.name user=%user.name container=%container.name)
  priority: CRITICAL
```