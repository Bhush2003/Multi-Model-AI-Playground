package handlers_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/yourusername/ai-playground/handlers"
	"github.com/yourusername/ai-playground/middleware"

	"github.com/golang-jwt/jwt/v5"
)

// setupPromptRouter builds a test Gin engine with the prompt route protected
// by the JWT middleware. The PromptHandler is constructed with a nil DB and nil
// config so that only request-binding and validation logic is exercised (no DB
// or AI-provider calls are made for the validation tests).
func setupPromptRouter(h *handlers.PromptHandler) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()

	// Inject a valid JWT so the middleware passes for tests that should reach
	// handler logic.
	r.Use(middleware.AuthRequired(testSecret))
	r.POST("/api/v1/prompts", h.Submit)
	return r
}

// validAuthHeader builds an Authorization header value with a signed JWT that
// contains the given userID, using testSecret.
func validAuthHeader(userID string) string {
	claims := &middleware.Claims{UserID: userID, Email: "test@example.com"}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, _ := tok.SignedString([]byte(testSecret))
	return "Bearer " + signed
}

// ── Validation: empty / whitespace prompt (Req 3 AC4) ──────────────────────

func TestPromptSubmit_EmptyPrompt(t *testing.T) {
	h := handlers.NewPromptHandler(nil, nil)
	r := setupPromptRouter(h)

	body, _ := json.Marshal(map[string]interface{}{
		"prompt": "",
		"models": []string{"gpt-4o"},
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/prompts", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", validAuthHeader("user-1"))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("empty prompt: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
}

func TestPromptSubmit_WhitespaceOnlyPrompt(t *testing.T) {
	h := handlers.NewPromptHandler(nil, nil)
	r := setupPromptRouter(h)

	body, _ := json.Marshal(map[string]interface{}{
		"prompt": "   \t\n  ",
		"models": []string{"gpt-4o"},
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/prompts", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", validAuthHeader("user-1"))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("whitespace prompt: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
}

// ── Validation: prompt exceeds 32,000 chars (Req 3 AC5) ────────────────────

func TestPromptSubmit_PromptExceedsMaxLength(t *testing.T) {
	h := handlers.NewPromptHandler(nil, nil)
	r := setupPromptRouter(h)

	// Build a prompt that is exactly 32,001 characters.
	longPrompt := strings.Repeat("a", 32_001)
	body, _ := json.Marshal(map[string]interface{}{
		"prompt": longPrompt,
		"models": []string{"gpt-4o"},
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/prompts", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", validAuthHeader("user-1"))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("over-length prompt: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
}

func TestPromptSubmit_PromptAtExactMaxLength(t *testing.T) {
	// A prompt of exactly 32,000 characters must pass input validation.
	// We wire Gin's recovery middleware so the nil-DB panic inside the handler
	// is caught and turned into a 500 (rather than crashing the test process).
	h := handlers.NewPromptHandler(nil, nil)

	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(gin.Recovery()) // catches nil-DB panic → 500
	r.Use(middleware.AuthRequired(testSecret))
	r.POST("/api/v1/prompts", h.Submit)

	promptAt32k := strings.Repeat("a", 32_000)
	body, _ := json.Marshal(map[string]interface{}{
		"prompt": promptAt32k,
		"models": []string{"gpt-4o"},
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/prompts", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", validAuthHeader("user-1"))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Must not be rejected with 400 from validation.
	if w.Code == http.StatusBadRequest {
		t.Errorf("32k-char prompt: should not be rejected by validation (got 400) — body: %s", w.Body.String())
	}
}

// ── Validation: no models selected ──────────────────────────────────────────

func TestPromptSubmit_NoModels(t *testing.T) {
	h := handlers.NewPromptHandler(nil, nil)
	r := setupPromptRouter(h)

	body, _ := json.Marshal(map[string]interface{}{
		"prompt": "Hello world",
		"models": []string{},
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/prompts", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", validAuthHeader("user-1"))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("no models: expected 400, got %d — body: %s", w.Code, w.Body.String())
	}
}

// ── Validation: missing Authorization header ─────────────────────────────────

func TestPromptSubmit_Unauthenticated(t *testing.T) {
	h := handlers.NewPromptHandler(nil, nil)
	r := setupPromptRouter(h)

	body, _ := json.Marshal(map[string]interface{}{
		"prompt": "Hello",
		"models": []string{"gpt-4o"},
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/prompts", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	// No Authorization header.
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("unauthenticated: expected 401, got %d", w.Code)
	}
}

// ── Error message content checks ─────────────────────────────────────────────

func TestPromptSubmit_EmptyPromptErrorMessage(t *testing.T) {
	h := handlers.NewPromptHandler(nil, nil)
	r := setupPromptRouter(h)

	body, _ := json.Marshal(map[string]interface{}{
		"prompt": "",
		"models": []string{"gpt-4o"},
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/prompts", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", validAuthHeader("user-1"))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	errMsg, _ := resp["error"].(string)
	if errMsg == "" {
		t.Error("expected non-empty error message in response body")
	}
}

func TestPromptSubmit_TooLongPromptErrorMessage(t *testing.T) {
	h := handlers.NewPromptHandler(nil, nil)
	r := setupPromptRouter(h)

	body, _ := json.Marshal(map[string]interface{}{
		"prompt": strings.Repeat("x", 32_001),
		"models": []string{"gpt-4o"},
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/prompts", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", validAuthHeader("user-1"))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	errMsg, _ := resp["error"].(string)
	if !strings.Contains(errMsg, "32,000") {
		t.Errorf("expected error to mention 32,000 chars, got: %q", errMsg)
	}
}
