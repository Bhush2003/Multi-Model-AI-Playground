package services_test

import (
	"context"
	"testing"
	"time"

	"github.com/yourusername/ai-playground/config"
	"github.com/yourusername/ai-playground/services"
)

// TestFanOut_ReturnsOneResultPerModel verifies that FanOut always returns
// exactly one ModelResult per selected model, even when model calls fail.
// Req 13 AC1: one model failure must not prevent other results from being returned.
func TestFanOut_ReturnsOneResultPerModel(t *testing.T) {
	cfg := &config.Config{} // empty keys — all provider calls will fail quickly

	models := []string{"gpt-4o", "gemini-1.5-pro", "claude-3-5-sonnet"}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	results := services.FanOut(ctx, "test prompt", models, cfg)

	if len(results) != len(models) {
		t.Errorf("expected %d results, got %d", len(models), len(results))
	}

	// All model names should be present in results.
	resultMap := make(map[string]services.ModelResult)
	for _, r := range results {
		resultMap[r.ModelName] = r
	}
	for _, model := range models {
		if _, ok := resultMap[model]; !ok {
			t.Errorf("missing result for model %q", model)
		}
	}
}

// TestFanOut_UnknownModelReturnsError verifies that an unknown model name
// results in a ModelResult with a non-nil Err rather than blocking or panicking.
// Req 13 AC1: unknown models must not block or suppress other results.
func TestFanOut_UnknownModelReturnsError(t *testing.T) {
	cfg := &config.Config{}
	ctx := context.Background()

	results := services.FanOut(ctx, "test", []string{"unknown-model-xyz"}, cfg)

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Err == nil {
		t.Error("expected non-nil Err for unknown model")
	}
}

// TestFanOut_PartialFailureDoesNotBlockOthers verifies that when some models
// fail, the remaining results are still returned within the overall timeout.
// Req 13 AC1: partial model failure must return all results (successful + failed).
func TestFanOut_PartialFailureDoesNotBlockOthers(t *testing.T) {
	cfg := &config.Config{} // empty keys — all real provider calls fail

	// Mix of a known (will fail with API error) and unknown model.
	models := []string{"gpt-4o", "unknown-model-xyz"}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	results := services.FanOut(ctx, "hello", models, cfg)

	if len(results) != len(models) {
		t.Errorf("expected %d results, got %d", len(models), len(results))
	}

	// The unknown model must have a non-nil error.
	for _, r := range results {
		if r.ModelName == "unknown-model-xyz" && r.Err == nil {
			t.Error("expected non-nil Err for unknown-model-xyz")
		}
	}
}
