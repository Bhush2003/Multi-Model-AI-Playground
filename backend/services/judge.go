package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// JudgeModelScore holds the AI Judge's evaluation of a single model.
type JudgeModelScore struct {
	Model     string `json:"model"`
	Score     int    `json:"score"`
	Reasoning string `json:"reasoning"`
}

// JudgeResult is the parsed output from GPT-4o's evaluation.
type JudgeResult struct {
	Winner       string            `json:"winner"`
	RankedModels []JudgeModelScore `json:"ranked_models"`
}

// JudgeService submits all model responses to GPT-4o for evaluation.
type JudgeService struct {
	APIKey string
}

// systemPrompt is the rubric injected into the AI Judge's system message.
const systemPrompt = `You are an expert AI evaluator. Score each response with this rubric:
- Factual accuracy: 40 pts (correctness of claims)
- Depth of explanation: 35 pts (completeness, examples)
- Clarity: 25 pts (structure, readability)
Return ONLY a JSON object:
{"winner":"<model>","ranked_models":[{"model":"<name>","score":<0-100>,"reasoning":"<text>"}]}
Sort ranked_models by score descending. winner = top-scored model.`

// openAIChatRequest is the request body for the OpenAI chat completions API.
type openAIChatRequest struct {
	Model          string              `json:"model"`
	ResponseFormat openAIResponseFmt   `json:"response_format"`
	Messages       []openAIChatMessage `json:"messages"`
}

type openAIResponseFmt struct {
	Type string `json:"type"`
}

type openAIChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// openAIChatResponse is the minimal subset of the OpenAI API response we need.
type openAIChatResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

// Evaluate calls GPT-4o in JSON mode with the evaluation rubric and returns
// ranked model scores.
//
// Req 12 AC2: submit all model responses for a prompt to the GPT-based
//
//	AI_Judge with a rubric covering factual accuracy, depth, and quality.
//
// Req 12 AC3: parse the output into a structured result with ranked models,
//
//	a score per model (1–100), and text reasoning per model.
func (s *JudgeService) Evaluate(ctx context.Context, userPrompt string, responses map[string]string) (*JudgeResult, error) {
	// Build the user message from the prompt and all model responses.
	var sb strings.Builder
	sb.WriteString("User prompt: ")
	sb.WriteString(userPrompt)
	sb.WriteString("\n\nModel responses:\n")
	for model, resp := range responses {
		sb.WriteString(model)
		sb.WriteString(": ")
		sb.WriteString(resp)
		sb.WriteString("\n\n")
	}

	reqBody := openAIChatRequest{
		Model: "gpt-4o",
		ResponseFormat: openAIResponseFmt{
			Type: "json_object",
		},
		Messages: []openAIChatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: sb.String()},
		},
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("judge: marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.openai.com/v1/chat/completions",
		bytes.NewReader(bodyBytes),
	)
	if err != nil {
		return nil, fmt.Errorf("judge: build http request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+s.APIKey)

	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("judge: http call: %w", err)
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("judge: read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("judge: openai returned status %d: %s", resp.StatusCode, respBytes)
	}

	var chatResp openAIChatResponse
	if err := json.Unmarshal(respBytes, &chatResp); err != nil {
		return nil, fmt.Errorf("judge: unmarshal chat response: %w", err)
	}

	if len(chatResp.Choices) == 0 {
		return nil, fmt.Errorf("judge: no choices in response")
	}

	content := chatResp.Choices[0].Message.Content
	var result JudgeResult
	if err := json.Unmarshal([]byte(content), &result); err != nil {
		return nil, fmt.Errorf("judge: unmarshal judge result: %w", err)
	}

	return &result, nil
}
