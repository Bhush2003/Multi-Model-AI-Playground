# Design Document

## Multi-Model AI Playground — Unified LLM Comparison and Evaluation Platform

---

## Overview

The platform consists of two main components:

1. **Flutter frontend** — a cross-platform mobile/web app using Riverpod for state management and Dio for HTTP
2. **Go API Gateway** — a Gin-based REST service that fans out prompts to AI providers, manages persistence, and hosts the RAG and AI Judge pipelines

PostgreSQL is the primary database. ChromaDB is the vector store for RAG. All AI provider calls are made server-side; API keys never leave the backend.

---

## Architecture

```
Flutter App (Riverpod + Dio)
        │
        │  HTTPS REST
        ▼
Go API Gateway (Gin)
   ├── Auth middleware (JWT)
   ├── /prompt   → fan-out goroutines → OpenAI │ Gemini │ Claude
   ├── /history  → PostgreSQL
   ├── /analytics→ PostgreSQL aggregates
   ├── /rag      → ChromaDB + embedding model → AI providers
   ├── /judge    → GPT evaluation pipeline
   └── /docs     → document chunking + embedding ingest
        │
   ┌────┴──────────────────┐
   │                       │
PostgreSQL              ChromaDB
(users, prompts,        (embeddings,
 responses, ratings,     chunks per doc)
 evaluations,
 templates)
```

---

## Backend Design (Go / Gin)

### Module Structure

```
backend/
├── main.go
├── config/           # env-based config loader
├── db/
│   ├── postgres.go   # connection pool, migrations
│   └── queries/      # raw SQL or sqlc generated
├── middleware/
│   └── auth.go       # JWT validation
├── handlers/
│   ├── auth.go
│   ├── prompt.go
│   ├── history.go
│   ├── analytics.go
│   ├── template.go
│   ├── rating.go
│   ├── rag.go
│   └── judge.go
├── services/
│   ├── fanout.go     # concurrent model dispatch
│   ├── openai.go
│   ├── gemini.go
│   ├── claude.go
│   ├── embedding.go  # OpenAI text-embedding-3-small
│   ├── chromadb.go
│   └── judge.go
└── models/           # Go structs mirroring DB tables
```

### REST API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/auth/register` | Create user, return JWT |
| POST | `/api/v1/auth/login` | Authenticate, return JWT |
| POST | `/api/v1/prompts` | Submit prompt, fan-out to models |
| GET | `/api/v1/prompts` | List prompt history (paginated) |
| GET | `/api/v1/prompts/:id` | Get single prompt + responses |
| POST | `/api/v1/prompts/:id/resubmit` | Resubmit historical prompt |
| GET | `/api/v1/analytics` | Aggregated cost/token stats |
| GET | `/api/v1/templates` | List prompt templates |
| POST | `/api/v1/responses/:id/rating` | Submit or update rating |
| POST | `/api/v1/documents` | Upload document for RAG |
| GET | `/api/v1/documents` | List user's documents |
| POST | `/api/v1/prompts/rag` | Submit RAG-mode prompt |
| POST | `/api/v1/prompts/:id/judge` | Trigger AI Judge evaluation |
| GET | `/api/v1/prompts/:id/judge` | Retrieve saved evaluation |

### Fan-Out Service (`services/fanout.go`)

```go
type ModelResult struct {
    ModelName  string
    Response   string
    LatencyMs  int64
    TokenCount int
    Cost       float64
    Err        error
}

func FanOut(ctx context.Context, prompt string, models []string) []ModelResult {
    // Launch one goroutine per selected model
    // Each goroutine has a 30-second timeout (context.WithTimeout)
    // Results collected via channel
    // Return all results including per-model errors
}
```

### JWT Auth Middleware

- Tokens signed with HS256, 24-hour expiry
- Claims: `user_id`, `email`, `exp`
- Middleware extracts and validates on every protected route

### Cost Calculation

Per-model pricing constants stored in config:

| Model | Input (per 1K tokens) | Output (per 1K tokens) |
|-------|-----------------------|------------------------|
| gpt-4o | $0.005 | $0.015 |
| gemini-1.5-pro | $0.00125 | $0.005 |
| claude-3-5-sonnet | $0.003 | $0.015 |

`Cost = (input_tokens / 1000 * input_price) + (output_tokens / 1000 * output_price)`

---

## Database Design (PostgreSQL)

### Schema

```sql
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    email       TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE prompts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    prompt      TEXT NOT NULL,
    rag_doc_id  UUID REFERENCES documents(id),
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE responses (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_id   UUID NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
    model_name  TEXT NOT NULL,
    response    TEXT,
    latency_ms  INTEGER,
    token_count INTEGER,
    cost        NUMERIC(10, 6),
    error       TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE ratings (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    response_id UUID NOT NULL REFERENCES responses(id) ON DELETE CASCADE,
    accuracy    SMALLINT CHECK (accuracy BETWEEN 1 AND 5),
    clarity     SMALLINT CHECK (clarity BETWEEN 1 AND 5),
    helpfulness SMALLINT CHECK (helpfulness BETWEEN 1 AND 5),
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (response_id)
);

CREATE TABLE templates (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category    TEXT NOT NULL,  -- Coding, Interview Prep, Content Writing, Summarization
    title       TEXT NOT NULL,
    body        TEXT NOT NULL
);

CREATE TABLE documents (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    filename    TEXT NOT NULL,
    file_size   INTEGER NOT NULL,
    status      TEXT DEFAULT 'processing', -- processing | ready | error
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE evaluations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_id   UUID NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
    ranked_models JSONB NOT NULL,   -- [{model, score, reasoning}]
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (prompt_id)
);

-- Indexes
CREATE INDEX idx_prompts_user_id ON prompts(user_id);
CREATE INDEX idx_responses_prompt_id ON responses(prompt_id);
CREATE INDEX idx_documents_user_id ON documents(user_id);
```

---

## RAG Pipeline Design

```
User uploads PDF/DOCX
        │
        ▼
Extract raw text (pdfcpu / docx parser in Go)
        │
        ▼
Chunk: 512 tokens, 50-token overlap (sliding window)
        │
        ▼
Embed each chunk: OpenAI text-embedding-3-small (1536-dim)
        │
        ▼
Store in ChromaDB collection keyed by document_id
        │
        ▼
Document status → "ready" in PostgreSQL
```

**At query time (RAG mode prompt):**

```
User prompt
    │
    ▼
Embed prompt → query ChromaDB (top-5, cosine similarity)
    │
    ▼
If max similarity < 0.5 → dispatch prompt without context
    │
    ▼
Prepend retrieved chunks as context → fan-out to selected models
```

---

## AI Judge Pipeline Design

```
All model responses collected
        │
        ▼
Build evaluation payload:
  - system: "You are an expert evaluator..."
  - user: structured JSON with prompt + all responses
        │
        ▼
Call GPT-4o with JSON mode response format
        │
        ▼
Parse: [{model, score (1–100), reasoning}] + winner
        │
        ▼
Persist to evaluations table
        │
        ▼
Return structured result to Flutter
```

Evaluation rubric injected in system prompt:
- **Factual accuracy** (40 pts): correctness of claims
- **Depth of explanation** (35 pts): completeness, examples
- **Clarity** (25 pts): structure, readability

---

## Frontend Design (Flutter / Riverpod)

### Screen Map

```
SplashScreen
    │
    ├── AuthScreen (Login / Register)
    │
    └── HomeScreen (bottom nav)
         ├── PlaygroundScreen        ← main feature
         │    ├── ModelSelectorWidget
         │    ├── PromptInputWidget
         │    ├── TemplatePicker
         │    ├── ResponsePanelList
         │    │    └── ResponseCard (label, text, latency, rating)
         │    └── JudgePanel
         ├── HistoryScreen
         │    └── HistoryDetailScreen
         ├── AnalyticsScreen
         └── DocumentsScreen         ← RAG uploads
```

### State Management (Riverpod)

| Provider | Type | Purpose |
|----------|------|---------|
| `authProvider` | `StateNotifierProvider` | JWT token, user info |
| `selectedModelsProvider` | `StateProvider<Set<String>>` | Which models are checked |
| `promptProvider` | `StateProvider<String>` | Current prompt text |
| `promptSubmitProvider` | `FutureProvider` | Fan-out request state |
| `historyProvider` | `FutureProvider<List<Prompt>>` | Paginated history |
| `analyticsProvider` | `FutureProvider<Analytics>` | Dashboard data |
| `ragDocumentProvider` | `StateProvider<Document?>` | Active RAG document |
| `judgeProvider` | `FutureProvider<Evaluation>` | AI Judge result |

### Response Panel Layout

- Horizontal `PageView` on mobile (swipe between models)
- Side-by-side `Row` on tablet/web
- Fastest response panel gets a green "Fastest" badge
- Loading state: shimmer animation
- Error state: red border + error message

### Dio HTTP Client Setup

```dart
final dio = Dio(BaseOptions(
  baseUrl: 'https://api.yourbackend.com/api/v1',
  connectTimeout: Duration(seconds: 10),
  receiveTimeout: Duration(seconds: 60), // long for LLM responses
  headers: {'Content-Type': 'application/json'},
));

// JWT interceptor — attaches Bearer token to every request
// Refresh/redirect on 401
```

---

## Security Considerations

- Passwords hashed with bcrypt (cost factor 12)
- JWT tokens expire in 24 hours
- All AI provider API keys stored as environment variables, never in source
- File uploads validated for MIME type and size before processing
- SQL queries use parameterized statements (no string interpolation)
- CORS restricted to known Flutter web origin in production

---

## Environment Configuration

```env
# Database
DATABASE_URL=postgres://user:pass@localhost:5432/ai_playground

# JWT
JWT_SECRET=<random 256-bit secret>

# AI Providers
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...
ANTHROPIC_API_KEY=sk-ant-...

# ChromaDB
CHROMA_URL=http://localhost:8000

# Server
PORT=8080
ENV=development
```
