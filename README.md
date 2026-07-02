# Multi-Model AI Playground

## Overview

A unified LLM comparison platform. Submit a single prompt to GPT-4o, Gemini 1.5 Pro, and Claude 3.5 Sonnet simultaneously and compare responses side-by-side. Features include prompt history, cost analytics, prompt templates, response ratings, RAG mode (document Q&A), and an AI Judge evaluator.

## Tech Stack

- **Backend**: Go 1.25 / Gin — REST API gateway
- **Frontend**: Flutter 3.x — cross-platform app (mobile + web)
- **Database**: PostgreSQL 16
- **Vector store**: ChromaDB (for RAG embeddings)

## Prerequisites

- Go 1.25+
- Flutter 3.x
- Docker + Docker Compose (for containerized setup)
- PostgreSQL 16 (for local dev without Docker)

## Quick Start (Docker)

```bash
# 1. Clone the repo
git clone <repo-url>
cd ai-playground

# 2. Copy env file and fill in your API keys
cp .env.example .env
# Edit .env: set JWT_SECRET, OPENAI_API_KEY, GEMINI_API_KEY, ANTHROPIC_API_KEY

# 3. Start all services
docker compose up --build

# Backend API: http://localhost:8080
# ChromaDB:    http://localhost:8000
```

## Local Development (without Docker)

### Backend

```bash
cd backend
cp .env.example .env
# Edit .env with real values (DATABASE_URL pointing to local Postgres)

# Database migrations run automatically when the server starts
go run .
```

### Frontend

```bash
cd frontend
flutter pub get
# Update lib/config/api_config.dart if backend runs on a different port
flutter run
```

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | ✅ | PostgreSQL connection string, e.g. `postgres://user:pass@localhost:5432/ai_playground` |
| `JWT_SECRET` | ✅ | Random 256-bit secret for signing JWTs. Generate with `openssl rand -hex 32` |
| `OPENAI_API_KEY` | ✅ | OpenAI API key (used for GPT-4o responses and text-embedding-3-small) |
| `GEMINI_API_KEY` | ✅ | Google Gemini API key |
| `ANTHROPIC_API_KEY` | ✅ | Anthropic Claude API key |
| `CHROMA_URL` | ✅ | ChromaDB base URL, default `http://localhost:8000` |
| `PORT` | optional | Backend HTTP port, default `8080` |
| `ENV` | optional | `development` or `production`. Production sets Gin to release mode. |

## API Overview

All protected endpoints require `Authorization: Bearer <token>` header.

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/api/v1/auth/register` | — | Create account, returns JWT |
| POST | `/api/v1/auth/login` | — | Login, returns JWT |
| POST | `/api/v1/prompts` | ✅ | Submit prompt to selected models |
| GET | `/api/v1/prompts` | ✅ | List prompt history (paginated) |
| GET | `/api/v1/prompts/:id` | ✅ | Get single prompt + responses + ratings |
| POST | `/api/v1/prompts/:id/resubmit` | ✅ | Resubmit prompt to new models |
| POST | `/api/v1/prompts/rag` | ✅ | Submit RAG-mode prompt with document context |
| POST | `/api/v1/prompts/:id/judge` | ✅ | Trigger AI Judge evaluation |
| GET | `/api/v1/prompts/:id/judge` | ✅ | Retrieve saved evaluation |
| GET | `/api/v1/analytics` | ✅ | Aggregated token/cost stats |
| GET | `/api/v1/templates` | ✅ | List prompt templates by category |
| POST | `/api/v1/responses/:id/rating` | ✅ | Submit or update response rating |
| POST | `/api/v1/documents` | ✅ | Upload PDF/DOCX for RAG |
| GET | `/api/v1/documents` | ✅ | List user's uploaded documents |

## Database Migrations

Migrations are applied automatically on server startup using golang-migrate. SQL files live in `backend/db/migrations/`. To run migrations manually:

```bash
cd backend
go run . # starts server and applies pending migrations
```

## Security Notes

- Never commit `.env` files — they are git-ignored
- `JWT_SECRET` should be a random 256-bit value: `openssl rand -hex 32`
- All AI provider API keys are server-side only; they never reach the Flutter client
- SQL queries use parameterized statements throughout
