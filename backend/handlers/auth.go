package handlers

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yourusername/ai-playground/middleware"
	"golang.org/x/crypto/bcrypt"
)

// AuthHandler holds dependencies for the auth routes (register + login).
type AuthHandler struct {
	DB        *pgxpool.Pool
	JWTSecret string
}

// NewAuthHandler constructs an AuthHandler with the provided pool and secret.
func NewAuthHandler(db *pgxpool.Pool, jwtSecret string) *AuthHandler {
	return &AuthHandler{DB: db, JWTSecret: jwtSecret}
}

// registerRequest is the expected body for POST /api/v1/auth/register.
type registerRequest struct {
	Name     string `json:"name"     binding:"required"`
	Email    string `json:"email"    binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
}

// loginRequest is the expected body for POST /api/v1/auth/login.
type loginRequest struct {
	Email    string `json:"email"    binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

// Register handles POST /api/v1/auth/register.
//
// It creates a new user record with a bcrypt-hashed password (cost 12) and
// returns a signed HS256 JWT valid for 24 hours.
func (h *AuthHandler) Register(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	req.Name = strings.TrimSpace(req.Name)

	// Hash the password with bcrypt cost 12 (per spec).
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
	if err != nil {
		log.Printf("register: bcrypt error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal server error"})
		return
	}

	// Insert the new user via parameterized query; capture the generated UUID.
	const insertSQL = `
		INSERT INTO users (name, email, password_hash)
		VALUES ($1, $2, $3)
		RETURNING id`

	var userID string
	err = h.DB.QueryRow(context.Background(), insertSQL,
		req.Name, req.Email, string(hash),
	).Scan(&userID)
	if err != nil {
		// Duplicate email → unique constraint violation (SQLSTATE 23505).
		if isDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "email already registered"})
			return
		}
		log.Printf("register: db insert error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal server error"})
		return
	}

	token, err := generateJWT(userID, req.Email, h.JWTSecret)
	if err != nil {
		log.Printf("register: jwt sign error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal server error"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"token": token})
}

// Login handles POST /api/v1/auth/login.
//
// It verifies the supplied password against the stored bcrypt hash and returns
// a signed HS256 JWT valid for 24 hours on success.
func (h *AuthHandler) Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	req.Email = strings.ToLower(strings.TrimSpace(req.Email))

	// Look up the user by email — parameterized query only.
	const selectSQL = `
		SELECT id, password_hash
		FROM users
		WHERE email = $1`

	var userID, passwordHash string
	err := h.DB.QueryRow(context.Background(), selectSQL, req.Email).
		Scan(&userID, &passwordHash)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// Use a generic message to avoid user enumeration.
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
			return
		}
		log.Printf("login: db query error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal server error"})
		return
	}

	// Constant-time bcrypt comparison.
	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	token, err := generateJWT(userID, req.Email, h.JWTSecret)
	if err != nil {
		log.Printf("login: jwt sign error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal server error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"token": token})
}

// generateJWT creates a signed HS256 JWT with user_id, email, and a 24-hour
// expiry, as required by the design spec.
func generateJWT(userID, email, secret string) (string, error) {
	claims := middleware.Claims{
		UserID: userID,
		Email:  email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secret))
}

// isDuplicateKeyError returns true when err indicates a PostgreSQL unique
// constraint violation (SQLSTATE 23505).
func isDuplicateKeyError(err error) bool {
	if err == nil {
		return false
	}
	// pgx wraps the PgError — check the message as a reliable fallback.
	return strings.Contains(err.Error(), "23505") ||
		strings.Contains(err.Error(), "unique constraint") ||
		strings.Contains(err.Error(), "duplicate key")
}
