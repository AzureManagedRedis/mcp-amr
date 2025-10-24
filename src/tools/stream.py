from typing import Dict, Any

from redis.exceptions import RedisError

from src.common.connection import RedisConnectionManager, run_redis_command
from src.common.server import mcp


@mcp.tool()
async def xadd(
    key: str, fields: Dict[str, Any], expiration: int = 0
) -> str:
    """Add an entry to a Redis stream with an optional expiration time.

    Args:
        key (str): The stream key.
        fields (dict): The fields and values for the stream entry.
        expiration (int): Expiration time in seconds. Use 0 for no expiration (default: 0).

    Returns:
        str: The ID of the added entry or an error message.
    """
    try:
        r = RedisConnectionManager.get_connection()
        entry_id = await run_redis_command(r.xadd, key, fields)
        if expiration and expiration > 0:
            await run_redis_command(r.expire, key, expiration)
        return f"Successfully added entry {entry_id} to {key}" + (
            f" with expiration {expiration} seconds" if expiration and expiration > 0 else ""
        )
    except RedisError as e:
        return f"Error adding to stream {key}: {str(e)}"


@mcp.tool()
async def xrange(key: str, count: int = 1) -> str:
    """Read entries from a Redis stream.

    Args:
        key (str): The stream key.
        count (int, optional): Number of entries to retrieve.

    Returns:
        str: The retrieved stream entries or an error message.
    """
    try:
        r = RedisConnectionManager.get_connection()
        entries = await run_redis_command(r.xrange, key, count=count)
        return str(entries) if entries else f"Stream {key} is empty or does not exist"
    except RedisError as e:
        return f"Error reading from stream {key}: {str(e)}"


@mcp.tool()
async def xdel(key: str, entry_id: str) -> str:
    """Delete an entry from a Redis stream.

    Args:
        key (str): The stream key.
        entry_id (str): The ID of the entry to delete.

    Returns:
        str: Confirmation message or an error message.
    """
    try:
        r = RedisConnectionManager.get_connection()
        result = await run_redis_command(r.xdel, key, entry_id)
        return (
            f"Successfully deleted entry {entry_id} from {key}"
            if result
            else f"Entry {entry_id} not found in {key}"
        )
    except RedisError as e:
        return f"Error deleting from stream {key}: {str(e)}"
