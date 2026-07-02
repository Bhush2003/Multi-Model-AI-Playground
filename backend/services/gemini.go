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
	geminiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent"
	geminiModel    = "gemini-1.5-pro"

	// Per-1K-token pricing for gemini-1.5-pro (USD).
	geminiInputPricePerK  = 0.00125
	geminiOutputPricePerK = 0.005
)

// GeminiService handles calls to the Google Gemini GenerateContent API.
type GeminiService struct {
	APIKey string
}

// geminiRequest is the JSON body sent to the GenerateContent endpoint.
type geminiRequest struct {
	Contents []geminiContent `json:"contents"`
}

type geminiContent struct {
	Parts []geminiPart `json:"parts"`
}

type geminiPart struct {
	Text string `json:"text"`
}

// geminiResponse is the JSON body returned by the GenerateContent endpoint.
type geminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
	UsageMetadata struct {
		PromptTokenCount     int `json:"promptTokenCount"`
		CandidatesTokenCount int `json:"candidatesTokenCount"`
	} `json:"usageMetadata"`
	Error *struct {
		Message string `json:"message"`
		Code    int    `json:"code"`
	} `json:"error,omitempty"`
}

// Call sends prompt to the Gemini GenerateContent API and returns the response
// text, token counts, latency, and cost. The provided context should carry a
// deadline/timeout.
func (s *GeminiService) Call(ctx context.Context, prompt string) (text string, inputTokens, outputTokens int, latencyMs int64, cost float64, err error) {
	payload := geminiRequest{
		Contents: []geminiContent{
			{Parts: []geminiPart{{Text: prompt}}},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("gemini: marshal request: %w", err)
	}

	url := geminiEndpoint + "?key=" + s.APIKey
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("gemini: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	start := time.Now()
	resp, err := http.DefaultClient.Do(req)
	latencyMs = time.Since(start).Milliseconds()
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("gemini: http: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("gemini: read response: %w", err)
	}

	var apiResp geminiResponse
	if err := json.Unmarshal(respBody, &apiResp); err != nil {
		return "", 0, 0, 0, 0, fmt.Errorf("gemini: decode response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		msg := fmt.Sprintf("HTTP %d", resp.StatusCode)
		if apiResp.Error != nil && apiResp.Error.Message != "" {
			msg = apiResp.Error.Message
		}
		return "", 0, 0, latencyMs, 0, fmt.Errorf("gemini: %s", msg)
	}

	if len(apiResp.Candidates) == 0 || len(apiResp.Candidates[0].Content.Parts) == 0 {
		return "", 0, 0, latencyMs, 0, fmt.Errorf("gemini: no candidates in response")
	}

	text = apiResp.Candidates[0].Content.Parts[0].Text
	inputTokens = apiResp.UsageMetadata.PromptTokenCount
	outputTokens = apiResp.UsageMetadata.CandidatesTokenCount
	cost = calculateCost(inputTokens, outputTokens, geminiInputPricePerK, geminiOutputPricePerK)

	return text, inputTokens, outputTokens, latencyMs, cost, nil
}
