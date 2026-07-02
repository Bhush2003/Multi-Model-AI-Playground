package services

import (
	"context"
	"fmt"
	"time"

	"github.com/yourusername/ai-playground/config"
)

// ModelResult holds the outcome of a single model call made by the fan-out service.
type ModelResult struct {
	ModelName    string
	Response     string
	LatencyMs    int64
	TokenCount   int     // total tokens (input + output)
	InputTokens  int     // for cost calculation
	OutputTokens int     // for cost calculation
	Cost         float64
	Err          error
}

// modelTimeout is the per-model deadline applied by FanOut.
const modelTimeout = 30 * time.Second

// fanOutCaller is the function type used to dispatch a single model call.
// It is a package-level variable so tests can substitute a lightweight fake
// without modifying production code.
type fanOutCaller func(ctx context.Context, modelName, prompt string, cfg *config.Config) ModelResult

// defaultCaller is the production implementation; assigned at package init so
// that tests can override fanOutCallerFn without touching the real callModel.
var fanOutCallerFn fanOutCaller = callModel

// FanOut dispatches the prompt concurrently to each named model and returns one
// ModelResult per model. Each goroutine runs with a 30-second context timeout
// derived from the parent ctx. A per-model failure or timeout never cancels the
// other goroutines.
//
// Resilience guarantee: the buffered channel has capacity len(models), so every
// goroutine can send its result without blocking, regardless of whether it
// succeeded or failed. The collector loop always reads exactly len(models)
// values, so partial failures (timeouts, provider errors) are recorded as
// ModelResult.Err and returned alongside successful results — a single model
// outage never prevents the caller from receiving the other models' responses.
func FanOut(ctx context.Context, prompt string, models []string, cfg *config.Config) []ModelResult {
	ch := make(chan ModelResult, len(models))

	for _, m := range models {
		go func(modelName string) {
			// Each model gets its own independent 30-second timeout so that a
			// slow model does not block the others from completing.
			modelCtx, cancel := context.WithTimeout(ctx, modelTimeout)
			defer cancel()

			ch <- fanOutCallerFn(modelCtx, modelName, prompt, cfg)
		}(m)
	}

	results := make([]ModelResult, 0, len(models))
	for range models {
		results = append(results, <-ch)
	}
	return results
}

// callModel dispatches a single model call and wraps the result in a ModelResult.
func callModel(ctx context.Context, modelName, prompt string, cfg *config.Config) ModelResult {
	switch modelName {
	case "gpt-4o":
		svc := &OpenAIService{APIKey: cfg.OpenAIAPIKey}
		text, in, out, latency, cost, err := svc.Call(ctx, prompt)
		if err != nil {
			return ModelResult{ModelName: modelName, Err: wrapTimeoutErr(ctx, err)}
		}
		return ModelResult{
			ModelName:    modelName,
			Response:     text,
			LatencyMs:    latency,
			InputTokens:  in,
			OutputTokens: out,
			TokenCount:   in + out,
			Cost:         cost,
		}

	case "gemini-1.5-pro":
		svc := &GeminiService{APIKey: cfg.GeminiAPIKey}
		text, in, out, latency, cost, err := svc.Call(ctx, prompt)
		if err != nil {
			return ModelResult{ModelName: modelName, Err: wrapTimeoutErr(ctx, err)}
		}
		return ModelResult{
			ModelName:    modelName,
			Response:     text,
			LatencyMs:    latency,
			InputTokens:  in,
			OutputTokens: out,
			TokenCount:   in + out,
			Cost:         cost,
		}

	case "claude-3-5-sonnet":
		svc := &ClaudeService{APIKey: cfg.AnthropicAPIKey}
		text, in, out, latency, cost, err := svc.Call(ctx, prompt)
		if err != nil {
			return ModelResult{ModelName: modelName, Err: wrapTimeoutErr(ctx, err)}
		}
		return ModelResult{
			ModelName:    modelName,
			Response:     text,
			LatencyMs:    latency,
			InputTokens:  in,
			OutputTokens: out,
			TokenCount:   in + out,
			Cost:         cost,
		}

	default:
		return ModelResult{
			ModelName: modelName,
			Err:       fmt.Errorf("unsupported model: %s", modelName),
		}
	}
}

// wrapTimeoutErr replaces a generic context error with a human-readable
// "timeout after 30s" message when the context deadline was exceeded.
func wrapTimeoutErr(ctx context.Context, err error) error {
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("timeout after 30s")
	}
	return err
}
