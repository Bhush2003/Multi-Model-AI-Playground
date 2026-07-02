package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const (
	openAIEndpoint = "https://api.openai.com/v1/chat/completions"
	openAIModel    = "gpt-4o"

	// Per-1K-token pricing for gpt-4o (USD).
	openAIInputPricePerK  = 0.005
	openAIOutputPricePerK = 0.015
)

// OpenAIService handles calls to the OpenAI Chat Completions API.
type OpenAIService struct {
	APIKey string
}

// openAIRequest is the JSON body sent to the Chat Completions endpoint.
type openAIRequest struct {
	Model    string              `json:"model"`
	Messages []openAIMessage     `json:"messages"`
}

type openAIMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// openAIResponse is the JSON body returned by the Chat Completions endpoint.
type openAIResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
	} `json:"usage"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

// Call sends prompt to the OpenAI Chat Completions API and returns the
// response text, token counts, latency, and cost. The provided context
// should carry a deadline/timeout.
func (s *OpenAIService) Call(ctx context.Context, prompt string) (text string, inputTokens, outputTokens int, latencyMs int64, cost float64, err error) {
	payload := openAIRequest{
		Model: openAIModel,
		Messages: []openAIMessage{
			{Role: "user", Content: prompt},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("openai: marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, openAIEndpoint, bytes.NewReader(body))
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("openai: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.APIKey)

	start := time.Now()
	resp, err := http.DefaultClient.Do(req)
	latencyMs = time.Since(start).Milliseconds()
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("openai: http: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("openai: read response: %w", err)
	}

	var apiResp openAIResponse
	if err := json.Unmarshal(respBody, &apiResp); err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("openai: decode response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		msg := fmt.Sprintf("HTTP %d", resp.StatusCode)
		if apiResp.Error != nil && apiResp.Error.Message != "" {
			msg = apiResp.Error.Message
		}
		return "", 0, 0, latencyMs, 0, fmt.Errorf("openai: %s", msg)
	}

	if len(apiResp.Choices) == 0 {
		return "", 0, 0, latencyMs, 0, fmt.Errorf("openai: no choices in response")
	}

	text = apiResp.Choices[0].Message.Content
	inputTokens = apiResp.Usage.PromptTokens
	outputTokens = apiResp.Usage.CompletionTokens
	cost = calculateCost(inputTokens, outputTokens, openAIInputPricePerK, openAIOutputPricePerK)

	return text, inputTokens, outputTokens, latencyMs, cost, nil
}

// calculateCost computes the monetary cost from token counts and per-1K pricing.
func calculateCost(inputTokens, outputTokens int, inputPricePerK, outputPricePerK float64) float64 {
	return (float64(inputTokens)/1000*inputPricePerK) + (float64(outputTokens)/1000*outputPricePerK)
}
