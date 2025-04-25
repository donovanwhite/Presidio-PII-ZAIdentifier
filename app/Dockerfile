# Use an official Python runtime as a parent image
FROM python:3.11-slim

# Set the working directory
WORKDIR /app

# Copy requirements.txt first for better cache performance
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install the spaCy language model
RUN python -m spacy download en_core_web_lg

# Install curl for health check
RUN apt-get update && apt-get install -y curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy the current directory contents into the container
COPY . .

# Add a non-root user for security
RUN useradd -m appuser

# Set proper permissions for the appuser
RUN chown -R appuser:appuser /app

# Add HEALTHCHECK instruction to verify container health
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -f http://localhost:80/health || exit 1

# Switch to non-root user for security
USER appuser

# Make port 80 available 
EXPOSE 80

# Run FastAPI application when the container launches
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80"]
