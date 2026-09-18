FROM python:3.9-slim
RUN pip install requests
COPY k8s-webserver.py /app/server.py
WORKDIR /app
CMD ["python", "server.py"]
