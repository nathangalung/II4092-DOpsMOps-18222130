---
name: Python Engineering & ML Patterns
description: Use when writing or reviewing Python — uv, ruff, pyright, FastAPI, ML pipeline structure, testing
globs: ["**/*.py", "**/pyproject.toml", "**/uv.lock", "**/*.ipynb", "**/requirements*.txt"]
---

# Python Engineering & ML Patterns

## Performance Setup
- Package manager: `uv` (10-100x faster than pip/poetry/pipenv)
- Formatter: `ruff format` (30x faster than black)
- Linter: `ruff check --fix` (10-100x faster than flake8/pylint)
- Type checker: `pyright` (3-5x faster than mypy, stricter)
- Test runner: `uv run pytest -x --tb=short` (auto-venv, fail-fast)
- ASGI server: `uvicorn` with uvloop (fastest Python HTTP)
- JSON: `orjson` or `msgspec` (5-30x faster than stdlib json)

## Zen of Python (PEP 20) — Applied

1. "Beautiful is better than ugly." → clean formatting (ruff format enforces)
2. "Explicit is better than implicit." → type hints on ALL functions, no magic
3. "Simple is better than complex." → don't over-engineer, start with functions
4. "Flat is better than nested." → max 3 levels of nesting, extract functions
5. "Errors should never pass silently." → handle exceptions, log, or re-raise with context
6. "In the face of ambiguity, refuse the temptation to guess." → strict types, validate inputs
7. "There should be one obvious way to do it." → follow established patterns per framework
8. "If the implementation is hard to explain, it's a bad idea." → refactor until clear
9. "Namespaces are one honking great idea." → use modules and packages for organization

## Package Management (uv)
```bash
uv init myproject            # New project
uv add fastapi uvicorn       # Add deps
uv add --dev pytest ruff     # Dev deps
uv sync --frozen             # CI/Docker (reproducible)
uv run pytest                # Run in managed venv
uv run python script.py      # Run script in venv
uvx ruff check .             # One-off tool execution
```

## Type Hints (MANDATORY)
```python
from typing import Optional, Sequence
from collections.abc import AsyncIterator

def process_items(
    items: Sequence[str],
    limit: int = 10,
    prefix: str | None = None,    # Python 3.10+ union syntax
) -> list[str]:
    ...

async def stream_data() -> AsyncIterator[bytes]:
    ...
```

## FastAPI Patterns
```python
from fastapi import FastAPI, Depends, HTTPException, status
from pydantic import BaseModel, Field

class CreateUserRequest(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    email: str = Field(pattern=r'^[\w.-]+@[\w.-]+\.\w+$')

class UserResponse(BaseModel):
    id: str
    name: str
    email: str

@app.post("/users", response_model=UserResponse, status_code=201)
async def create_user(
    body: CreateUserRequest,
    db: AsyncSession = Depends(get_db),
) -> UserResponse:
    ...
```
- Pydantic v2 for validation (50x faster than v1)
- Dependency injection for DB sessions, auth, config
- Background tasks: `BackgroundTasks` for non-blocking work
- Lifespan events for startup/shutdown (connection pools)

## ML Pipeline Patterns

### Instructor (LLM Structured Output)
```python
import instructor
from pydantic import BaseModel

client = instructor.from_openai(openai.OpenAI())

class ExtractedSkills(BaseModel):
    skills: list[str]
    experience_years: int

result = client.chat.completions.create(
    model="gpt-4o-mini",
    response_model=ExtractedSkills,
    messages=[{"role": "user", "content": cv_text}],
)
```

### Scikit-learn / CatBoost Pattern
```python
from catboost import CatBoostClassifier

model = CatBoostClassifier(
    cat_features=['skill_category', 'domain', 'tier'],  # native categorical
    iterations=1000,
    learning_rate=0.05,
    eval_metric='AUC',
)
model.fit(X_train, y_train, eval_set=(X_val, y_val), early_stopping_rounds=50)
```

## Testing Patterns
```python
import pytest
from httpx import AsyncClient

@pytest.fixture
async def client(app):
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac

@pytest.mark.asyncio
async def test_create_user(client: AsyncClient):
    response = await client.post("/users", json={"name": "Test", "email": "t@t.com"})
    assert response.status_code == 201
    assert response.json()["name"] == "Test"

@pytest.mark.parametrize("input,expected", [
    ("React", ["React"]),
    ("React.js", ["React"]),  # normalized
    ("", []),
])
def test_skill_extraction(input: str, expected: list[str]):
    assert extract_skills(input) == expected
```

## Project Structure
```
src/
  app/
    main.py           # FastAPI app, lifespan
    routes/            # API route modules
    services/          # Business logic
    repositories/      # Data access
    models/            # Pydantic models (request/response)
    dependencies.py    # FastAPI dependencies
  ml/
    training/          # Model training scripts
    serving/           # Model inference endpoints
    evaluation/        # Evaluation scripts
  core/
    config.py          # Settings via pydantic-settings
    logging.py         # Structured logging (structlog)
tests/
pyproject.toml
```
