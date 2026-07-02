package models

import (
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

// User mirrors the `users` table.
type User struct {
	ID           pgtype.UUID `db:"id"            json:"id"`
	Name         string      `db:"name"          json:"name"`
	Email        string      `db:"email"         json:"email"`
	PasswordHash string      `db:"password_hash" json:"-"`
	CreatedAt    time.Time   `db:"created_at"    json:"created_at"`
}

// Prompt mirrors the `prompts` table.
type Prompt struct {
	ID        pgtype.UUID  `db:"id"         json:"id"`
	UserID    pgtype.UUID  `db:"user_id"    json:"user_id"`
	Prompt    string       `db:"prompt"     json:"prompt"`
	RagDocID  *pgtype.UUID `db:"rag_doc_id" json:"rag_doc_id,omitempty"`
	CreatedAt time.Time    `db:"created_at" json:"created_at"`
}

// Response mirrors the `responses` table.
type Response struct {
	ID         pgtype.UUID  `db:"id"          json:"id"`
	PromptID   pgtype.UUID  `db:"prompt_id"   json:"prompt_id"`
	ModelName  string       `db:"model_name"  json:"model_name"`
	Response   *string      `db:"response"    json:"response,omitempty"`
	LatencyMs  *int32       `db:"latency_ms"  json:"latency_ms,omitempty"`
	TokenCount *int32       `db:"token_count" json:"token_count,omitempty"`
	Cost       *float64     `db:"cost"        json:"cost,omitempty"`
	Error      *string      `db:"error"       json:"error,omitempty"`
	CreatedAt  time.Time    `db:"created_at"  json:"created_at"`
}

// Rating mirrors the `ratings` table.
type Rating struct {
	ID          pgtype.UUID `db:"id"          json:"id"`
	ResponseID  pgtype.UUID `db:"response_id" json:"response_id"`
	Accuracy    *int16      `db:"accuracy"    json:"accuracy,omitempty"`
	Clarity     *int16      `db:"clarity"     json:"clarity,omitempty"`
	Helpfulness *int16      `db:"helpfulness" json:"helpfulness,omitempty"`
	CreatedAt   time.Time   `db:"created_at"  json:"created_at"`
	UpdatedAt   time.Time   `db:"updated_at"  json:"updated_at"`
}

// Template mirrors the `templates` table.
type Template struct {
	ID       pgtype.UUID `db:"id"       json:"id"`
	Category string      `db:"category" json:"category"`
	Title    string      `db:"title"    json:"title"`
	Body     string      `db:"body"     json:"body"`
}

// Document mirrors the `documents` table.
type Document struct {
	ID        pgtype.UUID `db:"id"         json:"id"`
	UserID    pgtype.UUID `db:"user_id"    json:"user_id"`
	Filename  string      `db:"filename"   json:"filename"`
	FileSize  int32       `db:"file_size"  json:"file_size"`
	Status    string      `db:"status"     json:"status"`
	CreatedAt time.Time   `db:"created_at" json:"created_at"`
}

// ModelScore is the per-model result produced by the AI Judge.
type ModelScore struct {
	Model     string `json:"model"`
	Score     int    `json:"score"`
	Reasoning string `json:"reasoning"`
}

// Evaluation mirrors the `evaluations` table.
type Evaluation struct {
	ID           pgtype.UUID  `db:"id"            json:"id"`
	PromptID     pgtype.UUID  `db:"prompt_id"     json:"prompt_id"`
	RankedModels []ModelScore `db:"ranked_models" json:"ranked_models"`
	CreatedAt    time.Time    `db:"created_at"    json:"created_at"`
}
