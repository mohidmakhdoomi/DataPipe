# Steering Documentation

This directory contains comprehensive guidance and standards for the Data Pipeline project. These documents provide team-wide standards, best practices, and operational procedures.

## Document Overview

### Core Standards
- **[Project Standards](project-standards.md)** - Overall project guidelines and quality standards
- **[Security Guidelines](security-guidelines.md)** - Security requirements and best practices
- **[Testing Standards](testing-standards.md)** - Testing strategy and implementation guidelines

### Technical Guides
- **[Airflow DAG Standards](airflow-dag-standards.md)** - DAG development and operational standards
- **[Data Modeling Guide](data-modeling-guide.md)** - dbt modeling patterns and conventions
- **[Monitoring Standards](monitoring-standards.md)** - Observability and alerting requirements

### Operational Procedures
- **[Deployment Guide](deployment-guide.md)** - Step-by-step deployment procedures
- **[Troubleshooting Guide](troubleshooting-guide.md)** - Common issues and solutions

## How to Use These Documents

### For Developers
1. Start with **Project Standards** for overall guidelines
2. Review **Airflow DAG Standards** when writing DAGs
3. Follow **Data Modeling Guide** for dbt development
4. Implement **Testing Standards** for all code
5. Apply **Security Guidelines** throughout development

### For DevOps/Platform Engineers
1. Use **Deployment Guide** for environment setup
2. Implement **Monitoring Standards** for observability
3. Follow **Security Guidelines** for infrastructure
4. Reference **Troubleshooting Guide** for operations

### For Data Engineers
1. Follow **Data Modeling Guide** for dbt projects
2. Apply **Airflow DAG Standards** for orchestration
3. Implement **Testing Standards** for data quality
4. Use **Troubleshooting Guide** for issue resolution

## Document Maintenance

These steering documents are living documents that should be:
- **Updated regularly** as practices evolve
- **Reviewed quarterly** by the team
- **Version controlled** with the project code
- **Referenced in code reviews** and planning

## Compliance

All project work should comply with these standards. During code reviews, check that:
- Code follows the established patterns
- Security guidelines are implemented
- Testing requirements are met
- Documentation is complete and current

## Getting Help

If you have questions about these standards or need clarification:
1. Check the **Troubleshooting Guide** first
2. Review relevant technical guides
3. Consult with team leads or architects
4. Propose updates through pull requests

## Quick Reference

### Most Important Standards
- **No hardcoded secrets** - Use environment variables or secret managers
- **Comprehensive testing** - Unit, integration, and data quality tests
- **Structured logging** - JSON format with consistent fields
- **Error handling** - Graceful degradation and proper alerting
- **Documentation** - Code, APIs, and operational procedures

### Key Patterns
- **Environment-aware configuration** - Detect and adapt to deployment context
- **Defensive programming** - Validate inputs and handle edge cases
- **Monitoring by default** - Instrument all critical paths
- **Security by design** - Apply security controls from the start