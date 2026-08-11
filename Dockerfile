FROM python:3.12-slim

RUN pip install --no-cache-dir swiss-academic-libraries-mcp

EXPOSE 8005

# No --http-path flag exists; endpoint is always /mcp at server root.
CMD ["swiss-academic-libraries-mcp", "--http", "--host", "0.0.0.0", "--port", "8005"]
