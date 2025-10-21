#!/usr/bin/env python3
"""Test Redis Entra ID authentication with different methods."""

import os
import sys
import logging

# Set up logging
os.environ['MCP_REDIS_LOG_LEVEL'] = 'INFO'
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Common Redis settings
os.environ['REDIS_HOST'] = 'wjason-mcp.westus2.redis.azure.net'
os.environ['REDIS_PORT'] = '10000'
os.environ['REDIS_SSL'] = 'true'
os.environ['REDIS_CLUSTER_MODE'] = 'false'

print("=" * 80)
print("Redis Entra ID Authentication Methods Test")
print("=" * 80)

# Test 1: DefaultAzureCredential (using Azure CLI login)
print("\n" + "=" * 80)
print("Method 1: DefaultAzureCredential (Azure CLI authentication)")
print("=" * 80)
print("\nThis method will use your Azure CLI login credentials.")
print("Make sure you're logged in with: az login")
print("\nTesting...")

os.environ['REDIS_ENTRAID_AUTH_METHOD'] = 'default_azure_credential'

try:
    # Import config module and update the REDIS_CFG directly
    from src.common import config
    from src.common.connection import RedisConnectionManager
    
    # Update config directly instead of relying on reload
    config.REDIS_CFG["entraid_auth_method"] = "default_azure_credential"
    
    # Reset the connection instance
    RedisConnectionManager._instance = None
    
    redis_client = RedisConnectionManager.get_connection()
    result = redis_client.ping()
    print(f"✓ Connection successful! PING result: {result}")
    
    # Test getting a key
    value = redis_client.get('gt3')
    if value:
        print(f"✓ Retrieved key 'gt3': {value.decode('utf-8') if isinstance(value, bytes) else value}")
    else:
        print("✗ Key 'gt3' not found")
        
    print("\n✅ DefaultAzureCredential test PASSED")
    
except Exception as e:
    print(f"\n❌ DefaultAzureCredential test FAILED: {type(e).__name__}: {e}")
    import traceback
    traceback.print_exc()

# Test 2: Managed Identity (will fail on local machine unless Arc-enabled)
print("\n" + "=" * 80)
print("Method 2: Managed Identity (System-Assigned)")
print("=" * 80)
print("\nThis method requires:")
print("- Running on an Azure VM/Container/Function")
print("- OR having Azure Arc agent installed on this machine")
print("\nTesting...")

os.environ['REDIS_ENTRAID_AUTH_METHOD'] = 'managed_identity'
# Don't set REDIS_ENTRAID_MANAGED_IDENTITY_CLIENT_ID for system-assigned

try:
    # Update config directly
    from src.common import config
    from src.common.connection import RedisConnectionManager
    
    config.REDIS_CFG["entraid_auth_method"] = "managed_identity"
    config.REDIS_CFG["entraid_managed_identity_client_id"] = None
    
    # Reset the connection instance
    RedisConnectionManager._instance = None
    
    redis_client = RedisConnectionManager.get_connection()
    result = redis_client.ping()
    print(f"✓ Connection successful! PING result: {result}")
    print("\n✅ Managed Identity test PASSED")
    
except Exception as e:
    print(f"\n⚠️  Managed Identity test FAILED (expected on non-Azure machines): {type(e).__name__}")
    if "No such file or directory" in str(e) or "IMDS" in str(e):
        print("   This is expected - managed identity only works on Azure resources")
    else:
        print(f"   Error: {e}")

# Test 3: Service Principal (with Conditional Access issues)
print("\n" + "=" * 80)
print("Method 3: Service Principal with Certificate")
print("=" * 80)
print("\nThis method uses a service principal with certificate authentication.")
print("Testing...")

os.environ['REDIS_ENTRAID_AUTH_METHOD'] = 'service_principal'
os.environ['REDIS_ENTRAID_TENANT_ID'] = '72f988bf-86f1-41af-91ab-2d7cd011db47'
os.environ['REDIS_ENTRAID_CLIENT_ID'] = '68dd3060-50d2-4ee0-bb8e-0aa54fff6b1e'
os.environ['REDIS_ENTRAID_CERT_PATH'] = '/Users/wikimonkey/workspace/mcp-redis-entra/combined-cert-1.pem'

try:
    # Update config directly
    from src.common import config
    from src.common.connection import RedisConnectionManager
    
    config.REDIS_CFG["entraid_auth_method"] = "service_principal"
    config.REDIS_CFG["entraid_tenant_id"] = "72f988bf-86f1-41af-91ab-2d7cd011db47"
    config.REDIS_CFG["entraid_client_id"] = "68dd3060-50d2-4ee0-bb8e-0aa54fff6b1e"
    config.REDIS_CFG["entraid_cert_path"] = "/Users/wikimonkey/workspace/mcp-redis-entra/combined-cert-1.pem"
    
    # Reset the connection instance
    RedisConnectionManager._instance = None
    
    redis_client = RedisConnectionManager.get_connection()
    result = redis_client.ping()
    print(f"✓ Connection successful! PING result: {result}")
    print("\n✅ Service Principal test PASSED")
    
except Exception as e:
    print(f"\n❌ Service Principal test FAILED: {type(e).__name__}")
    if "AADSTS53003" in str(e):
        print("   Blocked by Conditional Access policy (as seen before)")
    else:
        print(f"   Error: {e}")

print("\n" + "=" * 80)
print("Test Summary")
print("=" * 80)
print("\nRecommended for local development: DefaultAzureCredential")
print("- Uses your Azure CLI login (run 'az login' first)")
print("- No service principal or certificates needed")
print("- Works around Conditional Access policies for user accounts")
