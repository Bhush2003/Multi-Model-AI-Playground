package handlers

import (
	"context"
	"fmt"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// RatingHandler holds dependencies for the response rating routes.
type RatingHandler struct {
	DB *pgxpool.Pool
}

// NewRatingHandler constructs a RatingHandler.
func NewRatingHandler(db *pgxpool.Pool) *RatingHandler {
	return &RatingHandler{DB: db}
}

// ratingRequest is the JSON body for POST /api/v1/responses/:id/rating.
// All three fields are required (pointer so we can detect missing vs zero).
type ratingRequest struct {
	Accuracy    *int `json:"accuracy"`
	Clarity     *int `json:"clarity"`
	Helpfulness *int `json:"helpfulness"`
}

// ratingResponse is the 200 envelope returned after a successful upsert.
type ratingResponse struct {
	ResponseID  string `json:"response_id"`
	Accuracy    int    `json:"accuracy"`
	Clarity     int    `json:"clarity"`
	Helpfulness int    `json:"helpfulness"`
}

// UpsertRating handles POST /api/v1/responses/:id/rating.
//
// Validates that accuracy, clarity, and helpfulness are each between 1 and 5,
// verifies the response row exists, then upserts the rating record.
//
// Req 9 AC1 — rating controls for Accuracy, Clarity, Helpfulness (1–5 each)
// Req 9 AC2 — persist rating values against the response ID
// Req 9 AC3 — allow updating a previously submitted rating (upsert)
// Req 9 AC5 — rating value outside 1–5 → 400 with descriptive error
func (h *RatingHandler) UpsertRating(c *gin.Context) {
	responseID := c.Param("id")

	// Bind JSON body.
	var req ratingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate that all three fields are present and in range.
	if req.Accuracy == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "accuracy is required"})
		return
	}
	if req.Clarity == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "clarity is required"})
		return
	}
	if req.Helpfulness == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "helpfulness is required"})
		return
	}

	if err := validateRatingField("accuracy", *req.Accuracy); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := validateRatingField("clarity", *req.Clarity); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := validateRatingField("helpfulness", *req.Helpfulness); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := context.Background()

	// Verify the response row exists — Req 9 (implicit: can only rate a real response).
	const checkSQL = `SELECT id FROM responses WHERE id = $1`
	var exists string
	if err := h.DB.QueryRow(ctx, checkSQL, responseID).Scan(&exists); err != nil {
		if isNotFound(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "response not found"})
		} else {
			log.Printf("rating: check response %s: %v", responseID, err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to verify response"})
		}
		return
	}

	// Upsert rating — ON CONFLICT (response_id) updates all three fields and
	// bumps updated_at. Req 9 AC2, AC3.
	const upsertSQL = `
		INSERT INTO ratings (response_id, accuracy, clarity, helpfulness)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (response_id) DO UPDATE
			SET accuracy    = EXCLUDED.accuracy,
			    clarity     = EXCLUDED.clarity,
			    helpfulness = EXCLUDED.helpfulness,
			    updated_at  = NOW()`

	if _, err := h.DB.Exec(ctx, upsertSQL,
		responseID, *req.Accuracy, *req.Clarity, *req.Helpfulness,
	); err != nil {
		log.Printf("rating: upsert for response %s: %v", responseID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save rating"})
		return
	}

	c.JSON(http.StatusOK, ratingResponse{
		ResponseID:  responseID,
		Accuracy:    *req.Accuracy,
		Clarity:     *req.Clarity,
		Helpfulness: *req.Helpfulness,
	})
}

// validateRatingField returns a descriptive error when val is outside 1–5.
func validateRatingField(field string, val int) error {
	if val < 1 || val > 5 {
		return fmt.Errorf("%s must be between 1 and 5", field)
	}
	return nil
}
