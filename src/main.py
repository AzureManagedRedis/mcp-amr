import sys
import logging

import click

from src.common.config import parse_redis_uri, set_redis_config_from_cli
from src.common.server import mcp
from src.common.logging_utils import configure_logging


class RedisMCPServer:
    def __init__(self):
        # Configure logging on server initialization (idempotent)
        configure_logging()
        self._logger = logging.getLogger(__name__)
        self._logger.info("Starting the Redis MCP Server")

    def _preload_semantic_cache_model(self):
        """Pre-load the semantic cache embedding model at startup.
        
        This prevents timeout issues when the first semantic cache tool is called,
        as loading the model can take 10-30 seconds on cold start.
        """
        try:
            self._logger.info("Pre-loading semantic cache embedding model...")
            from src.tools.knowledge_store import _get_vectorizer
            vectorizer = _get_vectorizer()
            self._logger.info(f"Semantic cache model pre-loaded successfully (dims={vectorizer.dims})")
        except Exception as e:
            # Log but don't fail startup - the model will be loaded on first use if this fails
            self._logger.warning(f"Failed to pre-load semantic cache model (will load on first use): {e}")

    def run(self):
        # Pre-load model before starting the MCP server
        self._preload_semantic_cache_model()
        mcp.run()


@click.command()
@click.option(
    "--url",
    help="Redis connection URI (redis://user:pass@host:port/db or rediss:// for SSL)",
)
@click.option("--host", default="127.0.0.1", help="Redis host")
@click.option("--port", default=6379, type=int, help="Redis port")
@click.option("--db", default=0, type=int, help="Redis database number")
@click.option("--username", help="Redis username")
@click.option("--password", help="Redis password")
@click.option("--ssl", is_flag=True, help="Use SSL connection")
@click.option("--ssl-ca-path", help="Path to CA certificate file")
@click.option("--ssl-keyfile", help="Path to SSL key file")
@click.option("--ssl-certfile", help="Path to SSL certificate file")
@click.option(
    "--ssl-cert-reqs", default="required", help="SSL certificate requirements"
)
@click.option("--ssl-ca-certs", help="Path to CA certificates file")
@click.option("--cluster-mode", is_flag=True, help="Enable Redis cluster mode")
@click.option(
    "--entraid-auth-method",
    type=click.Choice(["service_principal", "managed_identity", "default_azure_credential"], case_sensitive=False),
    help="Entra ID authentication method (service_principal, managed_identity, or default_azure_credential)"
)
@click.option("--entraid-tenant-id", help="Entra ID tenant ID (for service_principal)")
@click.option("--entraid-client-id", help="Entra ID client ID (for service_principal)")
@click.option("--entraid-cert-path", help="Path to Entra ID certificate file (for service_principal)")
@click.option("--entraid-managed-identity-client-id", help="Managed identity client ID (for user-assigned managed_identity)")
def cli(
    url,
    host,
    port,
    db,
    username,
    password,
    ssl,
    ssl_ca_path,
    ssl_keyfile,
    ssl_certfile,
    ssl_cert_reqs,
    ssl_ca_certs,
    cluster_mode,
    entraid_auth_method,
    entraid_tenant_id,
    entraid_client_id,
    entraid_cert_path,
    entraid_managed_identity_client_id,
):
    """Redis MCP Server - Model Context Protocol server for Redis."""

    # Handle Redis URI if provided (and not empty)
    # Note: gemini-cli passes the raw "${REDIS_URL}" string when the env var is not set

    if url and url.strip() and url.strip() != "${REDIS_URL}":
        try:
            uri_config = parse_redis_uri(url)
            set_redis_config_from_cli(uri_config)
        except ValueError as e:
            click.echo(f"Error parsing Redis URI: {e}", err=True)
            sys.exit(1)
    else:
        # Set individual Redis parameters
        config = {
            "host": host,
            "port": port,
            "db": db,
            "ssl": ssl,
            "cluster_mode": cluster_mode,
        }

        if username:
            config["username"] = username
        if password:
            config["password"] = password
        if ssl_ca_path:
            config["ssl_ca_path"] = ssl_ca_path
        if ssl_keyfile:
            config["ssl_keyfile"] = ssl_keyfile
        if ssl_certfile:
            config["ssl_certfile"] = ssl_certfile
        if ssl_cert_reqs:
            config["ssl_cert_reqs"] = ssl_cert_reqs
        if ssl_ca_certs:
            config["ssl_ca_certs"] = ssl_ca_certs
        
        # Add Entra ID authentication parameters
        if entraid_auth_method:
            config["entraid_auth_method"] = entraid_auth_method
        if entraid_tenant_id:
            config["entraid_tenant_id"] = entraid_tenant_id
        if entraid_client_id:
            config["entraid_client_id"] = entraid_client_id
        if entraid_cert_path:
            config["entraid_cert_path"] = entraid_cert_path
        if entraid_managed_identity_client_id:
            config["entraid_managed_identity_client_id"] = entraid_managed_identity_client_id

        set_redis_config_from_cli(config)

    # Start the server
    server = RedisMCPServer()
    server.run()


def main():
    """Legacy main function for backward compatibility."""
    server = RedisMCPServer()
    server.run()


if __name__ == "__main__":
    main()
