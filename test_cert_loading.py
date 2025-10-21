#!/usr/bin/env python3
"""
Test script to verify certificate loading functionality.
This script helps validate that your certificate file is in the correct format.
"""

import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from common.connection import _load_certificate_credential


def test_certificate_loading(cert_path: str):
    """Test loading a certificate file."""
    print(f"Testing certificate file: {cert_path}")
    print("-" * 60)
    
    try:
        # Check if file exists
        if not os.path.exists(cert_path):
            print(f"❌ ERROR: Certificate file not found: {cert_path}")
            return False
        
        print(f"✓ Certificate file exists")
        
        # Try to load the certificate
        credential = _load_certificate_credential(cert_path)
        
        print(f"✓ Certificate loaded successfully")
        print(f"✓ Thumbprint: {credential['thumbprint']}")
        
        # Check if private key is present
        if "-----BEGIN PRIVATE KEY-----" in credential['private_key'] or \
           "-----BEGIN RSA PRIVATE KEY-----" in credential['private_key']:
            print(f"✓ Private key found in certificate file")
        else:
            print(f"❌ WARNING: Private key not found in certificate file")
            print(f"   The certificate file must contain both the certificate and private key")
            return False
        
        # Check if certificate is present
        if "-----BEGIN CERTIFICATE-----" in credential['private_key']:
            print(f"✓ Certificate found in file")
        else:
            print(f"⚠️  WARNING: Certificate section not found in file")
        
        print("\n" + "=" * 60)
        print("✓ Certificate file is valid and ready to use!")
        print("=" * 60)
        return True
        
    except Exception as e:
        print(f"\n❌ ERROR: Failed to load certificate")
        print(f"   {type(e).__name__}: {e}")
        print("\nPlease ensure:")
        print("  1. The file is in X.509 PEM format")
        print("  2. It contains both the private key and certificate")
        print("  3. The private key section starts with:")
        print("     -----BEGIN PRIVATE KEY----- or -----BEGIN RSA PRIVATE KEY-----")
        print("  4. The certificate section starts with:")
        print("     -----BEGIN CERTIFICATE-----")
        return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python test_cert_loading.py <path_to_certificate.pem>")
        print("\nExample:")
        print("  python test_cert_loading.py /path/to/combined-cert.pem")
        sys.exit(1)
    
    cert_path = sys.argv[1]
    success = test_certificate_loading(cert_path)
    sys.exit(0 if success else 1)
