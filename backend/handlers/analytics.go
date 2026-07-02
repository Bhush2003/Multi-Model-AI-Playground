package handlers

import (
	"context"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// knownModels is the canonical list of supported models.
// Analytics always returns an entry for every known model, even when the
// selected date range contains no data for that model (zeroes, not null).
var knownModels = []string{"gpt-4o", "gemini-1.5-pro", "claude-3-5-sonnet"}

// AnalyticsHandler holds dependencies for the analytics routes.
type AnalyticsHandler struct {
	DB *pgxpool.Pool
}

// NewAnalyticsHandler constructs an AnalyticsHandler.
func NewAnalyticsHandler(db *pgxpool.Pool) *AnalyticsHandler {
	return &AnalyticsHandler{DB: db}
}

// ────────────────────────────────────────────────────────────────────────────
// Response types
// ────────────────────────────────────────────────────────────────────────────

// perModelStats holds aggregated stats for a single model.
// Req 7 AC2, AC3.
type perModelStats struct {
	Model        string  `json:"model"`
	RequestCount int64   `json:"request_count"`
	TotalTokens  int64   `json:"total_tokens"`
	TotalCost    float64 `json:"total_cost"`
}

// analyticsResponse is the envelope for GET /api/v1/analytics.
// Req 7 AC1, AC2, AC3.
type analyticsResponse struct {
	TotalRequests int64           `json:"total_requests"`
	PerModel      []perModelStats `json:"per_model"`
}

// ────────────────────────────────────────────────────────────────────────────
// GET /api/v1/analytics
// ────────────────────────────────────────────────────────────────────────────

// GetAnalytics handles GET /api/v1/analytics?start_date=2024-01-01&end_date=2024-12-31
//
// Returns aggregated request count, token usage, and estimated cost per model
// for the authenticated user. Accepts optional start_date / end_date filters
// (ISO-8601 date strings, inclusive on both ends).
//
// Req 7 AC1, AC2, AC3, AC5, AC6.
func (h *AnalyticsHandler) GetAnalytics(c *gin.Context) {
	userIDStr, ok := extractUserID(c)
	if !ok {
		return
	}

	// --- Parse optional date-range query params (Req 7 AC5) ---
	// Dates are ISO-8601 strings like "2024-01-01".
	// start_date is inclusive (>= start_date 00:00:00 UTC).
	// end_date   is inclusive (< end_date + 1 day, i.e. < next day 00:00:00 UTC).
	var startTime, endTime *time.Time

	if raw := c.Query("start_date"); raw != "" {
		t, err := time.Parse("2006-01-02", raw)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid start_date format; expected YYYY-MM-DD"})
			return
		}
		startTime = &t
	}

	if raw := c.Query("end_date"); raw != "" {
		t, err := time.Parse("2006-01-02", raw)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid end_date format; expected YYYY-MM-DD"})
			return
		}
		// Make end_date inclusive by advancing to the start of the next day.
		next := t.AddDate(0, 0, 1)
		endTime = &next
	}

	ctx := context.Background()

	// --- Build aggregation query with optional date filters ---
	// We JOIN responses → prompts to filter by user_id and optionally created_at.
	// COALESCE ensures we get 0 instead of NULL for models with no rows.
	//
	// The query is parameterised; we build the args slice to match the $N
	// placeholders added conditionally for date filters.
	const baseSQL = `
		SELECT
			r.model_name,
			COUNT(*)                          AS request_count,
			COALESCE(SUM(r.token_count), 0)  AS total_tokens,
			COALESCE(SUM(r.cost), 0)         AS total_cost
		FROM responses r
		JOIN prompts p ON p.id = r.prompt_id
		WHERE p.user_id = $1`

	args := []interface{}{userIDStr}
	argIdx := 2
	extraWhere := ""

	if startTime != nil {
		extraWhere += " AND p.created_at >= $" + itoa(argIdx)
		args = append(args, *startTime)
		argIdx++
	}
	if endTime != nil {
		extraWhere += " AND p.created_at < $" + itoa(argIdx)
		args = append(args, *endTime)
		argIdx++
	}

	fullSQL := baseSQL + extraWhere + `
		GROUP BY r.model_name`

	rows, err := h.DB.Query(ctx, fullSQL, args...)
	if err != nil {
		log.Printf("analytics: aggregation query: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve analytics"})
		return
	}
	defer rows.Close()

	// Collect results into a map keyed by model name so we can merge with
	// knownModels and guarantee zero-values for models with no data (Req 7 AC6).
	statsMap := make(map[string]perModelStats, len(knownModels))
	for rows.Next() {
		var s perModelStats
		if err := rows.Scan(&s.Model, &s.RequestCount, &s.TotalTokens, &s.TotalCost); err != nil {
			log.Printf("analytics: scan row: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve analytics"})
			return
		}
		statsMap[s.Model] = s
	}
	if err := rows.Err(); err != nil {
		log.Printf("analytics: rows iteration error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve analytics"})
		return
	}

	// Build the ordered per-model slice, inserting zeroes for missing models.
	// Req 7 AC6: no data in range → return zeroes, not null/empty.
	perModel := make([]perModelStats, 0, len(knownModels))
	var totalRequests int64
	for _, model := range knownModels {
		s, found := statsMap[model]
		if !found {
			s = perModelStats{Model: model, RequestCount: 0, TotalTokens: 0, TotalCost: 0}
		}
		perModel = append(perModel, s)
		totalRequests += s.RequestCount
	}

	// Also include any model names returned by the DB that aren't in knownModels
	// (future-proofing — new models added to the DB still appear in the response).
	for model, s := range statsMap {
		if !contains(knownModels, model) {
			perModel = append(perModel, s)
			totalRequests += s.RequestCount
		}
	}

	c.JSON(http.StatusOK, analyticsResponse{
		TotalRequests: totalRequests,
		PerModel:      perModel,
	})
}

// ────────────────────────────────────────────────────────────────────────────
// Package-level helpers
// ────────────────────────────────────────────────────────────────────────────

// itoa converts an int to its decimal string representation without importing
// strconv (which is already imported elsewhere in the package via history.go,
// but we keep this explicit to avoid any import cycle risk in tests).
func itoa(n int) string {
	return strconv.Itoa(n)
}

// contains reports whether s is present in slice.
func contains(slice []string, s string) bool {
	for _, v := range slice {
		if v == s {
			return true
		}
	}
	return false
}
