package handlers

import (
	"context"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yourusername/ai-playground/config"
	"github.com/yourusername/ai-playground/services"
)

const maxPromptChars = 32_000

// PromptHandler holds dependencies for prompt submission routes.
type PromptHandler struct {
	DB  *pgxpool.Pool
	Cfg *config.Config
}

// NewPromptHandler constructs a PromptHandler.
func NewPromptHandler(db *pgxpool.Pool, cfg *config.Config) *PromptHandler {
	return &PromptHandler{DB: db, Cfg: cfg}
}

// submitPromptRequest is the expected body for POST /api/v1/prompts.
type submitPromptRequest struct {
	Prompt string   `json:"prompt"`
	Models []string `json:"models"`
}

// modelResultJSON is the per-model entry returned in the API response.
type modelResultJSON struct {
	Model      string   `json:"model"`
	Response   *string  `json:"response"`
	LatencyMs  *int64   `json:"latency_ms"`
	TokenCount *int     `json:"token_count"`
	Cost       *float64 `json:"cost"`
	Error      *string  `json:"error"`
}

// Submit handles POST /api/v1/prompts.
//
// It validates the request, persists the prompt, fans out to all selected
// models concurrently, persists each model result (including errors), and
// returns the full set of results to the caller.
func (h *PromptHandler) Submit(c *gin.Context) {
	var req submitPromptRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Req 3 AC4: reject empty / whitespace prompt.
	if strings.TrimSpace(req.Prompt) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "prompt must not be empty"})
		return
	}

	// Req 3 AC5: reject prompt exceeding 32,000 characters.
	if len([]rune(req.Prompt)) > maxPromptChars {
		c.JSON(http.StatusBadRequest, gin.H{"error": "prompt exceeds maximum length of 32,000 characters"})
		return
	}

	if len(req.Models) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "at least one model must be selected"})
		return
	}

	// Extract user_id injected by the JWT middleware.
	userID, _ := c.Get("user_id")
	userIDStr, ok := userID.(string)
	if !ok || userIDStr == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	ctx := context.Background()

	// Req 3 AC2: persist prompt before dispatching to models.
	const insertPromptSQL = `
		INSERT INTO prompts (user_id, prompt)
		VALUES ($1, $2)
		RETURNING id`

	var promptID string
	err := h.DB.QueryRow(ctx, insertPromptSQL, userIDStr, req.Prompt).Scan(&promptID)
	if err != nil {
		log.Printf("prompt: db insert error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist prompt"})
		return
	}

	// Req 3 AC1 + Req 13: fan out concurrently, one goroutine per model,
	// 30-second timeout per model, partial failures allowed.
	results := services.FanOut(ctx, req.Prompt, req.Models, h.Cfg)

	// Req 3 AC3 + Req 13 AC3: persist each model result (including errors).
	const insertResponseSQL = `
		INSERT INTO responses (prompt_id, model_name, response, latency_ms, token_count, cost, error)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`

	jsonResults := make([]modelResultJSON, 0, len(results))

	for _, r := range results {
		var (
			responseText *string
			latencyMs    *int64
			tokenCount   *int
			cost         *float64
			errText      *string
		)

		if r.Err != nil {
			msg := r.Err.Error()
			errText = &msg
		} else {
			responseText = &r.Response
			latencyMs = &r.LatencyMs
			tokenCount = &r.TokenCount
			cost = &r.Cost
		}

		_, dbErr := h.DB.Exec(ctx, insertResponseSQL,
			promptID,
			r.ModelName,
			responseText,
			latencyMs,
			tokenCount,
			cost,
			errText,
		)
		if dbErr != nil {
			log.Printf("prompt: persist response for model %s: %v", r.ModelName, dbErr)
			// Log the error but still return the result to the client — the
			// in-memory result is still useful even if persistence failed.
		}

		jsonResults = append(jsonResults, modelResultJSON{
			Model:      r.ModelName,
			Response:   responseText,
			LatencyMs:  latencyMs,
			TokenCount: tokenCount,
			Cost:       cost,
			Error:      errText,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"prompt_id": promptID,
		"results":   jsonResults,
	})
}
