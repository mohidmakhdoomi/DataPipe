#!/usr/bin/env python3
"""
Quick Environment Test Script

Tests the basic environment setup before running Airflow.
"""

import os
import sys
from pathlib import Path

def test_env_file():
    """Test if .env file exists and has required variables"""
    print("🔍 Checking .env file...")
    
    env_files = [
        "docker/.env",
        "airflow/.env", 
        "data-generators/.env"
    ]
    
    for env_file in env_files:
        if Path(env_file).exists():
            print(f"✅ Found: {env_file}")
        else:
            print(f"⚠️ Missing: {env_file} (copy from {env_file}.example)")
    
    return True

def test_required_files():
    """Test if required files exist"""
    print("\n🔍 Checking required files...")
    
    required_files = [
        "docker/docker-compose.yml",
        "airflow/dags/data_pipeline_main.py",
        "docker/.env",
        "SECURITY_SETUP.md"
    ]
    
    all_exist = True
    for file_path in required_files:
        if Path(file_path).exists():
            print(f"✅ {file_path}")
        else:
            print(f"❌ Missing: {file_path}")
            all_exist = False
    
    return all_exist

def test_python_imports():
    """Test if we can import required Python packages"""
    print("\n🔍 Testing Python imports...")
    
    packages = [
        ("pandas", "pandas"),
        ("requests", "requests"),
        ("pydantic", "pydantic")
    ]
    
    for package_name, import_name in packages:
        try:
            __import__(import_name)
            print(f"✅ {package_name}")
        except ImportError:
            print(f"⚠️ {package_name} not installed (pip install {package_name})")
    
    return True

def test_docker():
    """Test if Docker is available"""
    print("\n🔍 Testing Docker availability...")
    
    try:
        import subprocess
        result = subprocess.run(["docker", "--version"], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            print(f"✅ Docker: {result.stdout.strip()}")
            
            # Test docker-compose
            result = subprocess.run(["docker-compose", "--version"], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                print(f"✅ Docker Compose: {result.stdout.strip()}")
                return True
            else:
                print("❌ Docker Compose not available")
                return False
        else:
            print("❌ Docker not available")
            return False
    except Exception as e:
        print(f"❌ Docker test failed: {e}")
        return False

def main():
    """Run all environment tests"""
    print("🚀 Testing Environment Setup")
    print("=" * 40)
    
    tests = [
        ("Environment Files", test_env_file),
        ("Required Files", test_required_files), 
        ("Python Imports", test_python_imports),
        ("Docker", test_docker)
    ]
    
    results = []
    for test_name, test_func in tests:
        try:
            result = test_func()
            results.append(result)
        except Exception as e:
            print(f"❌ {test_name} failed: {e}")
            results.append(False)
    
    print("\n" + "=" * 40)
    print("SUMMARY")
    print("=" * 40)
    
    passed = sum(results)
    total = len(results)
    
    if passed == total:
        print("🎉 Environment setup looks good!")
        print("\n🎯 Next steps:")
        print("1. Set up your .env files with secure passwords")
        print("2. Run: cd docker && ./test_setup.ps1")
        print("3. Access Airflow at http://localhost:8080")
    else:
        print(f"⚠️ {total - passed} issues found. Please fix before proceeding.")
    
    return passed == total

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)