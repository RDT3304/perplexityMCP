# Start with the specified Python base image for mcpo
FROM python:3.12-slim-bookworm

# Set environment variables for non-interactive installations
ENV DEBIAN_FRONTEND=noninteractive

# Install uv (from official binary)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Install base dependencies (git, curl, ca-certificates)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    # Install Go compiler
    golang \
    && rm -rf /var/lib/apt/lists/*

# --- MCPO Python Virtual Environment Setup ---
WORKDIR /app
ENV VIRTUAL_ENV=/app/.venv
RUN uv venv "$VIRTUAL_ENV"
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN uv pip install mcpo && rm -rf ~/.cache

# --- Model Context Protocol Source Code & Build Steps (Go) ---
# Clone the repository
WORKDIR /
RUN git clone https://github.com/ppl-ai/modelcontextprotocol.git /mcp_server_src

# Change to its directory
WORKDIR /mcp_server_src

# Clean Go modules and download dependencies
RUN go mod tidy

# Build the Go application
# The output binary 'mcp-server' will be placed in the current working directory (/mcp_server_src)
RUN go build -o mcp-server ./cmd/mcp-server

# --- Final Configuration ---
# Set the primary working directory back to /app for mcpo execution
WORKDIR /app

# Expose the port mcpo will listen on
EXPOSE 8003

# Set default API keys and port for mcpo.
# IMPORTANT: These should be overridden with strong, unique keys
# in your deployment environment (e.g., Coolify, Kubernetes secrets, .env file).
ENV MCPO_API_KEY="your-secret-mcpo-api-key"
# Port for MCPO to listen on
ENV MCPO_PORT=8002

# Command to run mcpo, passing the Model Context Protocol stdio command.
# This launches the compiled Go binary and proxies its standard I/O to mcpo.
CMD mcpo --port ${MCPO_PORT} --api-key ${MCPO_API_KEY} -- /mcp_server_src/mcp-server
