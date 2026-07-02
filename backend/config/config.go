package config

import (
	"fmt"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

// Config holds all environment-driven configuration for the application.
type Config struct {
	DatabaseURL      string
	JWTSecret        string
	OpenAIAPIKey     string
	GeminiAPIKey     string
	AnthropicAPIKey  string
	ChromaURL        string
	Port             string
	Env              string
}

// Load reads the .env file (if present) and then reads all required variables
// from the environment. It returns an error if any required variable is missing.
func Load() (*Config, error) {
	// Load .env file — ignore error so the app still starts when running in a
	// container where env vars are injected directly.
	_ = godotenv.Load()

	cfg := &Config{
		DatabaseURL:     getEnv("DATABASE_URL", ""),
		JWTSecret:       getEnv("JWT_SECRET", ""),
		OpenAIAPIKey:    getEnv("OPENAI_API_KEY", ""),
		GeminiAPIKey:    getEnv("GEMINI_API_KEY", ""),
		AnthropicAPIKey: getEnv("ANTHROPIC_API_KEY", ""),
		ChromaURL:       getEnv("CHROMA_URL", "http://localhost:8000"),
		Port:            getEnv("PORT", "8080"),
		Env:             getEnv("ENV", "development"),
	}

	if err := cfg.validate(); err != nil {
		return nil, err
	}

	return cfg, nil
}

// validate checks that all required fields are present.
func (c *Config) validate() error {
	required := map[string]string{
		"DATABASE_URL": c.DatabaseURL,
		"JWT_SECRET":   c.JWTSecret,
	}
	for key, val := range required {
		if val == "" {
			return fmt.Errorf("missing required environment variable: %s", key)
		}
	}
	return nil
}

// getEnv returns the value of the named environment variable, or fallback if
// it is not set.
func getEnv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok {
		return v
	}
	return fallback
}

// GetInt returns an env variable parsed as int, with a default fallback.
func GetInt(key string, fallback int) int {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return fallback
	}
	return n
}
