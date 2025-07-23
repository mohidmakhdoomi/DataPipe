#!/usr/bin/env python3
"""
Standalone DAG Validation Script

This script validates the DAG without requiring a full Airflow installation.
It checks for syntax errors, import issues, and basic structure validation.
"""

import ast
import sys
import os
from pathlib import Path

def validate_python_syntax(file_path):
    """Validate Python syntax of the DAG file"""
    print(f"🔍 Validating Python syntax: {file_path}")
    
    try:
        with open(file_path, 'r') as f:
            content = f.read()
        
        # Parse the AST to check for syntax errors
        ast.parse(content)
        print("✅ Python syntax is valid")
        return True
    except SyntaxError as e:
        print(f"❌ Syntax error: {e}")
        return False
    except Exception as e:
        print(f"❌ Error reading file: {e}")
        return False

def check_required_imports(file_path):
    """Check if required Airflow imports are present"""
    print("🔍 Checking required imports...")
    
    required_imports = [
        'from airflow import DAG',
        'from datetime import datetime',
        'from airflow.operators.python import PythonOperator'
    ]
    
    try:
        with open(file_path, 'r') as f:
            content = f.read()
        
        missing_imports = []
        for import_stmt in required_imports:
            if import_stmt not in content:
                missing_imports.append(import_stmt)
        
        if missing_imports:
            print(f"❌ Missing required imports: {missing_imports}")
            return False
        
        print("✅ All required imports found")
        return True
    except Exception as e:
        print(f"❌ Error checking imports: {e}")
        return False

def check_dag_definition(file_path):
    """Check if DAG is properly defined"""
    print("🔍 Checking DAG definition...")
    
    try:
        with open(file_path, 'r') as f:
            content = f.read()
        
        # Check for DAG instantiation
        if 'dag = DAG(' not in content and 'DAG(' not in content:
            print("❌ No DAG definition found")
            return False
        
        # Check for default_args
        if 'default_args' not in content:
            print("⚠️ Warning: No default_args defined")
        
        # Check for required DAG parameters
        required_params = ['dag_id', 'description', 'schedule_interval']
        missing_params = []
        
        for param in required_params:
            if param not in content:
                missing_params.append(param)
        
        if missing_params:
            print(f"⚠️ Warning: Missing recommended DAG parameters: {missing_params}")
        
        print("✅ DAG definition looks good")
        return True
    except Exception as e:
        print(f"❌ Error checking DAG definition: {e}")
        return False

def check_task_definitions(file_path):
    """Check if tasks are properly defined"""
    print("🔍 Checking task definitions...")
    
    try:
        with open(file_path, 'r') as f:
            content = f.read()
        
        # Look for task operators
        task_operators = [
            'PythonOperator',
            'BashOperator',
            'DummyOperator',
            'BranchPythonOperator'
        ]
        
        found_operators = []
        for operator in task_operators:
            if operator in content:
                found_operators.append(operator)
        
        if not found_operators:
            print("❌ No task operators found")
            return False
        
        print(f"✅ Found task operators: {found_operators}")
        
        # Check for task dependencies (>> or <<)
        if '>>' not in content and '<<' not in content:
            print("⚠️ Warning: No task dependencies found")
        else:
            print("✅ Task dependencies found")
        
        return True
    except Exception as e:
        print(f"❌ Error checking task definitions: {e}")
        return False

def check_function_definitions(file_path):
    """Check if Python functions for tasks are properly defined"""
    print("🔍 Checking function definitions...")
    
    try:
        with open(file_path, 'r') as f:
            content = f.read()
        
        # Parse AST to find function definitions
        tree = ast.parse(content)
        
        functions = []
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                functions.append(node.name)
        
        if not functions:
            print("⚠️ Warning: No Python functions found")
        else:
            print(f"✅ Found functions: {functions}")
        
        # Check if functions have **context parameter
        context_functions = []
        for func_name in functions:
            if f"def {func_name}(**context)" in content:
                context_functions.append(func_name)
        
        if context_functions:
            print(f"✅ Functions with **context parameter: {context_functions}")
        
        return True
    except Exception as e:
        print(f"❌ Error checking function definitions: {e}")
        return False

def validate_dag_file(file_path):
    """Run all validation checks on the DAG file"""
    print(f"🚀 Validating DAG file: {file_path}")
    print("=" * 50)
    
    if not os.path.exists(file_path):
        print(f"❌ File not found: {file_path}")
        return False
    
    checks = [
        validate_python_syntax,
        check_required_imports,
        check_dag_definition,
        check_task_definitions,
        check_function_definitions
    ]
    
    results = []
    for check in checks:
        print()
        result = check(file_path)
        results.append(result)
    
    print("\n" + "=" * 50)
    print("VALIDATION SUMMARY")
    print("=" * 50)
    
    passed = sum(results)
    total = len(results)
    
    if passed == total:
        print(f"🎉 All {total} validation checks passed!")
        print("✅ DAG file is ready for Airflow")
        return True
    else:
        print(f"⚠️ {passed}/{total} validation checks passed")
        print("❌ Please fix the issues above before deploying")
        return False

def main():
    """Main function"""
    # Default to the main DAG file
    dag_file = "dags/data_pipeline_main.py"
    
    # Allow command line argument for different DAG file
    if len(sys.argv) > 1:
        dag_file = sys.argv[1]
    
    # Make path relative to script location
    script_dir = Path(__file__).parent
    dag_path = script_dir / dag_file
    
    success = validate_dag_file(str(dag_path))
    
    if success:
        print("\n🎯 Next steps:")
        print("1. Test with: airflow dags test data_pipeline_main 2024-01-01")
        print("2. Check DAG in UI: http://localhost:8080")
        print("3. Enable and trigger the DAG")
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()