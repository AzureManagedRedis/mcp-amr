"""Authentication module for MCP server."""

import logging
from typing import Optional, List
from starlette.middleware import Middleware

# Import middleware classes directly (no dependency issues)
from .api_key_middleware import APIKeyMiddleware
from .middleware import BearerAuthMiddleware
from .entra_token_verifier import EntraIDTokenVerifier

__all__ = [
    "BearerAuthMiddleware", 
    "APIKeyMiddleware", 
    "EntraIDTokenVerifier",
    "get_auth_middleware"
]

_logger = logging.getLogger(__name__)


def get_auth_middleware(auth_config: dict) -> Optional[Middleware]:
    """Get the appropriate authentication middleware based on configuration.
    
    Args:
        auth_config: Authentication configuration dictionary with:
            - method: "NO-AUTH", "API-KEY", or "OAUTH"  
            - api_keys: Set of API keys (for API-KEY method)
            - oauth_tenant_id, oauth_client_id, oauth_required_scopes: OAuth config
    
    Returns:
        Starlette Middleware instance or None for NO-AUTH
    """
    method = auth_config.get("method", "NO-AUTH").upper()
    
    if method == "NO-AUTH":
        _logger.info("Authentication disabled (NO-AUTH)")
        return None
        
    elif method == "API-KEY":
        api_keys = auth_config.get("api_keys", set())
        if not api_keys:
            _logger.warning("API-KEY authentication selected but no API keys configured. Falling back to NO-AUTH.")
            return None
        
        _logger.info(f"Using API Key authentication with {len(api_keys)} key(s)")
        return Middleware(APIKeyMiddleware, api_keys=api_keys)
        
    elif method == "OAUTH":
        tenant_id = auth_config.get("oauth_tenant_id")
        client_id = auth_config.get("oauth_client_id") 
        required_scopes = auth_config.get("oauth_required_scopes", [])
        
        if not tenant_id or not client_id:
            _logger.warning("OAUTH authentication selected but tenant_id/client_id missing. Falling back to NO-AUTH.")
            return None
            
        _logger.info(f"Using OAuth authentication (tenant: {tenant_id}, client: {client_id})")
        
        # Create OAuth config for BearerAuthMiddleware
        oauth_cfg = {
            "enabled": True,
            "tenant_id": tenant_id,
            "client_id": client_id,
            "required_scopes": required_scopes
        }
        return Middleware(BearerAuthMiddleware, oauth_config=oauth_cfg)
        
    else:
        _logger.error(f"Unknown authentication method: {method}. Falling back to NO-AUTH.")
        return None

