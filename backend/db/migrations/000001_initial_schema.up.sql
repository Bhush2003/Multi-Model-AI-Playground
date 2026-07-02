-- Migration: 000001_initial_schema (up)
-- Creates the core tables required for the Multi-Model AI Playground MVP.

-- Enable the pgcrypto extension for gen_random_uuid() (required on PostgreSQL < 13
-- where it is not built in; on PG 13+ gen_random_uuid() is available natively).
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT        NOT NULL,
    email         TEXT        UNIQUE NOT NULL,
    password_hash TEXT        NOT NULL,
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- documents (referenced by prompts.rag_doc_id — created before prompts)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS documents (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    filename   TEXT        NOT NULL,
    file_size  INTEGER     NOT NULL,
    status     TEXT        DEFAULT 'processing'
                           CHECK (status IN ('processing', 'ready', 'error')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_documents_user_id ON documents(user_id);

-- ---------------------------------------------------------------------------
-- prompts
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS prompts (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    prompt     TEXT        NOT NULL,
    rag_doc_id UUID        REFERENCES documents(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prompts_user_id ON prompts(user_id);

-- ---------------------------------------------------------------------------
-- responses
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS responses (
    id          UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_id   UUID           NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
    model_name  TEXT           NOT NULL,
    response    TEXT,
    latency_ms  INTEGER,
    token_count INTEGER,
    cost        NUMERIC(10, 6),
    error       TEXT,
    created_at  TIMESTAMPTZ    DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_responses_prompt_id ON responses(prompt_id);

-- ---------------------------------------------------------------------------
-- ratings
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ratings (
    id          UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    response_id UUID      NOT NULL REFERENCES responses(id) ON DELETE CASCADE,
    accuracy    SMALLINT  CHECK (accuracy    BETWEEN 1 AND 5),
    clarity     SMALLINT  CHECK (clarity     BETWEEN 1 AND 5),
    helpfulness SMALLINT  CHECK (helpfulness BETWEEN 1 AND 5),
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (response_id)
);

-- ---------------------------------------------------------------------------
-- templates
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS templates (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL,  -- Coding | Interview Prep | Content Writing | Summarization
    title    TEXT NOT NULL,
    body     TEXT NOT NULL
);

-- ---------------------------------------------------------------------------
-- evaluations
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS evaluations (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_id     UUID        NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
    ranked_models JSONB       NOT NULL,   -- [{model, score, reasoning}]
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (prompt_id)
);
