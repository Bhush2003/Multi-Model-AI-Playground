package handlers_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/yourusername/ai-playground/handlers"
	"github.com/yourusername/ai-playground/middleware"
)

// jwtSecret used by all tests.
const testSecret = "test-jwt-secret-value"

// setupRouter builds a Gin engine wired with the auth routes and the given
// AuthHandler. Using a real handler instance but a mock DB via pgxpool is not
// feasible without a live DB, so these tests validate:
//   - HTTP binding / validation (no DB call made on bad input)
//   - JWT generation helper output shape
func setupRouter(h *handlers.AuthHandler) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/api/v1/auth/register", h.Register)
	r.POST("/api/v1/auth/login", h.Login)
	return r
}

// ── JWT generation tests (no DB needed) ──────────────────────────────────────

func TestGenerateJWT_ValidToken(t *testing.T) {
	// generateJWT is package-private; test it indirectly via a register call
	// would need a DB.  Instead, validate the Claims struct directly.
	claims := &middleware.Claims{
		UserID: "abc-123",
		Email:  "user@example.com",
	}
	claims.RegisteredClaims = jwt.RegisteredClaims{}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenStr, err := token.SignedString([]byte(testSecret))
	if err != nil {
		t.Fatalf("signing failed: %v", err)
	}

	parsed, err := jwt.ParseWithClaims(tokenStr, &middleware.Claims{},
		func(_ *jwt.Token) (interface{}, error) { return []byte(testSecret), nil })
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}
	if !parsed.Valid {
		t.Fatal("expected token to be valid")
	}
	got, ok := parsed.Claims.(*middleware.Claims)
	if !ok {
		t.Fatal("claims type assertion failed")
	}
	if got.UserID != "abc-123" {
		t.Errorf("UserID: got %q, want %q", got.UserID, "abc-123")
	}
	if got.Email != "user@example.com" {
		t.Errorf("Email: got %q, want %q", got.Email, "user@example.com")
	}
}

func TestAuthMiddleware_MissingHeader(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(middleware.AuthRequired(testSecret))
	r.GET("/protected", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestAuthMiddleware_InvalidToken(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(middleware.AuthRequired(testSecret))
	r.GET("/protected", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer not.a.valid.token")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestAuthMiddleware_ValidToken(t *testing.T) {
	gin.SetMode(gin.TestMode)

	// Build a valid token manually.
	claims := &middleware.Claims{
		UserID: "user-999",
		Email:  "x@example.com",
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, _ := tok.SignedString([]byte(testSecret))

	r := gin.New()
	r.Use(middleware.AuthRequired(testSecret))
	r.GET("/protected", func(c *gin.Context) {
		uid, _ := c.Get("user_id")
		c.JSON(http.StatusOK, gin.H{"user_id": uid})
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer "+signed)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if resp["user_id"] != "user-999" {
		t.Errorf("user_id in context: got %v, want %q", resp["user_id"], "user-999")
	}
}

// ── Input validation tests (no DB needed) ────────────────────────────────────

func TestRegister_MissingFields(t *testing.T) {
	// AuthHandler with nil DB — binding failures happen before any DB call.
	h := handlers.NewAuthHandler(nil, testSecret)
	r := setupRouter(h)

	body, _ := json.Marshal(map[string]string{"email": "a@b.com"}) // missing name+password
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestRegister_InvalidEmail(t *testing.T) {
	h := handlers.NewAuthHandler(nil, testSecret)
	r := setupRouter(h)

	body, _ := json.Marshal(map[string]string{
		"name":     "Alice",
		"email":    "not-an-email",
		"password": "supersecret123",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestRegister_ShortPassword(t *testing.T) {
	h := handlers.NewAuthHandler(nil, testSecret)
	r := setupRouter(h)

	body, _ := json.Marshal(map[string]string{
		"name":     "Alice",
		"email":    "alice@example.com",
		"password": "short", // < 8 chars
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestLogin_MissingFields(t *testing.T) {
	h := handlers.NewAuthHandler(nil, testSecret)
	r := setupRouter(h)

	body, _ := json.Marshal(map[string]string{"email": "a@b.com"}) // missing password
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestAuthMiddleware_WrongSigningAlg(t *testing.T) {
	gin.SetMode(gin.TestMode)
	// Build a token with RS256 (different algorithm) but we can't sign it
	// without an RSA key — instead use a token signed with a different HMAC secret.
	claims := &middleware.Claims{
		UserID: "bad-actor",
		Email:  "bad@example.com",
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, _ := tok.SignedString([]byte("wrong-secret"))

	r := gin.New()
	r.Use(middleware.AuthRequired(testSecret))
	r.GET("/protected", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})

	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer "+signed)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for wrong secret, got %d", w.Code)
	}
}
