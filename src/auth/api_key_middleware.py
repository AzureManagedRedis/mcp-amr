"""API Key authentication middleware for HTTP server."""

import logging
import secrets
from typing import Optional, Set

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

_logger = logging.getLogger(__name__)


class APIKeyMiddleware(BaseHTTPMiddleware):
    """Middleware to validate API keys for HTTP endpoints."""
    
    def __init__(self, app, api_keys: Optional[Set[str]] = None):
        """Initialize API key middleware.
        
        Args:
            app: Starlette application
            api_keys: Set of valid API keys. If None or empty, auth is disabled.
        """
        super().__init__(app)
        self.api_keys = api_keys or set()
        self.auth_enabled = bool(self.api_keys)
        
        if self.auth_enabled:
            _logger.info(f"API Key authentication enabled with {len(self.api_keys)} valid key(s)")
        else:
            _logger.info("API Key authentication disabled")
    
    async def dispatch(self, request: Request, call_next):
        """Validate API key before processing request."""
        # Skip auth for health check
        if request.url.path == "/health":
            return await call_next(request)
        
        # If auth is disabled, allow all requests
        if not self.auth_enabled:
            return await call_next(request)
        
        # Check for API key in X-API-Key header
        api_key = request.headers.get("X-API-Key")
        
        if not api_key:
            _logger.warning(
                f"Missing API key from {request.client.host if request.client else 'unknown'}"
            )
            return JSONResponse(
                content={
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {
                        "code": -32001,
                        "message": "Missing X-API-Key header"
                    }
                },
                status_code=401,
                headers={"WWW-Authenticate": 'ApiKey realm="MCP Server"'}
            )
        
        # Validate API key using constant-time comparison
        if not self._is_valid_key(api_key):
            _logger.warning(
                f"Invalid API key from {request.client.host if request.client else 'unknown'}"
            )
            return JSONResponse(
                content={
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {
                        "code": -32001,
                        "message": "Invalid API key"
                    }
                },
                status_code=401,
                headers={"WWW-Authenticate": 'ApiKey realm="MCP Server"'}
            )
        
        # API key is valid
        _logger.info(
            f"Authenticated request from {request.client.host if request.client else 'unknown'}"
        )
        return await call_next(request)
    
    def _is_valid_key(self, provided_key: str) -> bool:
        """Validate API key using constant-time comparison.
        
        Args:
            provided_key: API key from request
            
        Returns:
            True if key is valid, False otherwise
        """
        # Use constant-time comparison to prevent timing attacks
        for valid_key in self.api_keys:
            if secrets.compare_digest(provided_key, valid_key):
                return True
        return False
