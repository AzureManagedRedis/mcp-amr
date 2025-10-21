FROM python:3.14-slim

# Install uv
RUN pip install --upgrade uv

# Create non-root user for security with home directory
RUN groupadd -r appuser && useradd -r -g appuser -m -d /home/appuser appuser

WORKDIR /app

# Copy dependency files first for better Docker layer caching
COPY pyproject.toml uv.lock README.md ./
COPY src ./src

# Install dependencies (no dev dependencies)
RUN uv sync --locked --no-dev --no-editable

# Copy the rest of the application files
COPY . /app

# Change ownership to non-root user
RUN chown -R appuser:appuser /app

# Create cache directory for uv with proper permissions
RUN mkdir -p /app/.cache/uv && chown -R appuser:appuser /app/.cache

# Switch to non-root user
USER appuser

# Set environment variables to prevent any cache directory creation
ENV HOME=/app
ENV UV_CACHE_DIR=/app/.cache/uv
ENV XDG_CACHE_HOME=/app/.cache
ENV PYTHONUNBUFFERED=1

# Expose port (Azure Container Apps will map this)
EXPOSE 8000

# Health check for Azure Container Apps
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import sys; sys.exit(0)"

# Default command - run HTTP server for remote MCP access
# This runs the MCP server with HTTP/SSE transport instead of stdio
ENV PYTHONPATH=/app
CMD ["/app/.venv/bin/python", "-m", "src.http_server"]