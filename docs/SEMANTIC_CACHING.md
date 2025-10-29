# Semantic Caching Tools

The MCP Redis server now includes semantic caching capabilities powered by RedisVL, allowing you to store and retrieve data based on semantic similarity using vector search.

## Overview

Semantic caching uses vector embeddings to find similar queries, making it ideal for:
- LLM response caching (reduce API calls for similar questions)
- Content recommendation systems
- Duplicate detection
- Semantic search applications

## Available Tools

### 1. `semantic_cache_store`

Store data in the semantic cache with a prompt, response, and optional metadata.

**Parameters:**
- `cache_name` (string, required): Name of the cache to use
- `prompt` (string, required): The input prompt/query to cache
- `response` (string, required): The response to cache
- `metadata` (dict, optional): Additional metadata to store with the entry
- `distance_threshold` (float, optional): Maximum vector distance for cache hits (0.0-1.0, default: 0.4)
- `ttl` (integer, optional): Time-to-live in seconds for the cache entry

**Example:**
```json
{
  "cache_name": "llm_responses",
  "prompt": "What is the capital of France?",
  "response": "The capital of France is Paris.",
  "metadata": {
    "model": "gpt-4",
    "timestamp": "2024-01-15T10:30:00Z"
  },
  "distance_threshold": 0.4,
  "ttl": 3600
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Data stored in cache 'llm_responses'",
  "prompt": "What is the capital of France?",
  "cache_hit": false
}
```

### 2. `semantic_cache_search`

Search the semantic cache using vector similarity.

**Parameters:**
- `cache_name` (string, required): Name of the cache to search
- `query` (string, required): The query to search for
- `num_results` (integer, optional): Number of results to return (default: 5)
- `distance_threshold` (float, optional): Maximum vector distance for matches (0.0-1.0, default: 0.4)
- `return_metadata` (boolean, optional): Include metadata in results (default: true)

**Example:**
```json
{
  "cache_name": "llm_responses",
  "query": "What's the capital city of France?",
  "num_results": 3,
  "distance_threshold": 0.4,
  "return_metadata": true
}
```

**Response:**
```json
{
  "status": "success",
  "query": "What's the capital city of France?",
  "num_results": 1,
  "results": [
    {
      "prompt": "What is the capital of France?",
      "response": "The capital of France is Paris.",
      "distance": 0.15,
      "metadata": {
        "model": "gpt-4",
        "timestamp": "2024-01-15T10:30:00Z"
      }
    }
  ]
}
```

### 3. `semantic_cache_clear`

Clear all entries from a semantic cache.

**Parameters:**
- `cache_name` (string, required): Name of the cache to clear
- `distance_threshold` (float, optional): Distance threshold of the cache to clear (default: 0.4)

**Example:**
```json
{
  "cache_name": "llm_responses",
  "distance_threshold": 0.4
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Cache 'llm_responses' cleared successfully"
}
```

### 4. `semantic_cache_info`

Get information and statistics about a semantic cache.

**Parameters:**
- `cache_name` (string, required): Name of the cache to inspect
- `distance_threshold` (float, optional): Distance threshold of the cache (default: 0.4)

**Example:**
```json
{
  "cache_name": "llm_responses",
  "distance_threshold": 0.4
}
```

**Response:**
```json
{
  "status": "success",
  "cache_name": "llm_responses",
  "distance_threshold": 0.4,
  "num_docs": 42,
  "index_info": {
    "index_name": "llm_responses_index",
    "vector_dims": 1536,
    "distance_metric": "COSINE"
  }
}
```

## Common Use Cases

### LLM Response Caching

Reduce API costs by caching LLM responses for similar questions:

```python
# Store an LLM response
await semantic_cache_store(
    cache_name="gpt4_cache",
    prompt="Explain quantum computing",
    response="Quantum computing uses quantum mechanics...",
    metadata={"model": "gpt-4", "tokens": 150},
    ttl=86400  # 24 hours
)

# Later, search for similar questions
results = await semantic_cache_search(
    cache_name="gpt4_cache",
    query="What is quantum computing?",
    distance_threshold=0.3  # Lower = more strict matching
)
```

### Content Recommendation

Find similar content based on semantic similarity:

```python
# Store product descriptions
await semantic_cache_store(
    cache_name="products",
    prompt="Red leather hiking boots",
    response="Product ID: 12345",
    metadata={"category": "footwear", "price": 89.99}
)

# Find similar products
results = await semantic_cache_search(
    cache_name="products",
    query="Crimson leather boots for hiking",
    num_results=10
)
```

### Duplicate Detection

Identify duplicate or near-duplicate content:

```python
# Check for duplicates before storing
results = await semantic_cache_search(
    cache_name="articles",
    query="New article content here...",
    num_results=1,
    distance_threshold=0.2  # Very strict for duplicates
)

if results and results[0]["distance"] < 0.2:
    print("Possible duplicate found!")
```

## Configuration

### Distance Threshold

The `distance_threshold` parameter controls how similar two pieces of text need to be to match:

- **0.0 - 0.2**: Very strict (nearly identical text)
- **0.2 - 0.4**: Moderate (similar meaning, different wording)
- **0.4 - 0.6**: Loose (related topics)
- **0.6+**: Very loose (may return unrelated results)

**Default:** 0.4 (good balance for most use cases)

### TTL (Time To Live)

Set `ttl` in seconds to automatically expire cache entries:

- No TTL: Entries never expire
- `ttl=3600`: 1 hour
- `ttl=86400`: 24 hours
- `ttl=604800`: 7 days

## Prerequisites

### Required Dependencies

The semantic caching tools require:
- `redisvl>=0.3.0` - Already included in `pyproject.toml`
- Redis with RediSearch module enabled

### Redis Configuration

Ensure your Redis instance has the RediSearch module:

```bash
# Check if RediSearch is available
redis-cli MODULE LIST
```

For Azure Cache for Redis Enterprise:
- Enable the "Search and query" capability when provisioning
- Or use the deployment parameter: `ENABLE_REDIS_SEARCH=true`

## Error Handling

All tools include comprehensive error handling:

```json
{
  "status": "error",
  "message": "Failed to store data in cache 'llm_responses': Connection timeout"
}
```

Common errors:
- **Connection errors**: Check Redis connectivity
- **Module not loaded**: Ensure RediSearch module is enabled
- **Invalid distance_threshold**: Must be between 0.0 and 1.0
- **Empty prompt/query**: Prompt and query cannot be empty

## Performance Tips

1. **Choose appropriate distance_threshold**: Lower values are more strict but may miss valid matches
2. **Use TTL for temporary data**: Prevents cache from growing indefinitely
3. **Monitor cache size**: Use `semantic_cache_info` to track number of entries
4. **Batch operations**: Store multiple entries separately, then search once
5. **Use metadata for filtering**: Store additional context for better result filtering

## Example: Complete LLM Caching Flow

```python
import asyncio
from src.tools.semantic_cache import (
    semantic_cache_store,
    semantic_cache_search,
    semantic_cache_info,
    semantic_cache_clear
)

async def llm_with_cache(prompt: str, model: str = "gpt-4"):
    """LLM call with semantic caching."""
    
    # Check cache first
    results = await semantic_cache_search(
        cache_name=f"{model}_cache",
        query=prompt,
        num_results=1,
        distance_threshold=0.3
    )
    
    if results["num_results"] > 0:
        print(f"Cache hit! Distance: {results['results'][0]['distance']}")
        return results["results"][0]["response"]
    
    # Cache miss - call LLM
    print("Cache miss - calling LLM...")
    response = await call_llm(prompt, model)  # Your LLM call
    
    # Store in cache
    await semantic_cache_store(
        cache_name=f"{model}_cache",
        prompt=prompt,
        response=response,
        metadata={"model": model, "timestamp": datetime.now().isoformat()},
        distance_threshold=0.3,
        ttl=86400  # 24 hours
    )
    
    return response

# Usage
response = await llm_with_cache("What is machine learning?")
```

## Additional Resources

- [RedisVL Documentation](https://redisvl.com/)
- [RediSearch Documentation](https://redis.io/docs/stack/search/)
- [Vector Similarity Search](https://redis.io/docs/stack/search/reference/vectors/)
