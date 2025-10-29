"""HTTP/SSE server wrapper for Redis MCP Server.

This module provides an HTTP server with Server-Sent Events (SSE) transport
for the Redis MCP Server, enabling remote access via HTTP instead of stdio.
"""

import asyncio
import json
import logging
import inspect
from typing import Any, Dict, List, Optional

from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import Response, JSONResponse
from starlette.routing import Route
from starlette.middleware import Middleware
from sse_starlette import EventSourceResponse
import uvicorn

from src.common.server import mcp
from src.common.config import AUTH_CFG
from src.common.logging_utils import configure_logging
from src.auth import get_auth_middleware

# Configure logging
configure_logging()
logger = logging.getLogger(__name__)



async def get_tools_list() -> List[Dict[str, Any]]:
    """Get list of all registered MCP tools.
    
    Returns:
        List of tool definitions with name, description, and input schema.
    """
    try:
        logger.debug("Calling mcp.list_tools()")
        # mcp.list_tools() returns a list of MCPTool Pydantic models
        mcp_tools = await mcp.list_tools()
        
        logger.info(f"Got {len(mcp_tools)} tools from mcp.list_tools()")
        
        # Convert Pydantic models to dicts for JSON serialization
        return [tool.model_dump(exclude_none=True) for tool in mcp_tools]
        
    except Exception as e:
        logger.error(f"Error calling mcp.list_tools(): {e}", exc_info=True)
        return []


async def call_tool(tool_name: str, arguments: Dict[str, Any]) -> Any:
    """Execute a registered MCP tool.
    
    Args:
        tool_name: Name of the tool to execute
        arguments: Dictionary of arguments to pass to the tool
        
    Returns:
        Tool execution result
    """
    try:
        logger.debug(f"Calling tool via mcp.call_tool: {tool_name}")
        # mcp.call_tool is async and returns the tool result
        # It handles context injection and result conversion automatically
        return await mcp.call_tool(tool_name, arguments)
        
    except Exception as e:
        logger.error(f"Error calling tool '{tool_name}': {e}", exc_info=True)
        raise


async def health_check(request: Request) -> Response:
    """Health check endpoint for container orchestration."""
    return Response(content="OK", status_code=200, media_type="text/plain")


async def mcp_sse_endpoint(request: Request) -> EventSourceResponse:
    """SSE endpoint for MCP protocol communication.
    
    This implements the MCP SSE transport as described in:
    https://modelcontextprotocol.io/docs/concepts/transports#http-with-sse
    """
    logger.info(f"New SSE connection from {request.client.host if request.client else 'unknown'}")
    
    async def event_generator():
        """Generate SSE events for MCP communication."""
        try:
            # Send initial connection event
            yield {
                "event": "endpoint",
                "data": "/message"
            }
            
            # Keep connection alive
            while True:
                # Send periodic heartbeat to keep connection alive
                await asyncio.sleep(15)
                # SSE comment to keep connection alive
                yield {"comment": "keepalive"}
                
        except asyncio.CancelledError:
            logger.info("SSE connection closed")
        except Exception as e:
            logger.error(f"Error in SSE endpoint: {e}", exc_info=True)
    
    return EventSourceResponse(
        event_generator(),
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no"
        }
    )


async def mcp_message_endpoint(request: Request) -> Response:
    """Handle MCP JSON-RPC messages.
    
    This endpoint receives POST requests with MCP protocol messages
    and returns the server's response.
    """
    try:
        body = await request.body()
        if not body:
            return Response(
                content=json.dumps({"error": "Empty request body"}),
                media_type="application/json",
                status_code=400
            )
        
        message = json.loads(body.decode())
        method = message.get("method")
        msg_id = message.get("id")
        params = message.get("params", {})
        
        logger.info(f"Received MCP message: {method}")
        logger.debug(f"Full message: {message}")
        
        # Handle different MCP methods
        if method == "initialize":
            response = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {
                        "tools": {},
                        "resources": {},
                        "prompts": {}
                    },
                    "serverInfo": {
                        "name": "Redis MCP Server",
                        "version": "0.3.4"
                    }
                }
            }
        elif method == "tools/list":
            # Get all registered tools from FastMCP
            tools = await get_tools_list()
            logger.info(f"Returning {len(tools)} tools")
            response = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "tools": tools
                }
            }
        elif method == "tools/call":
            # Execute a tool
            tool_name = params.get("name")
            arguments = params.get("arguments", {})
            
            logger.info(f"Calling tool: {tool_name} with args: {arguments}")
            
            try:
                result = await call_tool(tool_name, arguments)
                
                # Format result as MCP content
                response = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": str(result)
                            }
                        ]
                    }
                }
            except Exception as tool_error:
                logger.error(f"Tool execution error: {tool_error}", exc_info=True)
                response = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "error": {
                        "code": -32000,
                        "message": f"Tool execution failed: {str(tool_error)}"
                    }
                }
        else:
            # Unknown method
            logger.warning(f"Unknown method: {method}")
            response = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "error": {
                    "code": -32601,
                    "message": f"Method not found: {method}"
                }
            }
        
        return Response(
            content=json.dumps(response),
            media_type="application/json",
            status_code=200
        )
        
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in request: {e}")
        return Response(
            content=json.dumps({
                "jsonrpc": "2.0",
                "id": None,
                "error": {
                    "code": -32700,
                    "message": "Parse error: Invalid JSON"
                }
            }),
            media_type="application/json",
            status_code=400
        )
    except Exception as e:
        logger.error(f"Error processing MCP request: {e}", exc_info=True)
        error_response = {
            "jsonrpc": "2.0",
            "id": message.get("id") if 'message' in locals() else None,
            "error": {
                "code": -32603,
                "message": f"Internal error: {str(e)}"
            }
        }
        return Response(
            content=json.dumps(error_response),
            media_type="application/json",
            status_code=500
        )


# Create Starlette app with consolidated authentication
def create_app() -> Starlette:
    """Create Starlette app with configurable authentication middleware."""
    # Get appropriate middleware based on AUTH_CFG - all initialization handled in auth module
    middleware = []
    auth_middleware = get_auth_middleware(AUTH_CFG)
    
    if auth_middleware:
        middleware.append(auth_middleware)
    
    return Starlette(
        debug=False,
        routes=[
            Route("/health", health_check, methods=["GET"]),
            Route("/sse", mcp_sse_endpoint, methods=["GET"]),
            Route("/message", mcp_message_endpoint, methods=["POST"]),
        ],
        middleware=middleware
    )


app = create_app()


def run_server(host: str = "0.0.0.0", port: int = 8000):
    """Run the HTTP/SSE server for MCP.
    
    Args:
        host: Host to bind to (default: 0.0.0.0 for container deployment)
        port: Port to bind to (default: 8000)
    """
    # Pre-load semantic cache embedding model and initialize Redis connection at startup
    # This prevents delays/timeouts when the first semantic cache tool is called
    try:
        logger.info("Pre-loading semantic cache (model + Redis connection)...")
        from src.tools.semantic_cache import _get_vectorizer, _get_or_create_cache
        
        # Load embedding model
        vectorizer = _get_vectorizer()
        logger.info(f"Embedding model loaded (dims={vectorizer.dims})")
        
        # Initialize a dummy cache to trigger Redis connection and Entra ID token manager
        # This ensures the token manager starts during server initialization, not during first tool call
        _get_or_create_cache("_warmup_cache")
        logger.info("Semantic cache pre-loaded successfully (model + Redis connection ready)")
    except Exception as e:
        # Log but don't fail startup - the model will be loaded on first use if this fails
        logger.warning(f"Failed to pre-load semantic cache (will load on first use): {e}")
    
    # Log registered tools - need to run async function
    tools = asyncio.run(get_tools_list())
    
    logger.info("=" * 60)
    logger.info(f"Starting Redis MCP HTTP/SSE Server")
    logger.info(f"Listening on {host}:{port}")
    logger.info("=" * 60)
    
    # Log consolidated authentication status
    auth_method = AUTH_CFG.get("method", "NO-AUTH")
    if auth_method == "NO-AUTH":
        logger.info("🔓 Authentication: DISABLED")
        logger.info("   All requests allowed without authentication")
    elif auth_method == "API-KEY":
        num_keys = len(AUTH_CFG.get("api_keys", set()))
        logger.info("🔒 Authentication: API KEY")
        logger.info(f"   Configured API Keys: {num_keys}")
        logger.info("   All requests must include valid X-API-Key header")
    elif auth_method == "OAUTH":
        logger.info("🔒 Authentication: OAUTH")
        logger.info(f"   Tenant ID: {AUTH_CFG.get('oauth_tenant_id')}")
        logger.info(f"   Client ID: {AUTH_CFG.get('oauth_client_id')}")
        if AUTH_CFG.get('oauth_required_scopes'):
            logger.info(f"   Required Scopes: {', '.join(AUTH_CFG['oauth_required_scopes'])}")
        logger.info("   All requests must include valid Bearer token")
    logger.info("=" * 60)
    
    logger.info("Available endpoints:")
    logger.info(f"  - GET  /health   - Health check endpoint (no auth required)")
    logger.info(f"  - GET  /sse      - SSE endpoint for MCP transport")
    logger.info(f"  - POST /message  - MCP JSON-RPC message endpoint")
    logger.info("=" * 60)
    logger.info(f"Registered {len(tools)} MCP tools:")
    for tool in tools:
        logger.info(f"  - {tool['name']}")
    logger.info("=" * 60)
    
    uvicorn.run(
        app,
        host=host,
        port=port,
        log_level="info",
        access_log=True,
        timeout_keep_alive=30
    )


if __name__ == "__main__":
    run_server()
