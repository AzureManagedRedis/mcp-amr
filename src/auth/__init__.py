"""Authentication module for MCP server."""

from .api_key_middleware import APIKeyMiddleware

__all__ = ["APIKeyMiddleware"]
