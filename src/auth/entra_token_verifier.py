"""Microsoft Entra ID Token Verifier for FastMCP OAuth authentication."""

import logging
from typing import Optional
import jwt
from jwt import PyJWKClient
from mcp.server.auth.provider import TokenVerifier, AccessToken

_logger = logging.getLogger(__name__)


class EntraIDTokenVerifier(TokenVerifier):
    """Verifies Microsoft Entra ID (Azure AD) JWT tokens."""
    
    def __init__(
        self,
        tenant_id: str,
        client_id: str,
        required_scopes: Optional[list[str]] = None,
    ):
        """Initialize Entra ID token verifier.
        
        Args:
            tenant_id: Azure AD tenant ID
            client_id: Application (client) ID that tokens should be issued for
            required_scopes: Optional list of required scopes
        """
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.required_scopes = required_scopes or []
        
        # JWKS endpoint for Entra ID
        self.jwks_url = f"https://login.microsoftonline.com/{tenant_id}/discovery/v2.0/keys"
        self.issuer = f"https://login.microsoftonline.com/{tenant_id}/v2.0"
        
        # Create JWKS client (caches keys automatically)
        self.jwks_client = PyJWKClient(self.jwks_url)
        
        _logger.info("Initialized Entra ID token verifier for tenant: %s, client: %s", 
                    tenant_id, client_id)
    
    async def verify_token(self, token: str) -> AccessToken | None:
        """Verify a JWT token from Microsoft Entra ID.
        
        Args:
            token: JWT access token
            
        Returns:
            AccessToken if valid, None if invalid
        """
        try:
            _logger.debug("Verifying token...")
            _logger.debug(f"Expected audience: api://{self.client_id}")
            _logger.debug(f"Expected issuer: {self.issuer}")
            
            # Get signing key from token header
            signing_key = self.jwks_client.get_signing_key_from_jwt(token)
            _logger.debug("Got signing key from JWKS")
            
            # Decode token without validation first to check the audience format
            unverified = jwt.decode(token, options={"verify_signature": False})
            token_aud = unverified.get("aud", "")
            _logger.debug(f"Token audience: {token_aud}")
            
            # Azure CLI tokens may have audience as just the client ID without api:// prefix
            # Accept both formats: "api://{client_id}" or just "{client_id}"
            expected_audiences = [
                f"api://{self.client_id}",  # Standard Entra ID API format
                self.client_id,              # Direct client ID (used by Azure CLI)
            ]
            
            # Decode and validate token
            decoded = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                audience=expected_audiences,  # Accept multiple audience formats
                issuer=self.issuer,
                options={
                    "verify_signature": True,
                    "verify_exp": True,
                    "verify_aud": True,
                    "verify_iss": True,
                }
            )
            _logger.debug(f"Token decoded successfully. Claims: {list(decoded.keys())}")
            
            # Extract scopes from token
            # Entra ID uses "scp" claim for delegated permissions (user context)
            # and "roles" claim for application permissions (app context)
            scopes = []
            if "scp" in decoded:
                scopes = decoded["scp"].split(" ")
                _logger.debug(f"Found delegated scopes (scp): {scopes}")
            elif "roles" in decoded:
                scopes = decoded["roles"]
                _logger.debug(f"Found application roles: {scopes}")
            else:
                _logger.warning("Token has no 'scp' or 'roles' claim")
            
            # Verify required scopes with flexible matching
            if self.required_scopes:
                token_scopes_set = set(scopes)
                required_scopes_set = set(self.required_scopes)
                
                # Check if exact scopes match first
                if required_scopes_set.issubset(token_scopes_set):
                    _logger.debug("Exact scope match found")
                else:
                    # Try flexible matching for common patterns:
                    # - "MCP.Read" matches "User.MCP.Read" 
                    # - "MCP.Write" matches "User.MCP.Write"
                    flexible_match = True
                    for required_scope in required_scopes_set:
                        # Check if any token scope ends with the required scope
                        # or if any token scope matches "User.{required_scope}"
                        scope_found = any(
                            token_scope == required_scope or
                            token_scope == f"User.{required_scope}" or
                            token_scope.endswith(f".{required_scope}")
                            for token_scope in token_scopes_set
                        )
                        if not scope_found:
                            flexible_match = False
                            break
                    
                    if not flexible_match:
                        _logger.warning(
                            "Token missing required scopes. Required: %s, Present: %s",
                            required_scopes_set,
                            token_scopes_set
                        )
                        return None
                    else:
                        _logger.debug("Flexible scope match found")
            
            # Extract expiration
            exp = decoded.get("exp")
            
            _logger.info("Token validated successfully for client: %s", decoded.get("appid", decoded.get("azp", self.client_id)))
            
            # Return AccessToken
            return AccessToken(
                token=token,
                client_id=decoded.get("appid", decoded.get("azp", self.client_id)),
                scopes=scopes,
                expires_at=exp,
            )
            
        except jwt.ExpiredSignatureError:
            _logger.warning("Token has expired")
            return None
        except jwt.InvalidAudienceError as e:
            _logger.warning(f"Token audience validation failed: {e}")
            return None
        except jwt.InvalidIssuerError as e:
            _logger.warning(f"Token issuer validation failed: {e}")
            return None
        except jwt.InvalidTokenError as e:
            _logger.warning("Invalid token: %s", str(e))
            return None
        except Exception as e:
            _logger.error("Unexpected error verifying token: %s", str(e), exc_info=True)
            return None
