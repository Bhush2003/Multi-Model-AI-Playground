# Implementation Plan

## Overview

Implementation of the Multi-Model AI Playground — a unified LLM comparison and evaluation platform. The backend is a Go/Gin API gateway; the frontend is a Flutter app using Riverpod. Tasks are ordered so that foundational scaffolding, auth, and core fan-out are built first, followed by history, analytics, templates, ratings, RAG, AI Judge, and deployment.

## Task Dependency Graph

```json
{
  "waves": [
    { "wave": 1, "tasks": ["1"] },
    { "wave": 2, "tasks": ["2", "10", "14", "20", "21"] },
    { "wave": 3, "tasks": ["3", "4"] },
    { "wave": 4, "tasks": ["5", "6", "8", "12"] },
    { "wave": 5, "tasks": ["7", "9", "11", "13", "15", "17", "19"] },
    { "wave": 6, "tasks": ["16", "18"] }
  ]
}
```

## Tasks

- [x] 1. Project Scaffolding
  - Initialize Go module with `go mod init`; add Gin, pgx, godotenv, golang-jwt dependencies
  - Create Flutter project; add Riverpod, Dio, flutter_markdown, shimmer packages
  - Set up PostgreSQL database and run initial migration for `users`, `prompts`, `responses` tables
  - Create `.env` config loader in Go at `config/config.go`
  - Create backend folder structure: `handlers/`, `services/`, `db/`, `middleware/`, `models/`
  - _Requirements: 1, 3, 14_

- [x] 2. User Authentication — Backend
  - Implement `POST /api/v1/auth/register`: bcrypt password hash (cost 12), insert user, return JWT (HS256, 24 h expiry)
  - Implement `POST /api/v1/auth/login`: verify bcrypt hash, return JWT
  - Write JWT middleware at `middleware/auth.go`: validate Bearer token on protected routes, return 401 on failure
  - Use parameterized SQL for all user insert and lookup queries
  - _Requirements: 1_
  - _Depends on: 1_

- [x] 3. User Authentication — Frontend
  - Create `AuthScreen` with Login and Register tabs
  - Implement `authProvider` StateNotifier: store JWT, expose login/register methods via Dio
  - Add Dio interceptor to attach `Authorization: Bearer <token>` to every request
  - Redirect to `HomeScreen` on successful auth; redirect to `AuthScreen` on 401
  - _Requirements: 1_
  - _Depends on: 2_

- [x] 4. Prompt Fan-Out — Backend
  - Implement `services/fanout.go`: launch one goroutine per selected model with 30-second context timeout, collect results via channel, return all results including per-model errors
  - Implement `services/openai.go`: call OpenAI Chat Completions API, return response text + token counts + latency
  - Implement `services/gemini.go`: call Gemini GenerateContent API, return response text + token counts + latency
  - Implement `services/claude.go`: call Anthropic Messages API, return response text + token counts + latency
  - Implement cost calculation using per-model pricing constants (gpt-4o, gemini-1.5-pro, claude-3-5-sonnet)
  - Implement `POST /api/v1/prompts` handler: validate input, persist prompt, call fan-out, persist all responses (including per-model errors), return results
  - Add input validation: reject empty prompt (400), reject prompt > 32,000 chars (400)
  - _Requirements: 2, 3, 5, 13_
  - _Depends on: 1_

- [x] 5. Side-by-Side Response Display — Frontend
  - Create `PlaygroundScreen` with `ModelSelectorWidget` (checkboxes for GPT, Gemini, Claude)
  - Create `PromptInputWidget` with submit button; show inline validation if no model is selected
  - Implement `promptSubmitProvider` FutureProvider: POST to `/api/v1/prompts`, expose loading/error/data states
  - Create `ResponseCard` widget: model name, response text (with markdown rendering), latency badge
  - Build `ResponsePanelList`: horizontal PageView on mobile, Row on tablet; shimmer loading state per panel
  - Show error message inside panel when a model returns an error; do not hide other panels
  - Highlight the panel with the lowest latency with a green "Fastest" badge
  - _Requirements: 2, 4, 5_
  - _Depends on: 4_

- [x] 6. Prompt History — Backend
  - Implement `GET /api/v1/prompts`: paginated list of prompts for the authenticated user, ordered by `created_at DESC`
  - Implement `GET /api/v1/prompts/:id`: return prompt + all associated responses
  - Implement `POST /api/v1/prompts/:id/resubmit`: re-dispatch stored prompt text to selected models
  - _Requirements: 6, 14_
  - _Depends on: 2, 4_

- [x] 7. Prompt History — Frontend
  - Create `HistoryScreen`: paginated list showing truncated prompt (120 chars) and timestamp
  - Create `HistoryDetailScreen`: full prompt + all stored responses for a selected entry
  - Add "Resubmit" button on `HistoryDetailScreen`: calls resubmit endpoint with currently selected models
  - Show empty-state message when history list is empty
  - Implement `historyProvider` FutureProvider with pagination support
  - _Requirements: 6_
  - _Depends on: 6_

- [x] 8. Cost Analytics — Backend
  - Add `ratings` table migration; add aggregation queries for total requests, tokens, and cost per model grouped by user and optional date range
  - Implement `GET /api/v1/analytics`: return aggregated stats with optional `start_date` / `end_date` query params
  - Ensure analytics queries return zeroes (not null/empty) when no data exists in the requested date range
  - _Requirements: 7_
  - _Depends on: 2, 4_

- [x] 9. Cost Analytics — Frontend
  - Create `AnalyticsScreen`: total requests counter, per-model token breakdown, per-model cost breakdown
  - Add date range picker filter; re-fetch analytics on range change
  - Display zero-state UI when no data exists for the selected range
  - Implement `analyticsProvider` FutureProvider
  - _Requirements: 7_
  - _Depends on: 8_

- [x] 10. Prompt Templates — Backend
  - Add `templates` table migration with seed data for Coding, Interview Preparation, Content Writing, Summarization categories (at least 2 templates per category)
  - Implement `GET /api/v1/templates`: return all templates grouped by category
  - _Requirements: 8_
  - _Depends on: 1_

- [x] 11. Prompt Templates — Frontend
  - Create `TemplatePicker` bottom sheet: grouped list by category
  - On template selection, populate `PromptInputWidget` text field with template body; do not auto-submit
  - Position cursor inside the template to allow immediate customisation
  - _Requirements: 8_
  - _Depends on: 10_

- [x] 12. Response Rating — Backend
  - Implement `POST /api/v1/responses/:id/rating`: upsert rating (accuracy, clarity, helpfulness); validate 1–5 range, return 400 on violation
  - Include rating data in `GET /api/v1/prompts/:id` response payload
  - _Requirements: 9_
  - _Depends on: 4_

- [x] 13. Response Rating — Frontend
  - Add rating controls to `ResponseCard`: three 1–5 star inputs for Accuracy, Clarity, Helpfulness
  - On rating submit, POST to rating endpoint; update UI to show stored values
  - Pre-populate rating controls when existing rating is loaded from history
  - _Requirements: 9_
  - _Depends on: 12_

- [x] 14. Document Upload and Processing — Backend
  - Add `documents` table migration
  - Implement `POST /api/v1/documents`: accept multipart upload; validate MIME type (PDF/DOCX) and size ≤ 20 MB; return 422 on violation
  - Implement Go text extraction: pdfcpu for PDF, gomods/docx for DOCX
  - Implement chunking in `services/chunker.go`: sliding window, 512 tokens max, 50-token overlap
  - Implement `services/embedding.go`: call OpenAI `text-embedding-3-small`, return `[]float32` per chunk
  - Implement `services/chromadb.go`: store chunk embeddings in ChromaDB collection named by document ID
  - Update document status to `ready` in PostgreSQL after successful embedding; update to `error` on failure
  - Implement `GET /api/v1/documents`: list user's documents with status
  - _Requirements: 10_
  - _Depends on: 1_

- [x] 15. RAG Mode Query — Backend
  - Implement `POST /api/v1/prompts/rag`: accept prompt + document ID + selected models
  - Embed the user prompt and query ChromaDB for top-5 chunks (cosine similarity)
  - If max similarity < 0.5, dispatch prompt without injected context; include flag in response indicating no context was found
  - Prepend retrieved chunk texts as context block to prompt; fan-out to selected models using the existing fan-out service
  - Persist RAG prompt + responses in `prompts` / `responses` tables with `rag_doc_id` populated
  - _Requirements: 11_
  - _Depends on: 14_

- [x] 16. RAG Mode — Frontend
  - Create `DocumentsScreen`: list uploaded documents with status badges (Processing / Ready / Error); file picker for upload
  - Implement document upload flow: multipart POST to `/api/v1/documents`; show progress indicator; refresh list on completion
  - On `PlaygroundScreen`, add "RAG Mode" toggle that shows a document selector when enabled
  - When RAG mode is active, display banner showing which document is providing context
  - If backend returns no-context flag, show notice "No relevant context found; responding without document"
  - Implement `ragDocumentProvider` StateProvider
  - _Requirements: 10, 11_
  - _Depends on: 15_

- [x] 17. AI Judge — Backend
  - Add `evaluations` table migration
  - Implement `services/judge.go`: build evaluation prompt with rubric (factual accuracy 40 pts, depth 35 pts, clarity 25 pts); call GPT-4o with JSON response mode
  - Parse GPT response into structured `[]ModelScore{Model, Score, Reasoning}` + winner field
  - Implement `POST /api/v1/prompts/:id/judge`: invoke judge service, persist to `evaluations`, return structured result; return 502 on judge call failure
  - Implement `GET /api/v1/prompts/:id/judge`: return saved evaluation for use in history
  - _Requirements: 12_
  - _Depends on: 4, 6_

- [x] 18. AI Judge — Frontend
  - Show "Evaluate with AI Judge" button on `PlaygroundScreen` after all model responses are loaded
  - Implement `judgeProvider` FutureProvider: POST to judge endpoint; expose loading/error/data states
  - Create `JudgePanel` widget: ranked list of models with score bar, winner badge, and per-model reasoning text
  - In `HistoryDetailScreen`, load and display saved evaluation if it exists
  - _Requirements: 12_
  - _Depends on: 17_

- [x] 19. Error Handling and Resilience
  - Add global error handler in Gin: return consistent `{"error": "message"}` JSON for all unhandled panics
  - Add Flutter global error boundary: show user-friendly snackbar for network/server errors
  - Verify that a single model timeout does not block or fail other model responses (integration test)
  - _Requirements: 13_
  - _Depends on: 1, 2, 4_

- [x] 20. Database Migrations
  - Use golang-migrate or goose to manage all schema migrations as versioned SQL files
  - Ensure all foreign key constraints and indexes defined in the design are applied
  - Add seed migration for prompt templates
  - _Requirements: 14_
  - _Depends on: 1_

- [x] 21. Deployment Readiness
  - Write `Dockerfile` for Go backend
  - Write `docker-compose.yml` covering backend, PostgreSQL, and ChromaDB services
  - Add `README.md` with local setup instructions, environment variable list, and API overview
  - Add `.env.example` with all required keys and no real values
  - _Depends on: 1_

## Notes

- All AI provider API keys must be stored as environment variables and must never be committed to source control.
- SQL queries must use parameterized statements throughout — no string interpolation.
- JWT tokens use HS256 with a 24-hour expiry; the secret must be a random 256-bit value set via `JWT_SECRET`.
- The fan-out service enforces a 30-second per-model timeout using `context.WithTimeout`; timeouts are recorded as per-model errors, not global failures.
- ChromaDB collections are keyed by document ID; embeddings use OpenAI `text-embedding-3-small` (1536 dimensions).
- Flutter layout: horizontal `PageView` on mobile, side-by-side `Row` on tablet/web for response panels.
