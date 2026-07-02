package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

const (
	openAIEmbeddingURL   = "https://api.openai.com/v1/embeddings"
	embeddingModel       = "text-embedding-3-small"
	embeddingBatchSize   = 100 // max texts per API request to avoid size limits
)

// EmbeddingService generates vector embeddings via OpenAI text-embedding-3-small.
type EmbeddingService struct {
	APIKey string
}

// embeddingRequest is the JSON body sent to the OpenAI embeddings endpoint.
type embeddingRequest struct {
	Model string   `json:"model"`
	Input []string `json:"input"`
}

// embeddingData is one object inside the OpenAI embeddings response data array.
type embeddingData struct {
	Index     int       `json:"index"`
	Embedding []float64 `json:"embedding"`
}

// embeddingResponse is the full response from the OpenAI embeddings endpoint.
type embeddingResponse struct {
	Data []embeddingData `json:"data"`
}

// EmbedBatch generates embeddings for every text in texts, calling the OpenAI
// text-embedding-3-small model. Texts are batched in groups of embeddingBatchSize
// to avoid request-size limits.
//
// Returns a slice of float32 embedding vectors, one per input text, in the same
// order as the input slice.
func (s *EmbeddingService) EmbedBatch(ctx context.Context, texts []string) ([][]float32, error) {
	if len(texts) == 0 {
		return [][]float32{}, nil
	}

	results := make([][]float32, len(texts))

	for start := 0; start < len(texts); start += embeddingBatchSize {
		end := start + embeddingBatchSize
		if end > len(texts) {
			end = len(texts)
		}

		batch := texts[start:end]
		batchEmbeddings, err := s.embedBatch(ctx, batch)
		if err != nil {
			return nil, fmt.Errorf("embedding batch [%d:%d]: %w", start, end, err)
		}

		for i, emb := range batchEmbeddings {
			results[start+i] = emb
		}
	}

	return results, nil
}

// embedBatch sends a single batch request to the OpenAI embeddings API and
// returns the embeddings as []float32 slices.
func (s *EmbeddingService) embedBatch(ctx context.Context, texts []string) ([][]float32, error) {
	reqBody := embeddingRequest{
		Model: embeddingModel,
		Input: texts,
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, openAIEmbeddingURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+s.APIKey)

	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("http request: %w", err)
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("openai embeddings returned status %d: %s", resp.StatusCode, string(respBytes))
	}

	var embResp embeddingResponse
	if err := json.Unmarshal(respBytes, &embResp); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w", err)
	}

	// Build result slice in index order (API may not return items sorted).
	embeddings := make([][]float32, len(texts))
	for _, d := range embResp.Data {
		if d.Index < 0 || d.Index >= len(texts) {
			return nil, fmt.Errorf("embedding index %d out of range (batch size %d)", d.Index, len(texts))
		}
		f32 := make([]float32, len(d.Embedding))
		for i, v := range d.Embedding {
			f32[i] = float32(v)
		}
		embeddings[d.Index] = f32
	}

	return embeddings, nil
}
