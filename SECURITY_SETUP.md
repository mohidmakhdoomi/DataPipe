# Security Setup Guide

## Overview

This project has been updated to follow security best practices by removing all hardcoded passwords and secrets. All sensitive configuration is now managed through environment variables.

## Required Environment Variables

### Database Configuration
```bash
# PostgreSQL Database
POSTGRES_DB=transactions_db
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_secure_postgres_password_here

# ClickHouse Database
CLICKHOUSE_DB=analytics
CLICKHOUSE_USER=analytics_user
CLICKHOUSE_PASSWORD=your_secure_clickhouse_password_here
```

### Airflow Configuration
```bash
# Airflow Security Keys (32+ characters recommended)
AIRFLOW_FERNET_KEY=your_32_character_fernet_key_here_
AIRFLOW_SECRET_KEY=your_secret_key_here
```

## Setup Instructions

### 1. Local Development with Docker Compose

1. Copy the environment template:
   ```bash
   cp docker/.env.example docker/.env
   ```

2. Edit `docker/.env` and set secure passwords:
   ```bash
   # Generate secure passwords
   POSTGRES_PASSWORD=$(openssl rand -base64 32)
   CLICKHOUSE_PASSWORD=$(openssl rand -base64 32)
   AIRFLOW_FERNET_KEY=$(python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
   AIRFLOW_SECRET_KEY=$(openssl rand -base64 32)
   ```

3. Start the services:
   ```bash
   cd docker
   docker-compose up -d
   ```

### 2. Data Generators Setup

1. Copy the environment template:
   ```bash
   cp data-generators/.env.example data-generators/.env
   ```

2. Set the same database password as used in Docker Compose:
   ```bash
   POSTGRES_PASSWORD=your_secure_postgres_password_here
   ```

### 3. Kubernetes Deployment

For Kubernetes deployments, update the secrets in `k8s/secrets/database-secrets.yaml`:

1. Generate base64 encoded passwords:
   ```bash
   echo -n "your_secure_password" | base64
   ```

2. Update the secret values in the YAML files with your base64 encoded passwords.

3. Apply the secrets before deploying other components:
   ```bash
   kubectl apply -f k8s/secrets/
   ```

## Security Best Practices Implemented

### ✅ What Was Fixed

1. **Removed Hardcoded Passwords**: All hardcoded passwords have been replaced with environment variables
2. **Required Environment Variables**: Critical passwords now use `${VAR:?VAR must be set}` syntax to fail fast if not provided
3. **Secure Defaults**: Default values for passwords are now empty strings, forcing explicit configuration
4. **Environment Templates**: Provided `.env.example` files to guide proper configuration

### 🔒 Additional Security Recommendations

1. **Password Complexity**: Use strong, randomly generated passwords (32+ characters)
2. **Secret Rotation**: Regularly rotate passwords and keys (recommended: every 90 days)
3. **Environment Isolation**: Use different passwords for different environments (dev/staging/prod)
4. **Secret Management**: Consider using dedicated secret management tools like:
   - HashiCorp Vault
   - AWS Secrets Manager
   - Azure Key Vault
   - Kubernetes Secrets with encryption at rest

## Generating Secure Keys

### Fernet Key for Airflow
```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

### Random Passwords
```bash
# Generate 32-character password
openssl rand -base64 32

# Generate 16-character alphanumeric password
openssl rand -hex 16
```

### Secret Key for Airflow
```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

## Environment Variable Validation

The application will now fail to start if required environment variables are not set:

- `POSTGRES_PASSWORD` - Required for database connections
- `CLICKHOUSE_PASSWORD` - Required for ClickHouse connections  
- `AIRFLOW_FERNET_KEY` - Required for Airflow encryption
- `AIRFLOW_SECRET_KEY` - Required for Airflow web security

## Troubleshooting

### Common Issues

1. **"POSTGRES_PASSWORD must be set" error**
   - Ensure you've created a `.env` file with the required variables
   - Check that the `.env` file is in the correct directory

2. **Database connection failures**
   - Verify passwords match between services
   - Check that environment variables are properly loaded

3. **Airflow startup failures**
   - Ensure Fernet key is exactly 32 characters (base64 encoded)
   - Verify all Airflow environment variables are set

### Verification Commands

```bash
# Check if environment variables are loaded
docker-compose config

# Test database connection
docker-compose exec postgres psql -U postgres -d transactions_db -c "SELECT 1;"

# Check Airflow configuration
docker-compose exec airflow-webserver airflow config list
```

## Migration from Previous Version

If you're upgrading from a version with hardcoded passwords:

1. **Stop all services**: `docker-compose down`
2. **Set up environment variables** as described above
3. **Update any custom configurations** that referenced old hardcoded values
4. **Restart services**: `docker-compose up -d`
5. **Verify connections** work with new credentials

## Support

If you encounter issues with the security setup:

1. Check the troubleshooting section above
2. Verify your environment variables are correctly set
3. Review the logs for specific error messages
4. Ensure all required environment variables are provided

Remember: Never commit actual passwords or secrets to version control!