FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim

WORKDIR /app

COPY pyproject.toml .
RUN uv sync --no-dev

COPY main.py .

RUN useradd -u 1000 -m -s /usr/sbin/nologin app && chown -R 1000:1000 /app
USER 1000:1000

CMD ["uv", "run", "main.py"]
