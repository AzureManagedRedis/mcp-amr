"""Semantic Caching Tools for Redis MCP Server

These tools provide semantic caching capabilities using vector search,
allowing you to store and retrieve data based on semantic similarity.
"""

import json
import logging
from typing import List, Dict, Any, Optional, Union

from redis.exceptions import RedisError
from redisvl.extensions.cache.llm import SemanticCache
from redisvl.utils.vectorize.text.huggingface import HFTextVectorizer

from src.common.connection import RedisConnectionManager
from src.common.server import mcp

# Logger
_logger = logging.getLogger(__name__)

# Cache instances storage
_cache_instances: Dict[str, SemanticCache] = {}

# Pre-load the embedding model at module import time to avoid delays during first use
_vectorizer: Optional[HFTextVectorizer] = None

def _get_vectorizer() -> HFTextVectorizer:
    """Get or create the HuggingFace vectorizer instance.
    
    The model is loaded once and reused across all cache instances for efficiency.
    Using 'redis/langcache-embed-v1' which is specifically optimized for semantic
    caching - it provides excellent accuracy with faster inference and lower memory
    usage compared to general-purpose models.
    
    Returns:
        HFTextVectorizer: The vectorizer instance
    """
    global _vectorizer
    
    if _vectorizer is None:
        _logger.info("Loading Redis semantic cache embedding model (this may take a moment on first use)...")
        try:
            _vectorizer = HFTextVectorizer(
                model="redis/langcache-embed-v1"
            )
            _logger.info(f"Embedding model loaded successfully (dims={_vectorizer.dims})")
        except Exception as e:
            _logger.error(f"Failed to load embedding model: {e}")
            raise
    
    return _vectorizer


def _get_or_create_cache(
    cache_name: str,
    distance_threshold: float = 0.4,
    ttl: Optional[int] = None
) -> SemanticCache:
    """Get or create a semantic cache instance.
    
    Args:
        cache_name: Name of the cache
        distance_threshold: Maximum vector distance for cache hits (0.0-1.0)
        ttl: Time-to-live in seconds for cache entries
        
    Returns:
        SemanticCache instance
    """
    # Cache key should only include name and distance_threshold, not TTL
    # TTL is applied per-entry during store operations, not at cache level
    cache_key = f"{cache_name}:{distance_threshold}"
    
    if cache_key not in _cache_instances:
        # Get sync Redis connection (SemanticCache only supports sync client)
        redis_client = RedisConnectionManager.get_connection()
        
        # Get pre-loaded vectorizer
        vectorizer = _get_vectorizer()
        
        _logger.info(f"Creating semantic cache: {cache_name} (threshold={distance_threshold}, ttl={ttl})")
        
        _cache_instances[cache_key] = SemanticCache(
            name=cache_name,
            redis_client=redis_client,
            distance_threshold=distance_threshold,
            ttl=ttl,
            vectorizer=vectorizer
        )
    
    return _cache_instances[cache_key]


@mcp.tool()
async def semantic_cache_store(
    cache_name: str,
    prompt: str,
    response: str,
    metadata: Optional[Dict[str, Any]] = None,
    distance_threshold: float = 0.4,
    ttl: int = 0
) -> str:
    """Store data in a semantic cache for later retrieval by similarity search.
    
    This tool uses vector embeddings to enable semantic search - you can retrieve
    stored data by searching for similar prompts, not just exact matches.
    
    Args:
        cache_name (str): Name of the cache (e.g., "product-search", "qa-cache")
        prompt (str): The text content to use for semantic matching (e.g., query, description)
        response (str): The associated response/data to store
        metadata (dict, optional): Additional metadata as key-value pairs
        distance_threshold (float): Maximum vector distance for cache hits (0.0-1.0, default 0.4).
                                   Lower values = stricter matching, higher = more lenient
        ttl (int): Time-to-live in seconds (0 = no expiration, default 0)
    
    Returns:
        str: Success confirmation or error message
        
    Example:
        Store a product description:
        semantic_cache_store(
            cache_name="products",
            prompt="High-performance laptop with 32GB RAM, RTX 4080, 4K display",
            response="Dell XPS 17 - $2,999",
            metadata={"brand": "Dell", "category": "laptop", "price": 2999},
            ttl=3600
        )
    """
    try:
        cache = _get_or_create_cache(cache_name, distance_threshold, ttl if ttl > 0 else None)
        
        # Prepare metadata
        metadata_dict = metadata or {}
        if isinstance(metadata, str):
            try:
                metadata_dict = json.loads(metadata)
            except json.JSONDecodeError:
                _logger.warning(f"Failed to parse metadata as JSON, treating as string")
                metadata_dict = {"raw": metadata}
        
        # Store in cache using sync method wrapped in executor
        from src.common.connection import run_redis_command
        await run_redis_command(
            cache.store,
            prompt=prompt,
            response=response,
            metadata=metadata_dict
        )
        
        _logger.info(f"Stored entry in cache '{cache_name}': {prompt[:50]}...")
        
        return (
            f"✓ Successfully stored in cache '{cache_name}'\n"
            f"Prompt: {prompt[:100]}{'...' if len(prompt) > 100 else ''}\n"
            f"Response: {response[:100]}{'...' if len(response) > 100 else ''}\n"
            f"TTL: {ttl if ttl > 0 else 'No expiration'}"
        )
        
    except RedisError as e:
        error_msg = f"Redis error storing in cache '{cache_name}': {str(e)}"
        _logger.error(error_msg)
        return f"✗ {error_msg}"
    except Exception as e:
        error_msg = f"Error storing in cache '{cache_name}': {str(e)}"
        _logger.error(error_msg)
        return f"✗ {error_msg}"


@mcp.tool()
async def semantic_cache_search(
    cache_name: str,
    query: str,
    num_results: int = 5,
    distance_threshold: float = 0.4,
    return_metadata: bool = True
) -> Union[str, List[Dict[str, Any]]]:
    """Search the semantic cache using vector similarity to find relevant entries.
    
    This performs a semantic search, finding entries with similar meaning to your query,
    not just exact keyword matches.
    
    Args:
        cache_name (str): Name of the cache to search
        query (str): The search query/prompt to find similar entries
        num_results (int): Maximum number of results to return (default 5)
        distance_threshold (float): Maximum vector distance for matches (0.0-1.0, default 0.4).
                                   Lower = stricter matching, higher = more lenient
        return_metadata (bool): Whether to include metadata in results (default True)
    
    Returns:
        list|str: List of matching entries with response, similarity score, and metadata,
                 or error message if search fails
        
    Example:
        Search for laptops:
        results = semantic_cache_search(
            cache_name="products",
            query="gaming laptop with good graphics card",
            num_results=3
        )
        
        # Results will include entries about high-performance laptops,
        # even if they don't mention "gaming" explicitly
    """
    try:
        cache = _get_or_create_cache(cache_name, distance_threshold, None)
        
        # Perform semantic search using sync method wrapped in executor
        from src.common.connection import run_redis_command
        return_fields = ["response", "vector_distance"]
        if return_metadata:
            return_fields.append("metadata")
        
        results = await run_redis_command(
            cache.check,
            prompt=query,
            num_results=num_results,
            return_fields=return_fields
        )
        
        if not results:
            return f"No matching entries found in cache '{cache_name}' for query: {query}"
        
        _logger.info(f"Found {len(results)} results in cache '{cache_name}' for query: {query[:50]}...")
        
        # Format results
        formatted_results = []
        for i, result in enumerate(results, 1):
            similarity_score = 1.0 - float(result.get('vector_distance', 0))
            
            entry = {
                "rank": i,
                "response": result.get('response', 'N/A'),
                "similarity_score": round(similarity_score, 4),
                "distance": round(float(result.get('vector_distance', 0)), 4)
            }
            
            if return_metadata:
                metadata_str = result.get('metadata')
                if metadata_str:
                    try:
                        if isinstance(metadata_str, str):
                            entry['metadata'] = json.loads(metadata_str)
                        else:
                            entry['metadata'] = metadata_str
                    except json.JSONDecodeError:
                        entry['metadata'] = {"raw": metadata_str}
            
            formatted_results.append(entry)
        
        # Return formatted string for better readability
        output = [
            f"Search Results from '{cache_name}' (Query: '{query[:100]}{'...' if len(query) > 100 else ''}')",
            f"Found {len(formatted_results)} matching entries:\n"
        ]
        
        for entry in formatted_results:
            output.append(f"\n{entry['rank']}. {entry['response']}")
            output.append(f"   Similarity: {entry['similarity_score']:.4f} (distance: {entry['distance']:.4f})")
            
            if 'metadata' in entry and entry['metadata']:
                output.append(f"   Metadata: {json.dumps(entry['metadata'], indent=6)}")
        
        return "\n".join(output)
        
    except RedisError as e:
        error_msg = f"Redis error searching cache '{cache_name}': {str(e)}"
        _logger.error(error_msg)
        return f"✗ {error_msg}"
    except Exception as e:
        error_msg = f"Error searching cache '{cache_name}': {str(e)}"
        _logger.error(error_msg)
        return f"✗ {error_msg}"


@mcp.tool()
async def semantic_cache_clear(cache_name: str, distance_threshold: float = 0.4) -> str:
    """Clear all entries from a semantic cache.
    
    Args:
        cache_name (str): Name of the cache to clear
        distance_threshold (float): Distance threshold of the cache to clear (default 0.4)
    
    Returns:
        str: Success confirmation or error message
    """
    try:
        cache = _get_or_create_cache(cache_name, distance_threshold, None)
        
        # Clear cache using sync method wrapped in executor
        from src.common.connection import run_redis_command
        await run_redis_command(cache.clear)
        
        _logger.info(f"Cleared cache: {cache_name}")
        return f"✓ Successfully cleared cache '{cache_name}'"
        
    except RedisError as e:
        error_msg = f"Redis error clearing cache '{cache_name}': {str(e)}"
        _logger.error(error_msg)
        return f"✗ {error_msg}"
    except Exception as e:
        error_msg = f"Error clearing cache '{cache_name}': {str(e)}"
        _logger.error(error_msg)
        return f"✗ {error_msg}"


@mcp.tool()
async def semantic_cache_info(cache_name: str, distance_threshold: float = 0.4) -> str:
    """Get information about a semantic cache including entry count and configuration.
    
    Args:
        cache_name (str): Name of the cache
        distance_threshold (float): Distance threshold of the cache (default 0.4)
    
    Returns:
        str: Cache statistics and configuration
    """
    try:
        cache = _get_or_create_cache(cache_name, distance_threshold, None)
        
        # Get index info using sync method wrapped in executor
        from src.common.connection import run_redis_command
        info = await run_redis_command(cache.index.info)
        
        output = [
            f"Semantic Cache Information: '{cache_name}'",
            f"\nConfiguration:",
            f"  Index Name: {info.get('index_name', 'N/A')}",
            f"  Distance Threshold: {distance_threshold}",
            f"  TTL: {cache.ttl if cache.ttl else 'No expiration'}",
            f"\nStatistics:",
            f"  Total Entries: {info.get('num_docs', 0)}",
            f"  Index Definition: {info.get('index_definition', 'N/A')}",
        ]
        
        return "\n".join(output)
        
    except RedisError as e:
        error_msg = f"Redis error getting cache info for '{cache_name}': {str(e)}"
        _logger.error(error_msg)
        return f"✗ {error_msg}"
    except Exception as e:
        error_msg = f"Error getting cache info for '{cache_name}': {str(e)}"
        _logger.error(error_msg)
        return f"✗ {error_msg}"
