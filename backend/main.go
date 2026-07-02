package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/yourusername/ai-playground/config"
	"github.com/yourusername/ai-playground/db"
	"github.com/yourusername/ai-playground/handlers"
	"github.com/yourusername/ai-playground/middleware"
)

func main() {
	// Load configuration from .env / environment variables.
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	// Run database migrations before opening the connection pool.
	// Migrations are applied from db/migrations/ relative to the working directory.
	if err := db.RunMigrations(cfg.DatabaseURL); err != nil {
		log.Fatalf("migrations: %v", err)
	}
	log.Println("Database migrations applied successfully")

	// Connect to PostgreSQL.
	pool, err := db.NewPool(context.Background(), cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	defer pool.Close()

	log.Println("Database connection established")

	// Configure Gin.
	if cfg.Env == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()
	r.Use(gin.Logger())
	// Custom recovery middleware returns a consistent JSON error payload for all
	// unhandled panics instead of the default HTML response from gin.Default().
	r.Use(gin.CustomRecoveryWithWriter(os.Stderr, func(c *gin.Context, err any) {
		log.Printf("panic recovered: %v", err)
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "internal server error"})
	}))

	// Health check — used by Docker/load-balancer liveness probes.
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// API v1 route group.
	v1 := r.Group("/api/v1")

	// --- Public auth routes (no JWT required) ---
	authHandler := handlers.NewAuthHandler(pool, cfg.JWTSecret)
	auth := v1.Group("/auth")
	{
		auth.POST("/register", authHandler.Register)
		auth.POST("/login", authHandler.Login)
	}

	// --- Protected routes (JWT required) ---
	// All routes registered under this group will require a valid Bearer token.
	protected := v1.Group("/")
	protected.Use(middleware.AuthRequired(cfg.JWTSecret))
	{
		// Prompt fan-out (Task 4).
		promptHandler := handlers.NewPromptHandler(pool, cfg)
		protected.POST("/prompts", promptHandler.Submit)

		// Prompt history (Task 6).
		historyHandler := handlers.NewHistoryHandler(pool, cfg)
		protected.GET("/prompts", historyHandler.ListPrompts)
		protected.GET("/prompts/:id", historyHandler.GetPrompt)
		protected.POST("/prompts/:id/resubmit", historyHandler.Resubmit)

		// Cost analytics (Task 8).
		analyticsHandler := handlers.NewAnalyticsHandler(pool)
		protected.GET("/analytics", analyticsHandler.GetAnalytics)

		// Prompt templates (Task 10).
		templateHandler := handlers.NewTemplateHandler(pool)
		protected.GET("/templates", templateHandler.GetTemplates)

		// Response ratings (Task 12).
		ratingHandler := handlers.NewRatingHandler(pool)
		protected.POST("/responses/:id/rating", ratingHandler.UpsertRating)

		// Document upload & listing for RAG (Task 14).
		ragHandler := handlers.NewRAGHandler(pool, cfg)
		protected.POST("/documents", ragHandler.UploadDocument)
		protected.GET("/documents", ragHandler.ListDocuments)

		// RAG mode prompt (Task 15) — registered BEFORE /prompts/:id routes
		// to prevent Gin from matching "rag" as the :id path parameter.
		protected.POST("/prompts/rag", ragHandler.RAGPrompt)

		// AI Judge — Task 17.
		judgeHandler := handlers.NewJudgeHandler(pool, cfg)
		protected.POST("/prompts/:id/judge", judgeHandler.PostJudge)
		protected.GET("/prompts/:id/judge", judgeHandler.GetJudge)
	}

	addr := ":" + cfg.Port
	log.Printf("Starting server on %s (env=%s)", addr, cfg.Env)
	if err := r.Run(addr); err != nil {
		log.Fatalf("server: %v", err)
	}
}
