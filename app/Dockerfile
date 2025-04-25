# Use an official Python runtime as a parent image
FROM python:3.11-slim

# Set the working directory
WORKDIR /app

# Copy requirements.txt first for better cache performance
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the current directory contents into the container
COPY . .

# Add a non-root user for security
RUN useradd -m appuser
USER appuser

# Make port 80 available 
EXPOSE 80

# Run FastAPI application when the container launches
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80"]
