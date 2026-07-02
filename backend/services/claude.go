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
	claudeEndpoint = "https://api.anthropic.com/v1/messages"
	claudeModel    = "claude-3-5-sonnet-20241022"
	claudeVersion  = "2023-06-01"
	claudeMaxTokens = 4096

	// Per-1K-token pricing for claude-3-5-sonnet (USD).
	claudeInputPricePerK  = 0.003
	claudeOutputPricePerK = 0.015
)

// ClaudeService handles calls to the Anthropic Messages API.
type ClaudeService struct {
	APIKey string
}

// claudeRequest is the JSON body sent to the Messages endpoint.
type claudeRequest struct {
	Model     string          `json:"model"`
	MaxTokens int             `json:"max_tokens"`
	Messages  []claudeMessage `json:"messages"`
}

type claudeMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// claudeResponse is the JSON body returned by the Messages endpoint.
type claudeResponse struct {
	Content []struct {
		Text string `json:"text"`
		Type string `json:"type"`
	} `json:"content"`
	Usage struct {
		InputTokens  int `json:"input_tokens"`
		OutputTokens int `json:"output_tokens"`
	} `json:"usage"`
	Error *struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

// Call sends prompt to the Anthropic Messages API and returns the response
// text, token counts, latency, and cost. The provided context should carry a
// deadline/timeout.
func (s *ClaudeService) Call(ctx context.Context, prompt string) (text string, inputTokens, outputTokens int, latencyMs int64, cost float64, err error) {
	payload := claudeRequest{
		Model:     claudeModel,
		MaxTokens: claudeMaxTokens,
		Messages: []claudeMessage{
			{Role: "user", Content: prompt},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("claude: marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, claudeEndpoint, bytes.NewReader(body))
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("claude: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", s.APIKey)
	req.Header.Set("anthropic-version", claudeVersion)

	start := time.Now()
	resp, err := http.DefaultClient.Do(req)
	latencyMs = time.Since(start).Milliseconds()
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("claude: http: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("claude: read response: %w", err)
	}

	var apiResp claudeResponse
	if err := json.Unmarshal(respBody, &apiResp); err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("claude: decode response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		msg := fmt.Sprintf("HTTP %d", resp.StatusCode)
		if apiResp.Error != nil && apiResp.Error.Message != "" {
			msg = apiResp.Error.Message
		}
		return "", 0, 0, latencyMs, 0, fmt.Errorf("claude: %s", msg)
	}

	if len(apiResp.Content) == 0 {
		return "", 0, 0, latencyMs, 0, fmt.Errorf("claude: no content in response")
	}

	text = apiResp.Content[0].Text
	inputTokens = apiResp.Usage.InputTokens
	outputTokens = apiResp.Usage.OutputTokens
	cost = calculateCost(inputTokens, outputTokens, claudeInputPricePerK, claudeOutputPricePerK)

	return text, inputTokens, outputTokens, latencyMs, cost, nil
}
