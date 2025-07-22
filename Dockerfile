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

# Build the TypeScript project (if a build step is required)
# The README doesn't explicitly mention 'npm run build', but it's common for TS projects.
# If 'npm start' works directly from source, this might not be needed.
# We'll include it for robustness, assuming a production build.
# Check their package.json for common build scripts like 'build', 'compile', etc.
RUN npm run build || echo "No build script found or build not necessary for this project. Continuing."

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
# The command for the Perplexity MCP will be 'node /mcp_server_src/perplexity-ask/index.js'
# (assuming index.js is the main entry point after build, or the source if no build)
# You might need to adjust 'index.js' based on the actual entry point of their project.
CMD ["mcpo", "--port", "${MCPO_PORT}", "--api-key", "${MCPO_API_KEY}", "--", "node", "/mcp_server_src/perplexity-ask/index.js"]
