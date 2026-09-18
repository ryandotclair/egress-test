FROM python:3.9-slim
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN pip install requests
COPY k8s-webserver.py /app/server.py
WORKDIR /app
CMD ["python", "server.py"]
