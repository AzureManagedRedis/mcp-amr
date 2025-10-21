import asyncio
import logging
from typing import Optional, Type, Union, Callable, Any
from functools import partial

import redis
from redis import Redis
from redis.cluster import RedisCluster
from redis_entraid.cred_provider import (
    create_from_service_principal,
    create_from_managed_identity,
    create_from_default_azure_credential,
    TokenManagerConfig,
    RetryPolicy,
    DEFAULT_LOWER_REFRESH_BOUND_MILLIS,
    DEFAULT_TOKEN_REQUEST_EXECUTION_TIMEOUT_IN_MS,
)
from redis_entraid.identity_provider import (
    ManagedIdentityType,
    ManagedIdentityIdType,
)

from src.common.config import REDIS_CFG
from src.version import __version__

_logger = logging.getLogger(__name__)


async def run_redis_command(func: Callable, *args, **kwargs) -> Any:
    """Run a Redis command in an executor to avoid blocking the event loop.
    
    Args:
        func: The Redis method to call
        *args: Positional arguments for the method
        **kwargs: Keyword arguments for the method
        
    Returns:
        The result of the Redis command
    """
    loop = asyncio.get_event_loop()
    if args or kwargs:
        func_with_args = partial(func, *args, **kwargs)
        return await loop.run_in_executor(None, func_with_args)
    else:
        return await loop.run_in_executor(None, func)


def _load_certificate_credential(cert_path: str) -> dict:
    """Load certificate from PEM file and prepare credential for MSAL.
    
    Args:
        cert_path: Path to the X.509 certificate file in PEM format
        
    Returns:
        Dictionary with private_key and thumbprint for MSAL
    """
    import hashlib
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.backends import default_backend
    
    try:
        with open(cert_path, 'rb') as cert_file:
            cert_data = cert_file.read()
        
        # Load the certificate
        cert = x509.load_pem_x509_certificate(cert_data, default_backend())
        
        # Calculate thumbprint (SHA-1 fingerprint of the certificate)
        thumbprint = hashlib.sha1(cert.public_bytes(serialization.Encoding.DER)).hexdigest().upper()
        
        # Extract private key from the PEM file
        # The PEM file should contain both the certificate and private key
        private_key_pem = cert_data.decode('utf-8')
        
        return {
            "private_key": private_key_pem,
            "thumbprint": thumbprint,
        }
    except FileNotFoundError:
        _logger.error("Certificate file not found: %s", cert_path)
        raise ValueError(f"Certificate file not found: {cert_path}")
    except Exception as e:
        _logger.error("Failed to load certificate from %s: %s", cert_path, e)
        raise ValueError(f"Failed to load certificate: {e}")


def _create_entraid_credential_provider():
    """Create Entra ID credential provider for Redis authentication.
    
    Supports three authentication methods:
    - service_principal: Uses certificate-based service principal authentication
    - managed_identity: Uses Azure managed identity (system or user-assigned)
    - default_azure_credential: Uses DefaultAzureCredential (tries multiple methods including Azure CLI)
    """
    auth_method = REDIS_CFG.get("entraid_auth_method", "service_principal")
    
    token_manager_config = TokenManagerConfig(
        expiration_refresh_ratio=0.9,
        lower_refresh_bound_millis=DEFAULT_LOWER_REFRESH_BOUND_MILLIS,
        token_request_execution_timeout_in_ms=DEFAULT_TOKEN_REQUEST_EXECUTION_TIMEOUT_IN_MS,
        retry_policy=RetryPolicy(
            max_attempts=5,
            delay_in_ms=50
        )
    )
    
    try:
        if auth_method == "service_principal":
            # Service Principal with Certificate
            tenant_id = REDIS_CFG.get("entraid_tenant_id")
            client_id = REDIS_CFG.get("entraid_client_id")
            cert_path = REDIS_CFG.get("entraid_cert_path")

            if not tenant_id:
                raise ValueError("REDIS_ENTRAID_TENANT_ID is required for service principal authentication")
            if not client_id:
                raise ValueError("REDIS_ENTRAID_CLIENT_ID is required for service principal authentication")
            if not cert_path:
                raise ValueError("REDIS_ENTRAID_CERT_PATH is required for service principal authentication")

            _logger.info("Creating Entra ID credential provider using service principal (tenant_id=%s, client_id=%s)", 
                        tenant_id, client_id)
            
            # Load and prepare certificate credential
            client_credential = _load_certificate_credential(cert_path)
            
            credential_provider = create_from_service_principal(
                tenant_id=tenant_id,
                client_id=client_id,
                client_credential=client_credential,
                token_manager_config=token_manager_config
            )
            
        elif auth_method == "managed_identity":
            # Managed Identity (System or User-Assigned)
            managed_identity_client_id = REDIS_CFG.get("entraid_managed_identity_client_id")
            
            _logger.info("Creating Entra ID credential provider using managed identity%s",
                        f" (client_id={managed_identity_client_id})" if managed_identity_client_id else " (system-assigned)")
            
            if managed_identity_client_id:
                # User-assigned managed identity
                credential_provider = create_from_managed_identity(
                    identity_type=ManagedIdentityType.USER_ASSIGNED,
                    resource="https://redis.azure.com",
                    id_type=ManagedIdentityIdType.CLIENT_ID,
                    id_value=managed_identity_client_id,
                    token_manager_config=token_manager_config
                )
            else:
                # System-assigned managed identity
                credential_provider = create_from_managed_identity(
                    identity_type=ManagedIdentityType.SYSTEM_ASSIGNED,
                    resource="https://redis.azure.com",
                    token_manager_config=token_manager_config
                )
                
        elif auth_method == "default_azure_credential":
            # DefaultAzureCredential - tries multiple methods in order:
            # 1. Environment variables
            # 2. Managed Identity
            # 3. Azure CLI
            # 4. Azure PowerShell
            # 5. Interactive browser
            _logger.info("Creating Entra ID credential provider using DefaultAzureCredential (will try multiple auth methods)")
            
            credential_provider = create_from_default_azure_credential(
                scopes=("https://redis.azure.com/.default",),
                token_manager_config=token_manager_config
            )
            
        else:
            raise ValueError(f"Invalid REDIS_ENTRAID_AUTH_METHOD: {auth_method}. "
                           f"Valid options are: service_principal, managed_identity, default_azure_credential")
        
        return credential_provider
        
    except Exception as e:
        _logger.error("Failed to create Entra ID credential provider: %s", e)
        raise


class RedisConnectionManager:
    _instance: Optional[Redis] = None

    @classmethod
    def get_connection(cls, decode_responses=True) -> Redis:
        if cls._instance is None:
            try:
                # Check if Entra ID authentication is enabled
                # If entraid_auth_method is set, use Entra ID; otherwise fall back to password
                entraid_auth_method = REDIS_CFG.get("entraid_auth_method")
                credential_provider = None
                
                if entraid_auth_method:
                    _logger.info("Using Entra ID authentication (method: %s)", entraid_auth_method)
                    credential_provider = _create_entraid_credential_provider()
                else:
                    _logger.info("Using password authentication (no REDIS_ENTRAID_AUTH_METHOD set)")
                
                if REDIS_CFG["cluster_mode"]:
                    redis_class: Type[Union[Redis, RedisCluster]] = (
                        redis.cluster.RedisCluster
                    )
                    connection_params = {
                        "host": REDIS_CFG["host"],
                        "port": REDIS_CFG["port"],
                        "ssl": REDIS_CFG["ssl"],
                        "ssl_ca_path": REDIS_CFG["ssl_ca_path"],
                        "ssl_keyfile": REDIS_CFG["ssl_keyfile"],
                        "ssl_certfile": REDIS_CFG["ssl_certfile"],
                        "ssl_cert_reqs": REDIS_CFG["ssl_cert_reqs"],
                        "ssl_ca_certs": REDIS_CFG["ssl_ca_certs"],
                        "decode_responses": decode_responses,
                        "lib_name": f"redis-py(mcp-server_v{__version__})",
                        "max_connections_per_node": 10,
                    }
                    
                    # Add authentication - either Entra ID or username/password
                    if credential_provider:
                        connection_params["credential_provider"] = credential_provider
                    else:
                        connection_params["username"] = REDIS_CFG["username"]
                        connection_params["password"] = REDIS_CFG["password"]
                else:
                    redis_class: Type[Union[Redis, RedisCluster]] = redis.Redis
                    connection_params = {
                        "host": REDIS_CFG["host"],
                        "port": REDIS_CFG["port"],
                        "db": REDIS_CFG["db"],
                        "ssl": REDIS_CFG["ssl"],
                        "ssl_ca_path": REDIS_CFG["ssl_ca_path"],
                        "ssl_keyfile": REDIS_CFG["ssl_keyfile"],
                        "ssl_certfile": REDIS_CFG["ssl_certfile"],
                        "ssl_cert_reqs": REDIS_CFG["ssl_cert_reqs"],
                        "ssl_ca_certs": REDIS_CFG["ssl_ca_certs"],
                        "decode_responses": decode_responses,
                        "lib_name": f"redis-py(mcp-server_v{__version__})",
                        "max_connections": 10,
                        "socket_connect_timeout": 5,  # Add connection timeout
                        "socket_timeout": 5,  # Add socket timeout
                    }
                    
                    # Add authentication - either Entra ID or username/password
                    if credential_provider:
                        _logger.info("Using Entra ID credential provider for authentication")
                        connection_params["credential_provider"] = credential_provider
                    else:
                        connection_params["username"] = REDIS_CFG["username"]
                        connection_params["password"] = REDIS_CFG["password"]

                _logger.info("Creating Redis connection to %s:%s (SSL: %s)", 
                            REDIS_CFG["host"], REDIS_CFG["port"], REDIS_CFG["ssl"])
                cls._instance = redis_class(**connection_params)
                _logger.info("Redis connection object created successfully")

            except redis.exceptions.ConnectionError:
                _logger.error("Failed to connect to Redis server")
                raise
            except redis.exceptions.AuthenticationError:
                _logger.error("Authentication failed")
                raise
            except redis.exceptions.TimeoutError:
                _logger.error("Connection timed out")
                raise
            except redis.exceptions.ResponseError as e:
                _logger.error("Response error: %s", e)
                raise
            except redis.exceptions.RedisError as e:
                _logger.error("Redis error: %s", e)
                raise
            except redis.exceptions.ClusterError as e:
                _logger.error("Redis Cluster error: %s", e)
                raise
            except Exception as e:
                _logger.error("Unexpected error: %s", e)
                raise

        return cls._instance
