FROM python:3.12-slim
WORKDIR /app
COPY load_test.py .
RUN useradd --create-home --uid 10001 appuser
USER appuser
ENV PYTHONUNBUFFERED=1
CMD ["python", "load_test.py"]
