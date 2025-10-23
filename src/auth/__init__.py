"""Authentication module for MCP server."""

# Import middleware directly (no dependency issues)
from .middleware import BearerAuthMiddleware

# Lazy import function for EntraIDTokenVerifier to handle optional JWT dependencies
def get_entra_token_verifier():
    """Lazy import of EntraIDTokenVerifier to handle optional dependencies.
    
    This avoids importing JWT dependencies at module load time, which allows
    the auth package to be imported even when JWT libraries aren't available.
    
    Returns:
        EntraIDTokenVerifier class (not an instance)
    """
    from .entra_token_verifier import EntraIDTokenVerifier
    return EntraIDTokenVerifier

__all__ = ["BearerAuthMiddleware", "get_entra_token_verifier"]
