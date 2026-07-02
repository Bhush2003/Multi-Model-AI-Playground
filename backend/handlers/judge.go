package handlers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yourusername/ai-playground/config"
	"github.com/yourusername/ai-playground/services"
)

// JudgeHandler holds dependencies for the AI Judge routes.
type JudgeHandler struct {
	DB  *pgxpool.Pool
	Cfg *config.Config
}

// NewJudgeHandler constructs a JudgeHandler with the provided pool and config.
func NewJudgeHandler(db *pgxpool.Pool, cfg *config.Config) *JudgeHandler {
	return &JudgeHandler{DB: db, Cfg: cfg}
}

// PostJudge handles POST /api/v1/prompts/:id/judge.
//
// Req 12 AC2: submit all model responses to the GPT-based AI_Judge.
// Req 12 AC3: parse the structured result (ranked list, scores, reasoning).
// Req 12 AC5: return 502 if the AI_Judge call fails or returns a malformed response.
// Req 12 AC6: persist the evaluation result associated with the prompt ID.
func (h *JudgeHandler) PostJudge(c *gin.Context) {
	userIDStr, ok := extractUserID(c)
	if !ok {
		return
	}

	promptID := c.Param("id")
	ctx := context.Background()

	// 1. Check prompt exists and belongs to the authenticated user.
	const promptSQL = `SELECT user_id, prompt FROM prompts WHERE id = $1`
	var promptOwnerID, promptText string
	err := h.DB.QueryRow(ctx, promptSQL, promptID).Scan(&promptOwnerID, &promptText)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "prompt not found"})
		return
	}
	if promptOwnerID != userIDStr {
		c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
		return
	}

	// 2. Load successful responses for this prompt.
	const responsesSQL = `
		SELECT model_name, response
		FROM responses
		WHERE prompt_id = $1
		  AND response IS NOT NULL
		  AND error IS NULL`

	rows, err := h.DB.Query(ctx, responsesSQL, promptID)
	if err != nil {
		log.Printf("judge post: query responses: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load responses"})
		return
	}
	defer rows.Close()

	modelResponses := make(map[string]string)
	for rows.Next() {
		var modelName, responseText string
		if err := rows.Scan(&modelName, &responseText); err != nil {
			log.Printf("judge post: scan response: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load responses"})
			return
		}
		modelResponses[modelName] = responseText
	}
	if err := rows.Err(); err != nil {
		log.Printf("judge post: rows error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load responses"})
		return
	}

	if len(modelResponses) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no successful responses available to evaluate"})
		return
	}

	// 3. Call the AI Judge service.
	svc := &services.JudgeService{APIKey: h.Cfg.OpenAIAPIKey}
	result, err := svc.Evaluate(ctx, promptText, modelResponses)
	if err != nil {
		log.Printf("judge post: evaluate: %v", err)
		// Req 12 AC5: return 502 when the evaluation service is unavailable.
		c.JSON(http.StatusBadGateway, gin.H{"error": "evaluation service is unavailable"})
		return
	}

	// 4. Marshal ranked_models to JSONB bytes for storage.
	rankedJSON, err := json.Marshal(result.RankedModels)
	if err != nil {
		log.Printf("judge post: marshal ranked models: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to marshal evaluation result"})
		return
	}

	// 5. UPSERT the evaluation result into the evaluations table.
	// Req 12 AC6: persist to the evaluations table.
	const upsertSQL = `
		INSERT INTO evaluations (prompt_id, ranked_models)
		VALUES ($1, $2)
		ON CONFLICT (prompt_id)
		DO UPDATE SET ranked_models = EXCLUDED.ranked_models`

	if _, err := h.DB.Exec(ctx, upsertSQL, promptID, rankedJSON); err != nil {
		log.Printf("judge post: upsert evaluation: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist evaluation"})
		return
	}

	// 6. Return the evaluation result.
	c.JSON(http.StatusOK, gin.H{
		"prompt_id":     promptID,
		"winner":        result.Winner,
		"ranked_models": result.RankedModels,
	})
}

// GetJudge handles GET /api/v1/prompts/:id/judge.
//
// Req 12 AC6: retrieve the persisted evaluation result from prompt history.
func (h *JudgeHandler) GetJudge(c *gin.Context) {
	userIDStr, ok := extractUserID(c)
	if !ok {
		return
	}

	promptID := c.Param("id")
	ctx := context.Background()

	// 1. Verify prompt exists and belongs to the authenticated user.
	const promptSQL = `SELECT user_id FROM prompts WHERE id = $1`
	var promptOwnerID string
	err := h.DB.QueryRow(ctx, promptSQL, promptID).Scan(&promptOwnerID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "prompt not found"})
		return
	}
	if promptOwnerID != userIDStr {
		c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
		return
	}

	// 2. Load the evaluation result.
	const evalSQL = `SELECT ranked_models FROM evaluations WHERE prompt_id = $1`
	var rankedModelsJSON []byte
	err = h.DB.QueryRow(ctx, evalSQL, promptID).Scan(&rankedModelsJSON)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "evaluation not found"})
		return
	}

	// 3. Unmarshal the JSONB into the slice of model scores.
	var rankedModels []services.JudgeModelScore
	if err := json.Unmarshal(rankedModelsJSON, &rankedModels); err != nil {
		log.Printf("judge get: unmarshal ranked models: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to parse evaluation result"})
		return
	}

	// 4. Determine winner from the first item (already sorted descending by score).
	winner := ""
	if len(rankedModels) > 0 {
		winner = rankedModels[0].Model
	}

	c.JSON(http.StatusOK, gin.H{
		"prompt_id":     promptID,
		"winner":        winner,
		"ranked_models": rankedModels,
	})
}
