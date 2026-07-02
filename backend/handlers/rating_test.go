package handlers_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/yourusername/ai-playground/handlers"
	"github.com/yourusername/ai-playground/middleware"
)

// setupRatingRouter builds a Gin engine with the rating route protected by JWT.
// Uses gin.Recovery() so that a nil-DB panic (when valid input reaches the DB
// call) is caught and turned into a 500 rather than crashing the test process.
func setupRatingRouter(h *handlers.RatingHandler) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(middleware.AuthRequired(testSecret))
	r.POST("/api/v1/responses/:id/rating", h.UpsertRating)
	return r
}

// postRating is a helper that fires a POST to the rating endpoint.
func postRating(r *gin.Engine, body interface{}) *httptest.ResponseRecorder {
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/responses/some-response-id/rating",
		bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", validAuthHeader("user-1"))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// ── Valid body — must NOT be rejected with 400 ────────────────────────────────

// TestRating_ValidBody confirms that a well-formed body passes validation and
// reaches the DB call. With a nil pool the handler panics; gin.Recovery turns
// that into a 500 — the key assertion is that we do NOT get a 400.
func TestRating_ValidBody(t *testing.T) {
	h := handlers.NewRatingHandler(nil)
	r := setupRatingRouter(h)

	w := postRating(r, map[string]interface{}{
		"accuracy":    4,
		"clarity":     5,
		"helpfulness": 3,
	})

	if w.Code == http.StatusBadRequest {
		t.Errorf("valid body: should not produce 400 — body: %s", w.Body.String())
	}
}

// ── accuracy out-of-range ────────────────────────────────────────────────────

// TestRating_AccuracyZero verifies that accuracy=0 is rejected with 400.
// Req 9 AC5.
func TestRating_AccuracyZero(t *testing.T) {
	h := handlers.NewRatingHandler(nil)
	r := setupRatingRouter(h)

	w := postRating(r, map[string]interface{}{
		"accuracy":    0,
		"clarity":     3,
		"helpfulness": 3,
	})

	if w.Code != http.StatusBadRequest {
		t.Errorf("accuracy=0: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
	assertErrorField(t, w, "accuracy")
}

// TestRating_AccuracySix verifies that accuracy=6 is rejected with 400.
// Req 9 AC5.
func TestRating_AccuracySix(t *testing.T) {
	h := handlers.NewRatingHandler(nil)
	r := setupRatingRouter(h)

	w := postRating(r, map[string]interface{}{
		"accuracy":    6,
		"clarity":     3,
		"helpfulness": 3,
	})

	if w.Code != http.StatusBadRequest {
		t.Errorf("accuracy=6: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
	assertErrorField(t, w, "accuracy")
}

// ── clarity out-of-range ─────────────────────────────────────────────────────

// TestRating_ClarityZero verifies that clarity=0 is rejected with 400.
// Req 9 AC5.
func TestRating_ClarityZero(t *testing.T) {
	h := handlers.NewRatingHandler(nil)
	r := setupRatingRouter(h)

	w := postRating(r, map[string]interface{}{
		"accuracy":    3,
		"clarity":     0,
		"helpfulness": 3,
	})

	if w.Code != http.StatusBadRequest {
		t.Errorf("clarity=0: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
	assertErrorField(t, w, "clarity")
}

// ── helpfulness out-of-range ─────────────────────────────────────────────────

// TestRating_HelpfulnessSix verifies that helpfulness=6 is rejected with 400.
// Req 9 AC5.
func TestRating_HelpfulnessSix(t *testing.T) {
	h := handlers.NewRatingHandler(nil)
	r := setupRatingRouter(h)

	w := postRating(r, map[string]interface{}{
		"accuracy":    3,
		"clarity":     3,
		"helpfulness": 6,
	})

	if w.Code != http.StatusBadRequest {
		t.Errorf("helpfulness=6: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
	assertErrorField(t, w, "helpfulness")
}

// ── missing fields ───────────────────────────────────────────────────────────

// TestRating_MissingAccuracy verifies that omitting accuracy is rejected with 400.
// Req 9 AC5.
func TestRating_MissingAccuracy(t *testing.T) {
	h := handlers.NewRatingHandler(nil)
	r := setupRatingRouter(h)

	w := postRating(r, map[string]interface{}{
		"clarity":     3,
		"helpfulness": 3,
	})

	if w.Code != http.StatusBadRequest {
		t.Errorf("missing accuracy: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
}

// TestRating_MissingClarity verifies that omitting clarity is rejected with 400.
func TestRating_MissingClarity(t *testing.T) {
	h := handlers.NewRatingHandler(nil)
	r := setupRatingRouter(h)

	w := postRating(r, map[string]interface{}{
		"accuracy":    3,
		"helpfulness": 3,
	})

	if w.Code != http.StatusBadRequest {
		t.Errorf("missing clarity: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
}

// TestRating_MissingHelpfulness verifies that omitting helpfulness is rejected with 400.
func TestRating_MissingHelpfulness(t *testing.T) {
	h := handlers.NewRatingHandler(nil)
	r := setupRatingRouter(h)

	w := postRating(r, map[string]interface{}{
		"accuracy": 3,
		"clarity":  3,
	})

	if w.Code != http.StatusBadRequest {
		t.Errorf("missing helpfulness: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
}

// TestRating_EmptyBody verifies that an empty JSON body is rejected with 400.
func TestRating_EmptyBody(t *testing.T) {
	h := handlers.NewRatingHandler(nil)
	r := setupRatingRouter(h)

	w := postRating(r, map[string]interface{}{})

	if w.Code != http.StatusBadRequest {
		t.Errorf("empty body: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
}

// ── boundary values — must NOT be rejected ───────────────────────────────────

// TestRating_BoundaryMin verifies that all fields set to 1 pass validation.
func TestRating_BoundaryMin(t *testing.T) {
	h := handlers.NewRatingHandler(nil)
	r := setupRatingRouter(h)

	w := postRating(r, map[string]interface{}{
		"accuracy":    1,
		"clarity":     1,
		"helpfulness": 1,
	})

	if w.Code == http.StatusBadRequest {
		t.Errorf("min boundary (1,1,1): should not produce 400 — body: %s", w.Body.String())
	}
}

// TestRating_BoundaryMax verifies that all fields set to 5 pass validation.
func TestRating_BoundaryMax(t *testing.T) {
	h := handlers.NewRatingHandler(nil)
	r := setupRatingRouter(h)

	w := postRating(r, map[string]interface{}{
		"accuracy":    5,
		"clarity":     5,
		"helpfulness": 5,
	})

	if w.Code == http.StatusBadRequest {
		t.Errorf("max boundary (5,5,5): should not produce 400 — body: %s", w.Body.String())
	}
}

// ── helpers ──────────────────────────────────────────────────────────────────

// assertErrorField checks that the response body contains an "error" key whose
// value mentions the given field name.
func assertErrorField(t *testing.T, w *httptest.ResponseRecorder, field string) {
	t.Helper()
	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal error response: %v", err)
	}
	errMsg, _ := resp["error"].(string)
	if errMsg == "" {
		t.Errorf("expected non-empty 'error' field in response body")
		return
	}
	// The error message should name the offending field.
	if !containsString(errMsg, field) {
		t.Errorf("expected error message to mention %q, got: %q", field, errMsg)
	}
}

// containsString reports whether sub is a substring of s (case-sensitive).
func containsString(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub ||
		func() bool {
			for i := 0; i <= len(s)-len(sub); i++ {
				if s[i:i+len(sub)] == sub {
					return true
				}
			}
			return false
		}())
}
