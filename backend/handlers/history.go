package handlers

import (
	"context"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yourusername/ai-playground/config"
	"github.com/yourusername/ai-playground/services"
)

// HistoryHandler holds dependencies for prompt history routes.
type HistoryHandler struct {
	DB  *pgxpool.Pool
	Cfg *config.Config
}

// NewHistoryHandler constructs a HistoryHandler.
func NewHistoryHandler(db *pgxpool.Pool, cfg *config.Config) *HistoryHandler {
	return &HistoryHandler{DB: db, Cfg: cfg}
}

// ────────────────────────────────────────────────────────────────────────────
// Response types
// ────────────────────────────────────────────────────────────────────────────

// promptListItem is a single entry in the paginated history list.
type promptListItem struct {
	ID        string  `json:"id"`
	Prompt    string  `json:"prompt"`
	CreatedAt string  `json:"created_at"`
	RagDocID  *string `json:"rag_doc_id"`
}

// listPromptsResponse is the envelope for GET /api/v1/prompts.
type listPromptsResponse struct {
	Prompts []promptListItem `json:"prompts"`
	Total   int              `json:"total"`
	Page    int              `json:"page"`
	Limit   int              `json:"limit"`
}

// ratingJSON is the rating sub-object embedded in each response detail.
type ratingJSON struct {
	Accuracy    *int16 `json:"accuracy"`
	Clarity     *int16 `json:"clarity"`
	Helpfulness *int16 `json:"helpfulness"`
}

// responseDetail is one model response with an optional rating.
type responseDetail struct {
	ID         string      `json:"id"`
	ModelName  string      `json:"model_name"`
	Response   *string     `json:"response"`
	LatencyMs  *int32      `json:"latency_ms"`
	TokenCount *int32      `json:"token_count"`
	Cost       *float64    `json:"cost"`
	Error      *string     `json:"error"`
	CreatedAt  string      `json:"created_at"`
	Rating     *ratingJSON `json:"rating"`
}

// promptDetailResponse is the envelope for GET /api/v1/prompts/:id.
type promptDetailResponse struct {
	ID        string           `json:"id"`
	Prompt    string           `json:"prompt"`
	CreatedAt string           `json:"created_at"`
	RagDocID  *string          `json:"rag_doc_id"`
	Responses []responseDetail `json:"responses"`
}

// ────────────────────────────────────────────────────────────────────────────
// GET /api/v1/prompts — paginated list
// ────────────────────────────────────────────────────────────────────────────

// ListPrompts handles GET /api/v1/prompts?page=1&limit=20.
//
// Returns prompts for the authenticated user, ordered by created_at DESC.
// Req 6 AC1, AC4, AC5.
func (h *HistoryHandler) ListPrompts(c *gin.Context) {
	userIDStr, ok := extractUserID(c)
	if !ok {
		return
	}

	// Parse pagination params — default page=1, limit=20, max limit=100.
	page := parseIntQuery(c, "page", 1)
	limit := parseIntQuery(c, "limit", 20)
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = 1
	}
	if limit > 100 {
		limit = 100
	}
	offset := (page - 1) * limit

	ctx := context.Background()

	// Count total prompts for this user.
	const countSQL = `SELECT COUNT(*) FROM prompts WHERE user_id = $1`
	var total int
	if err := h.DB.QueryRow(ctx, countSQL, userIDStr).Scan(&total); err != nil {
		log.Printf("history: count prompts: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve prompt history"})
		return
	}

	// Fetch page of prompts ordered by created_at DESC.
	const listSQL = `
		SELECT id, prompt, created_at, rag_doc_id
		FROM prompts
		WHERE user_id = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3`

	rows, err := h.DB.Query(ctx, listSQL, userIDStr, limit, offset)
	if err != nil {
		log.Printf("history: list prompts query: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve prompt history"})
		return
	}
	defer rows.Close()

	prompts := make([]promptListItem, 0)
	for rows.Next() {
		var (
			id        string
			prompt    string
			createdAt string
			ragDocID  *string
		)
		if err := rows.Scan(&id, &prompt, &createdAt, &ragDocID); err != nil {
			log.Printf("history: scan prompt row: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve prompt history"})
			return
		}
		prompts = append(prompts, promptListItem{
			ID:        id,
			Prompt:    prompt,
			CreatedAt: createdAt,
			RagDocID:  ragDocID,
		})
	}
	if err := rows.Err(); err != nil {
		log.Printf("history: rows iteration error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve prompt history"})
		return
	}

	// Req 6 AC5: return empty array (not 404) when no history exists.
	c.JSON(http.StatusOK, listPromptsResponse{
		Prompts: prompts,
		Total:   total,
		Page:    page,
		Limit:   limit,
	})
}

// ────────────────────────────────────────────────────────────────────────────
// GET /api/v1/prompts/:id — single prompt + all responses + ratings
// ────────────────────────────────────────────────────────────────────────────

// GetPrompt handles GET /api/v1/prompts/:id.
//
// Returns the prompt and all associated model responses, each with an optional
// rating object. Returns 403 if the prompt belongs to a different user.
// Req 6 AC2, Req 14.
func (h *HistoryHandler) GetPrompt(c *gin.Context) {
	userIDStr, ok := extractUserID(c)
	if !ok {
		return
	}

	promptID := c.Param("id")
	if strings.TrimSpace(promptID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing prompt id"})
		return
	}

	ctx := context.Background()

	// Fetch the prompt — include user_id for ownership check.
	const promptSQL = `
		SELECT id, user_id, prompt, created_at, rag_doc_id
		FROM prompts
		WHERE id = $1`

	var (
		pID        string
		pUserID    string
		pText      string
		pCreatedAt string
		pRagDocID  *string
	)
	err := h.DB.QueryRow(ctx, promptSQL, promptID).Scan(
		&pID, &pUserID, &pText, &pCreatedAt, &pRagDocID,
	)
	if err != nil {
		// pgx returns pgx.ErrNoRows — check the error message as a portable
		// approach that also works with wrapped errors.
		if isNotFound(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "prompt not found"})
		} else {
			log.Printf("history: get prompt %s: %v", promptID, err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve prompt"})
		}
		return
	}

	// Ownership check — Req 6 (access control implied by auth).
	if pUserID != userIDStr {
		c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
		return
	}

	// Fetch all responses for this prompt, joined with ratings (LEFT JOIN so
	// responses without a rating still appear).
	const responsesSQL = `
		SELECT
			r.id,
			r.model_name,
			r.response,
			r.latency_ms,
			r.token_count,
			r.cost,
			r.error,
			r.created_at,
			rt.accuracy,
			rt.clarity,
			rt.helpfulness
		FROM responses r
		LEFT JOIN ratings rt ON rt.response_id = r.id
		WHERE r.prompt_id = $1
		ORDER BY r.created_at ASC`

	rows, err := h.DB.Query(ctx, responsesSQL, promptID)
	if err != nil {
		log.Printf("history: query responses for prompt %s: %v", promptID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve responses"})
		return
	}
	defer rows.Close()

	responses := make([]responseDetail, 0)
	for rows.Next() {
		var (
			rID         string
			rModelName  string
			rResponse   *string
			rLatencyMs  *int32
			rTokenCount *int32
			rCost       *float64
			rError      *string
			rCreatedAt  string
			rtAccuracy  *int16
			rtClarity   *int16
			rtHelp      *int16
		)
		if err := rows.Scan(
			&rID, &rModelName, &rResponse, &rLatencyMs,
			&rTokenCount, &rCost, &rError, &rCreatedAt,
			&rtAccuracy, &rtClarity, &rtHelp,
		); err != nil {
			log.Printf("history: scan response row: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve responses"})
			return
		}

		var rating *ratingJSON
		if rtAccuracy != nil || rtClarity != nil || rtHelp != nil {
			rating = &ratingJSON{
				Accuracy:    rtAccuracy,
				Clarity:     rtClarity,
				Helpfulness: rtHelp,
			}
		}

		responses = append(responses, responseDetail{
			ID:         rID,
			ModelName:  rModelName,
			Response:   rResponse,
			LatencyMs:  rLatencyMs,
			TokenCount: rTokenCount,
			Cost:       rCost,
			Error:      rError,
			CreatedAt:  rCreatedAt,
			Rating:     rating,
		})
	}
	if err := rows.Err(); err != nil {
		log.Printf("history: rows iteration error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve responses"})
		return
	}

	c.JSON(http.StatusOK, promptDetailResponse{
		ID:        pID,
		Prompt:    pText,
		CreatedAt: pCreatedAt,
		RagDocID:  pRagDocID,
		Responses: responses,
	})
}

// ────────────────────────────────────────────────────────────────────────────
// POST /api/v1/prompts/:id/resubmit — re-dispatch to selected models
// ────────────────────────────────────────────────────────────────────────────

// resubmitRequest is the body for POST /api/v1/prompts/:id/resubmit.
type resubmitRequest struct {
	Models []string `json:"models"`
}

// Resubmit handles POST /api/v1/prompts/:id/resubmit.
//
// Looks up the stored prompt text by ID, validates ownership, then fans out
// to the requested models exactly as POST /api/v1/prompts does.
// Req 6 AC3.
func (h *HistoryHandler) Resubmit(c *gin.Context) {
	userIDStr, ok := extractUserID(c)
	if !ok {
		return
	}

	promptID := c.Param("id")
	if strings.TrimSpace(promptID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing prompt id"})
		return
	}

	var req resubmitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if len(req.Models) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "at least one model must be selected"})
		return
	}

	ctx := context.Background()

	// Look up stored prompt text and verify ownership.
	const promptSQL = `SELECT user_id, prompt FROM prompts WHERE id = $1`
	var (
		ownerID    string
		promptText string
	)
	if err := h.DB.QueryRow(ctx, promptSQL, promptID).Scan(&ownerID, &promptText); err != nil {
		if isNotFound(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "prompt not found"})
		} else {
			log.Printf("history: resubmit lookup prompt %s: %v", promptID, err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve prompt"})
		}
		return
	}

	if ownerID != userIDStr {
		c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
		return
	}

	// Persist a new prompt record for this resubmission (same text, new ID/timestamp).
	const insertPromptSQL = `
		INSERT INTO prompts (user_id, prompt)
		VALUES ($1, $2)
		RETURNING id`

	var newPromptID string
	if err := h.DB.QueryRow(ctx, insertPromptSQL, userIDStr, promptText).Scan(&newPromptID); err != nil {
		log.Printf("history: resubmit insert prompt: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist resubmitted prompt"})
		return
	}

	// Fan out to selected models.
	results := services.FanOut(ctx, promptText, req.Models, h.Cfg)

	// Persist results — same pattern as PromptHandler.Submit.
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

		if _, dbErr := h.DB.Exec(ctx, insertResponseSQL,
			newPromptID, r.ModelName,
			responseText, latencyMs, tokenCount, cost, errText,
		); dbErr != nil {
			log.Printf("history: resubmit persist response for model %s: %v", r.ModelName, dbErr)
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
		"prompt_id": newPromptID,
		"results":   jsonResults,
	})
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

// extractUserID pulls the user_id injected by the JWT middleware.
func extractUserID(c *gin.Context) (string, bool) {
	v, _ := c.Get("user_id")
	id, ok := v.(string)
	if !ok || id == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return "", false
	}
	return id, true
}

// parseIntQuery reads an integer query parameter with a fallback default.
func parseIntQuery(c *gin.Context, key string, defaultVal int) int {
	raw := c.Query(key)
	if raw == "" {
		return defaultVal
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return defaultVal
	}
	return n
}

// isNotFound returns true when pgx signals that a query returned no rows.
func isNotFound(err error) bool {
	return err != nil && strings.Contains(err.Error(), "no rows")
}
