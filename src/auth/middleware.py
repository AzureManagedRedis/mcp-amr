"""Authentication middleware for HTTP server."""

import logging
from typing import Optional, Dict, Any

from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger(__name__)


class BearerAuthMiddleware(BaseHTTPMiddleware):
    """Middleware to validate Bearer tokens for OAuth-protected endpoints."""
    
    def __init__(self, app, oauth_config: Optional[Dict[str, Any]] = None, token_verifier=None):
        super().__init__(app)
        self.oauth_config = oauth_config or {}
        self.token_verifier = token_verifier
        self.oauth_enabled = self.oauth_config.get("enabled", False)
        
        if self.oauth_enabled:
            logger.info("OAuth authentication enabled for HTTP server")
        else:
            logger.info("OAuth authentication disabled for HTTP server")
    
    async def dispatch(self, request: Request, call_next):
        """Validate Bearer token before processing request."""
        # Skip auth for health check
        if request.url.path == "/health":
            return await call_next(request)
        
        # If OAuth is disabled, allow all requests
        if not self.oauth_enabled or not self.token_verifier:
            return await call_next(request)
        
        # Extract Bearer token from Authorization header
        auth_header = request.headers.get("Authorization")
        if not auth_header:
            logger.warning(f"Missing Authorization header from {request.client.host if request.client else 'unknown'}")
            return JSONResponse(
                content={
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {
                        "code": -32001,
                        "message": "Missing Authorization header"
                    }
                },
                status_code=401
            )
        
        # Parse Bearer token
        parts = auth_header.split()
        if len(parts) != 2 or parts[0].lower() != "bearer":
            logger.warning(f"Invalid Authorization header format from {request.client.host if request.client else 'unknown'}")
            return JSONResponse(
                content={
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {
                        "code": -32001,
                        "message": "Invalid Authorization header format. Expected: Bearer <token>"
                    }
                },
                status_code=401
            )
        
        token = parts[1]
        
        # Verify token
        try:
            access_token = await self.token_verifier.verify_token(token)
            if not access_token:
                logger.warning(f"Invalid or expired token from {request.client.host if request.client else 'unknown'}")
                return JSONResponse(
                    content={
                        "jsonrpc": "2.0",
                        "id": None,
                        "error": {
                            "code": -32001,
                            "message": "Invalid or expired access token"
                        }
                    },
                    status_code=401
                )
            
            # Token is valid, store it in request state for potential use
            request.state.access_token = access_token
            logger.info(f"Authenticated request from client {access_token.client_id} with scopes: {access_token.scopes}")
            
        except Exception as e:
            logger.error(f"Token verification error: {e}", exc_info=True)
            return JSONResponse(
                content={
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {
                        "code": -32001,
                        "message": f"Token verification failed: {str(e)}"
                    }
                },
                status_code=401
            )
        
        return await call_next(request)