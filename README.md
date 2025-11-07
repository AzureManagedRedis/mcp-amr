## Overview
Azure Managed Redis MCP Server provides a natural language interface for agentic apps to interact with Azure Managed Redis—a high-speed, in-memory datastore that is ideal for low-latency use cases like agent memory, vector data store and semantic caching.

This repo is a fork of [mcp-redis](https://github.com/redis/mcp-redis) with following updates:
- Support SSE so that this MCP server can be hosted remotely
- Support server side authentication through API Keys or OAuth
- Uses Entra Id Authentication by default to connect to Azure Managed Redis instance
- Removed the use of 'anyOf' keyword which cannot be parsed by some older MCP clients
- Allows bringing your own vectorizer for vector search use cases with the "knowledge store" tools
- Azd support to host MCP server remotely on Azure Container Apps

 Using this MCP Server, you can ask questions like:

- "Store the entire conversation in a stream"
- "Cache this item"
- "Store the session with an expiration time"
- "Store this json data as a vector"
- "Index and search this vector"

## Tools

This MCP Server provides tools to manage the data stored in Redis.

- `string` tools to set, get strings with expiration. Useful for storing simple configuration values, session data, or caching responses.
- `hash` tools to store field-value pairs within a single key. The hash can store vector embeddings. Useful for representing objects with multiple attributes, user profiles, or product information where fields can be accessed individually.
- `list` tools with common operations to append and pop items. Useful for queues, message brokers, or maintaining a list of most recent actions.
- `set` tools to add, remove and list set members. Useful for tracking unique values like user IDs or tags, and for performing set operations like intersection.
- `sorted set` tools to manage data for e.g. leaderboards, priority queues, or time-based analytics with score-based ordering.
- `pub/sub` functionality to publish messages to channels and subscribe to receive them. Useful for real-time notifications, chat applications, or distributing updates to multiple clients.
- `streams` tools to add, read, and delete from data streams. Useful for event sourcing, activity feeds, or sensor data logging with consumer groups support.
- `JSON` tools to store, retrieve, and manipulate JSON documents in Redis. Useful for complex nested data structures, document databases, or configuration management with path-based access.
- `knowledge store` tools to store and retrieve data using semantic similarity search with vector embeddings powered by Azure OpenAI. Useful for building RAG systems, semantic caching, question-answering systems, or any application that needs to find relevant information based on meaning rather than exact matches.

Additional tools.

- `query engine` tools to manage vector indexes and perform vector search
- `server management` tool to retrieve information about the database

## Installation

[Run the Redis MCP Server locally](https://github.com/redis/mcp-redis/blob/main/README.md)

### Host remote MCP Server on Azure

#### Deploy to Azure with Azure Developer CLI
The fastest way to deploy the MCP Server to Azure is using Azure Developer CLI (`azd`):

```bash
# Install azd (if not already installed)
curl -fsSL https://aka.ms/install-azd.sh | bash

# Login and deploy
azd auth login
azd up
```
This single command will:
- ✅ Prompt for environment name, subscription, and location
- ✅ Deploy Azure Managed Redis with RediSearch and RedisJSON
- ✅ Deploy Container Apps with the MCP server
- ✅ Build and push the container image
- ✅ Configure authentication (NO-AUTH, API-KEY, or OAUTH)

See detailed instructions [here](https://github.com/AzureManagedRedis/mcp-amr/blob/main/infra/README.md)

#### Deploy to Azure with Shell Script

Alternatively, you can use the interactive deployment script:

```bash
./infra/deploy-redis-mcp.sh
```

This script provides full control over the deployment configuration including resource group, location, Redis SKU, and authentication method.

For detailed deployment options, see [docs/AZURE_DEPLOYMENT.md](./docs/AZURE_DEPLOYMENT.md).

## Testing
Configure a client list VSCode GitHub Copilot to create MCP client for testing. Edit the `mcp.json` and add:

```json
{
  "servers": {
    "redis": {
      "type": "http",
      "url": "https://<your-Redis-MCP-server-url>/message",
      "headers": {
        "X-API-Key": "<your-api-key>"
      }
    }
  }
}
```
