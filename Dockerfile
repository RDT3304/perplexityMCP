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
    && rm -rf /var/lib/apt/lists/*

# --- Install Go 1.22 ---
# Define Go version
ENV GOLANG_VERSION=1.22.4
ENV GOROOT=/usr/local/go
ENV PATH="${GOROOT}/bin:$PATH"

RUN curl -OL https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go${GOLANG_VERSION}.linux-amd64.tar.gz \
    && rm go${GOLANG_VERSION}.linux-amd64.tar.gz

# --- MCPO Python Virtual Environment Setup ---
WORKDIR /app
ENV VIRTUAL_ENV=/app/.venv
RUN uv venv "$VIRTUAL_ENV"
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN uv pip install mcpo && rm -rf ~/.cache

# --- Model Context Protocol Source Code & Build Steps (Go) ---
# Clone the repository to a temporary folder
WORKDIR /
RUN git clone https://github.com/ppl-ai/modelcontextprotocol.git /tmp/mcp_repo \
    # Move contents from the cloned repo into /mcp_server_src
    && mkdir -p /mcp_server_src \
    && mv /tmp/mcp_repo/* /tmp/mcp_repo/.* /mcp_server_src/ || true \
    && rm -rf /tmp/mcp_repo

# Change to the repository root where go.mod is located
WORKDIR /mcp_server_src

# IMPORTANT DEBUG STEP: List contents to verify `go.mod` is here
# Uncomment the next line if it fails again
RUN ls -F /mcp_server_src/
# Expected output from above: You should see go.mod listed here

# Clean Go modules and download dependencies
RUN go mod tidy

# Build the Go application, specifying the main package path
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
ENV MCPO_PORT=8003

# Command to run mcpo, passing the Model Context Protocol stdio command.
# This launches the compiled Go binary and proxies its standard I/O to mcpo.
CMD mcpo --port ${MCPO_PORT} --api-key ${MCPO_API_KEY} -- /mcp_server_src/mcp-server
