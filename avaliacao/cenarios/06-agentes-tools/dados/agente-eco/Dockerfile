# Agente A2A mínimo ("eco de governança") — só stdlib, sem dependências.
# Ver server.py para a nota sobre a decisão de não usar a2a-sdk (Python).
FROM python:3.12-slim
WORKDIR /app
COPY server.py .
ENV PORT=9000
EXPOSE 9000
CMD ["python", "server.py"]
