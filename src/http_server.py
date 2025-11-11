"""HTTP/SSE server wrapper for Redis MCP Server.

This module provides an HTTP server with Server-Sent Events (SSE) transport
for the Redis MCP Server, enabling remote access via HTTP instead of stdio.

SSE Transport Implementation:
- GET /sse: Establishes SSE connection, server sends "endpoint" event with "/message" URL
- POST /message: Client sends JSON-RPC requests, server responds with JSON-RPC responses
"""

import asyncio
import json
import logging
import uuid
from typing import Any, Dict, List

from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import Response
from starlette.routing import Route
from sse_starlette import EventSourceResponse
import uvicorn

from src.common.server import mcp
from src.common.config import AUTH_CFG
from src.common.logging_utils import configure_logging
from src.auth import get_auth_middleware

# Configure logging
configure_logging()
logger = logging.getLogger(__name__)

# Store active SSE connections for each session
# session_id -> asyncio.Queue for sending messages to client
_sse_sessions: Dict[str, asyncio.Queue] = {}



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
    
    According to MCP spec, this endpoint:
    1. Establishes an SSE connection
    2. Sends an initial "endpoint" event with the message endpoint URL
    3. Can send "message" events containing JSON-RPC responses
    4. Keeps connection alive with periodic events
    
    Spec: https://modelcontextprotocol.io/specification/2024-11-05/basic/transports#http-with-sse
    """
    # Generate unique session ID for this connection
    session_id = str(uuid.uuid4())
    message_queue = asyncio.Queue()
    _sse_sessions[session_id] = message_queue
    
    logger.info(f"New SSE connection - session: {session_id} from {request.client.host if request.client else 'unknown'}")
    
    async def event_generator():
        """Generate SSE events for MCP communication."""
        try:
            # Send session ID first so client knows which session to use
            yield {
                "event": "session",
                "data": session_id
            }
            
            # Send initial endpoint event as per MCP spec
            # Include session ID as query parameter for the endpoint URL
            yield {
                "event": "endpoint",
                "data": f"/message?sessionId={session_id}"
            }
            
            # Main event loop: send queued messages and keepalives
            while True:
                try:
                    # Wait for message with timeout for keepalive
                    message = await asyncio.wait_for(message_queue.get(), timeout=15.0)
                    
                    # Send message event with JSON-RPC response
                    yield {
                        "event": "message",
                        "data": json.dumps(message)
                    }
                    
                except asyncio.TimeoutError:
                    # Send keepalive comment to prevent connection timeout
                    yield {"comment": "keepalive"}
                    
        except asyncio.CancelledError:
            logger.info(f"SSE connection closed - session: {session_id}")
        except Exception as e:
            logger.error(f"Error in SSE endpoint - session: {session_id}: {e}", exc_info=True)
        finally:
            # Clean up session
            if session_id in _sse_sessions:
                del _sse_sessions[session_id]
    
    return EventSourceResponse(
        event_generator(),
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no"
        }
    )


async def mcp_message_endpoint(request: Request) -> Response:
    """Handle MCP JSON-RPC messages.
    
    According to MCP spec, this endpoint:
    1. Receives JSON-RPC requests via POST
    2. For SSE transport: queues response to be sent via SSE "message" event (returns 202 Accepted)
    3. For direct HTTP: returns JSON-RPC response immediately (returns 200 OK)
    
    The client indicates SSE mode by including the session ID as a query parameter (?sessionId=xxx).
    
    Spec: https://modelcontextprotocol.io/specification/2024-11-05/basic/transports#http-with-sse
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
        
        # Check if this is an SSE session (client sends session ID as query parameter)
        session_id = request.query_params.get("sessionId")
        use_sse = session_id and session_id in _sse_sessions

        logger.info(f"Received MCP message: {method} (SSE: {use_sse}, session: {session_id}, message id: {msg_id})")
        logger.debug(f"Full message: {message}")
        
        # Handle notifications (no id field, no response expected)
        if msg_id is None:
            logger.debug(f"Handling notification: {method}")
            
            if method == "notifications/initialized":
                # Client has completed initialization
                logger.info("Client initialization complete")
            elif method == "notifications/cancelled":
                # Client cancelled a request
                logger.info(f"Request cancelled: {params}")
            else:
                logger.debug(f"Received notification: {method}")
            
            # For notifications, return 204 No Content (no response body)
            return Response(
                content="",
                status_code=204
            )
        
        # Handle different MCP methods (requests that expect responses)
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
                
                # FastMCP can return either:
                # 1. A list of TextContent objects directly
                # 2. A tuple of (content_list, raw_result_dict)
                
                content_list = None
                if isinstance(result, list):
                    # Direct list of TextContent objects
                    content_list = result
                elif isinstance(result, tuple) and len(result) >= 1:
                    # Tuple format: extract first element
                    content_list = result[0]
                
                if content_list is not None:
                    # Convert Pydantic models to JSON-serializable dicts
                    content = []
                    for item in content_list:
                        if hasattr(item, 'model_dump'):
                            # Convert Pydantic model (TextContent, etc.) to dict
                            content.append(item.model_dump(exclude_none=True))
                        elif isinstance(item, dict):
                            content.append(item)
                        else:
                            # Fallback - wrap as text
                            content.append({"type": "text", "text": str(item)})
                else:
                    # Fallback: wrap unknown result as text
                    content = [{"type": "text", "text": str(result)}]
                
                # Format result as MCP content
                response = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {
                        "content": content
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
        
        # Send response based on transport mode
        if use_sse:
            # SSE mode: queue response for delivery via SSE, return 202 Accepted
            try:
                await _sse_sessions[session_id].put(response)
                logger.debug(f"Queued response for SSE session: {session_id}")
                return Response(
                    content="",
                    status_code=202  # Accepted
                )
            except KeyError:
                # Session no longer exists
                logger.warning(f"SSE session {session_id} not found")
                return Response(
                    content=json.dumps({
                        "error": "SSE session not found or expired"
                    }),
                    media_type="application/json",
                    status_code=404
                )
        else:
            # Direct HTTP mode: return response immediately
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
    # Pre-load semantic cache embedding model at startup to avoid first-call delays
    try:
        logger.info("Pre-loading semantic cache embedding model...")
        from src.tools.knowledge_store import _get_vectorizer
        vectorizer = _get_vectorizer()
        logger.info(f"Semantic cache model pre-loaded successfully (dims={vectorizer.dims})")
    except Exception as e:
        # Log but don't fail startup - the model will be loaded on first use if this fails
        logger.warning(f"Failed to pre-load semantic cache model (will load on first use): {e}")
    
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
