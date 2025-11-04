import json
import logging
from typing import Union

from redis.exceptions import RedisError
from redis import Redis

from src.common.connection import RedisConnectionManager, run_redis_command
from src.common.server import mcp


@mcp.tool()
async def set(
    key: str,
    value: str,
    expiration: int = 0,
) -> str:
    """Set a Redis string value with an optional expiration time.

    Args:
        key (str): The key to set.
        value (str): The value to store. For JSON objects, pass as JSON string.
        expiration (int): Expiration time in seconds. Use 0 for no expiration (default: 0).

    Returns:
        str: Confirmation message or an error message.
    """
    # Try to parse as JSON if it looks like JSON
    try:
        parsed = json.loads(value)
        if isinstance(parsed, dict):
            encoded_value = json.dumps(parsed).encode("utf-8")
        else:
            encoded_value = value.encode("utf-8")
    except (json.JSONDecodeError, TypeError):
        encoded_value = value.encode("utf-8")

    try:
        r: Redis = RedisConnectionManager.get_connection()
        
        # Run the blocking Redis call in an executor to avoid blocking the event loop
        if expiration and expiration > 0:
            await run_redis_command(r.setex, key, expiration, encoded_value)
        else:
            await run_redis_command(r.set, key, encoded_value)

        return f"Successfully set {key}" + (
            f" with expiration {expiration} seconds" if expiration and expiration > 0 else ""
        )
    except RedisError as e:
        return f"Error setting key {key}: {str(e)}"


@mcp.tool()
async def get(key: str) -> Union[str, bytes]:
    """Get a Redis string value.

    Args:
        key (str): The key to retrieve.

    Returns:
        str, bytes: The stored value or an error message.
    """
    _logger = logging.getLogger(__name__)
    
    try:
        _logger.debug("Getting Redis connection for key: %s", key)
        r: Redis = RedisConnectionManager.get_connection()
        _logger.debug("Got Redis connection object, executing GET command")
        
        # Run the blocking Redis call in an executor to avoid blocking the event loop
        value = await run_redis_command(r.get, key)
        _logger.debug("GET command completed, value retrieved")

        if value is None:
            return f"Key {key} does not exist"

        if isinstance(value, bytes):
            try:
                text = value.decode("utf-8")
                return text
            except UnicodeDecodeError:
                return value

        return str(value)
    except RedisError as e:
        _logger.error("Redis error retrieving key %s: %s", key, str(e))
        return f"Error retrieving key {key}: {str(e)}"
    except Exception as e:
        _logger.error("Unexpected error retrieving key %s: %s", key, str(e))
        return f"Unexpected error retrieving key {key}: {str(e)}"
