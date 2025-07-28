FROM node:18-alpine

# ARG CLEAR_KEY
WORKDIR /app

# Install the latest version globally
# RUN yes n | npx -y @smithery/cli@latest install @waldzellai/clear-thought --client claude --profile crooked-toucan-bdJ0n5 --key $CLEAR_KEY
RUN npm install -g @waldzellai/clear-thought

# Expose default port if needed (optional, depends on MCP client interaction)
# EXPOSE 3000

# Default command to run the server
# RUN npx -y @smithery/cli@latest install @waldzellai/clear-thought --client claude --profile crooked-toucan-bdJ0n5 --key $CLEAR_KEY
# RUN ["npx", "-y","@smithery/cli", "run", "@waldzellai/clear-thought", "--key","879baa0c-4663-45f8-b4c5-67452793779b","--profile","crooked-toucan-bdJ0n5"]
CMD ["mcp-server-clear-thought"]
