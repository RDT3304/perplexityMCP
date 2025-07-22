# Stage 1: Build the Perplexity MCP application
FROM node:20-slim AS builder

# Install git and ca-certificates in the builder stage
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Clone the repository
RUN git clone https://github.com/ppl-ai/modelcontextprotocol.git .

# Navigate to the specific directory as per their README for dependency installation and build
WORKDIR /app/perplexity-ask

# Install node modules
RUN npm install

# Build the TypeScript project
# Based on package.json, 'npm run build' (which runs 'tsc') will output to 'dist/'.
RUN npm run build

# Stage 2: Create the final, lean production image
FROM python:3.12-slim-bookworm

# Set environment variables for non-interactive installations
ENV DEBIAN_FRONTEND=noninteractive

# Install uv (from official binary)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Install base dependencies (curl, ca-certificates) - ca-certificates is still good to have here for general use
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# --- MCPO Python Virtual Environment Setup ---
WORKDIR /app

ENV VIRTUAL_ENV=/app/.venv
RUN uv venv "$VIRTUAL_ENV"
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN uv pip install mcpo && rm -rf ~/.cache

# Copy the built Perplexity MCP application from the builder stage
# This copies the entire 'perplexity-ask' directory from the builder stage
COPY --from=builder /app/perplexity-ask /mcp_server_src/perplexity-ask

# Since mcpo will execute the Node.js application, Node.js runtime is needed in the final image
# We can't use the 'node' base image directly for the final stage because we need python:3.12-slim-bookworm
# So, we need to install Node.js separately in this stage.
# This will add some size, but is necessary.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Expose the port mcpo will listen on
EXPOSE 8003

# Set default API keys and port for mcpo.
# IMPORTANT: These should be overridden with strong, unique keys
# in your deployment environment (e.g., Coolify, Kubernetes secrets, .env file).
ENV MCPO_API_KEY="your-secret-mcpo-api-key"
# Port for MCPO to listen on
ENV MCPO_PORT=8003

# This is for the Perplexity MCP itself
ENV PERPLEXITY_API_KEY="YOUR_PERPLEXITY_API_KEY_HERE"

# Command to run mcpo, passing the Perplexity MCP stdio command.
# CORRECTED PATH: node /mcp_server_src/perplexity-ask/dist/index.js
CMD ["sh", "-c", "mcpo --port \"${MCPO_PORT}\" --api-key \"${MCPO_API_KEY}\" -- node /mcp_server_src/perplexity-ask/dist/index.js"]
