---
inclusion: always
---

# Data Pipeline Project Standards

## Code Quality Standards

### Python Code Standards
- **PEP 8 Compliance**: All Python code must follow PEP 8 style guidelines
- **Type Hints**: Use type hints for all function parameters and return values
- **Docstrings**: All functions and classes must have comprehensive docstrings
- **Error Handling**: Implement proper exception handling with specific error types
- **Logging**: Use structured logging with appropriate log levels

```python
# Example: Proper function structure
def process_user_data(user_id: str, data: Dict[str, Any]) -> Optional[UserModel]:
    """
    Process user data and return validated user model.
    
    Args:
        user_id: Unique identifier for the user
        data: Raw user data dictionary
        
    Returns:
        Validated UserModel instance or None if validation fails
        
    Raises:
        ValidationError: If user data is invalid
        DatabaseError: If database operation fails
    """
    try:
        logger.info(f"Processing user data for user_id: {user_id}")
        # Implementation here
        return validated_user
    except ValidationError as e:
        logger.error(f"User data validation failed: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error processing user {user_id}: {e}")
        return None
```

### SQL Standards
- **Consistent Formatting**: Use consistent indentation and capitalization
- **Meaningful Names**: Use descriptive table and column names
- **Comments**: Document complex queries and business logic
- **Performance**: Consider indexing and query optimization

```sql
-- Example: Well-formatted SQL
SELECT 
    u.user_id,
    u.email,
    u.registration_date,
    COUNT(t.transaction_id) as total_transactions,
    SUM(t.total_amount) as total_revenue
FROM users u
LEFT JOIN transactions t 
    ON u.user_id = t.user_id 
    AND t.status = 'completed'
WHERE u.is_active = true
    AND u.registration_date >= '2024-01-01'
GROUP BY u.user_id, u.email, u.registration_date
ORDER BY total_revenue DESC;
```

### dbt Standards
- **Model Organization**: Follow staging → intermediate → marts pattern
- **Naming Conventions**: 
  - Staging: `stg_<source>_<table>`
  - Intermediate: `int_<business_concept>`
  - Marts: `dim_<entity>` or `fact_<event>`
- **Documentation**: All models must have descriptions and column documentation
- **Testing**: Implement data quality tests for all models

## Environment Management

### Development Workflow
1. **Feature Branches**: Create feature branches from `main`
2. **Local Testing**: Test all changes locally before pushing
3. **Pull Requests**: All changes must go through PR review
4. **CI/CD**: Automated testing must pass before merge

### Environment Promotion
- **Development** → **Staging** → **Production**
- Each environment has separate configurations
- Database migrations tested in staging first
- Rollback procedures documented for each environment

## Data Quality Standards

### Data Validation Rules
- **Completeness**: Check for null values in required fields
- **Uniqueness**: Validate unique constraints
- **Referential Integrity**: Ensure foreign key relationships
- **Business Rules**: Implement domain-specific validation
- **Freshness**: Monitor data recency and staleness

### Monitoring Requirements
- **SLA Compliance**: 95% success rate for all pipelines
- **Data Freshness**: Data must be < 2 hours old
- **Quality Scores**: Maintain > 90% data quality score
- **Alert Response**: Critical alerts must be addressed within 1 hour

## Security Standards

### Data Protection
- **Encryption**: All data encrypted in transit and at rest
- **Access Control**: Role-based access to data and systems
- **Audit Logging**: All data access logged and monitored
- **Data Masking**: PII masked in non-production environments

### Credential Management
- **No Hardcoded Secrets**: Use environment variables or secret managers
- **Rotation Policy**: Rotate credentials every 90 days
- **Least Privilege**: Grant minimum required permissions
- **Multi-Factor Authentication**: Required for all production access

## Performance Standards

### Query Performance
- **Response Time**: Queries should complete within 30 seconds
- **Resource Usage**: Monitor CPU and memory consumption
- **Indexing Strategy**: Implement appropriate indexes for query patterns
- **Query Optimization**: Regular review and optimization of slow queries

### Pipeline Performance
- **Processing Time**: Pipelines should complete within SLA windows
- **Throughput**: Handle expected data volumes with headroom
- **Scalability**: Design for horizontal scaling
- **Resource Efficiency**: Optimize resource utilization

## Documentation Requirements

### Code Documentation
- **README Files**: Every component must have comprehensive README
- **API Documentation**: All APIs documented with examples
- **Architecture Diagrams**: Keep system diagrams current
- **Runbooks**: Operational procedures documented

### Data Documentation
- **Data Dictionary**: Maintain comprehensive data catalog
- **Lineage Tracking**: Document data flow and transformations
- **Business Glossary**: Define business terms and metrics
- **Change Log**: Track schema and pipeline changes

## Testing Standards

### Unit Testing
- **Coverage**: Minimum 80% code coverage
- **Test Types**: Unit, integration, and end-to-end tests
- **Mock Data**: Use realistic test data sets
- **Automated Testing**: All tests run in CI/CD pipeline

### Data Testing
- **dbt Tests**: Implement standard dbt tests (unique, not_null, etc.)
- **Custom Tests**: Business-specific validation rules
- **Data Profiling**: Regular data profiling and anomaly detection
- **Regression Testing**: Test data pipeline changes thoroughly

## Deployment Standards

### Infrastructure as Code
- **Version Control**: All infrastructure defined in code
- **Environment Parity**: Consistent environments across dev/staging/prod
- **Automated Deployment**: Use CI/CD for deployments
- **Rollback Capability**: Quick rollback procedures available

### Release Management
- **Semantic Versioning**: Use semantic versioning for releases
- **Release Notes**: Document all changes and impacts
- **Deployment Windows**: Schedule deployments during low-usage periods
- **Post-Deployment Validation**: Verify system health after deployments

## Incident Response

### Severity Levels
- **Critical**: System down, data loss, security breach
- **High**: Major functionality impaired, SLA breach
- **Medium**: Minor functionality issues, performance degradation
- **Low**: Cosmetic issues, enhancement requests

### Response Times
- **Critical**: 15 minutes
- **High**: 1 hour
- **Medium**: 4 hours
- **Low**: Next business day

### Communication
- **Status Page**: Update status page for user-facing issues
- **Stakeholder Notification**: Inform relevant stakeholders promptly
- **Post-Mortem**: Conduct post-mortem for critical/high severity incidents
- **Documentation**: Update runbooks based on incident learnings