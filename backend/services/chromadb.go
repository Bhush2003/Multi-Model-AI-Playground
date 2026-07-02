package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// ChromaDBService stores and queries chunk embeddings in ChromaDB.
type ChromaDBService struct {
	BaseURL string
}

// ─────────────────────────────────────────────────────────────────────────────
// ChromaDB REST API types
// ─────────────────────────────────────────────────────────────────────────────

type chromaCreateCollectionRequest struct {
	Name string `json:"name"`
}

type chromaCreateCollectionResponse struct {
	ID string `json:"id"`
}

type chromaAddRequest struct {
	IDs        []string      `json:"ids"`
	Embeddings [][]float32   `json:"embeddings"`
	Documents  []string      `json:"documents"`
}

type chromaQueryRequest struct {
	QueryEmbeddings [][]float32 `json:"query_embeddings"`
	NResults        int         `json:"n_results"`
	Include         []string    `json:"include"`
}

type chromaQueryResponse struct {
	Documents [][]string    `json:"documents"`
	Distances [][]float64   `json:"distances"`
}

// ─────────────────────────────────────────────────────────────────────────────
// UpsertChunks
// ─────────────────────────────────────────────────────────────────────────────

// UpsertChunks creates (or gets) a ChromaDB collection named collectionID and
// upserts all chunk texts and their embeddings into it.
//
// Each chunk is stored with an ID of the form "<collectionID>_<index>".
func (s *ChromaDBService) UpsertChunks(ctx context.Context, collectionID string, chunks []string, embeddings [][]float32) error {
	if len(chunks) == 0 {
		return nil
	}

	// Get or create the collection; capture its internal ChromaDB UUID.
	chromaCollectionID, err := s.getOrCreateCollection(ctx, collectionID)
	if err != nil {
		return fmt.Errorf("getOrCreateCollection %q: %w", collectionID, err)
	}

	// Build IDs for each chunk: "<collectionID>_0", "_1", ...
	ids := make([]string, len(chunks))
	for i := range chunks {
		ids[i] = fmt.Sprintf("%s_%d", collectionID, i)
	}

	addReq := chromaAddRequest{
		IDs:        ids,
		Embeddings: embeddings,
		Documents:  chunks,
	}
	addBody, err := json.Marshal(addReq)
	if err != nil {
		return fmt.Errorf("marshal add request: %w", err)
	}

	url := fmt.Sprintf("%s/api/v1/collections/%s/add", s.BaseURL, chromaCollectionID)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(addBody))
	if err != nil {
		return fmt.Errorf("create add request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		return fmt.Errorf("http add: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("chromadb add returned status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

// ─────────────────────────────────────────────────────────────────────────────
// QuerySimilar
// ─────────────────────────────────────────────────────────────────────────────

// QuerySimilar retrieves the topK most semantically similar chunks from the
// ChromaDB collection identified by collectionID.
//
// Returns the matched document texts, their cosine distances, and any error.
func (s *ChromaDBService) QuerySimilar(ctx context.Context, collectionID string, queryEmbedding []float32, topK int) ([]string, []float64, error) {
	// Resolve the collection's internal ChromaDB UUID.
	chromaCollectionID, err := s.getOrCreateCollection(ctx, collectionID)
	if err != nil {
		return nil, nil, fmt.Errorf("getOrCreateCollection %q: %w", collectionID, err)
	}

	queryReq := chromaQueryRequest{
		QueryEmbeddings: [][]float32{queryEmbedding},
		NResults:        topK,
		Include:         []string{"documents", "distances"},
	}
	queryBody, err := json.Marshal(queryReq)
	if err != nil {
		return nil, nil, fmt.Errorf("marshal query request: %w", err)
	}

	url := fmt.Sprintf("%s/api/v1/collections/%s/query", s.BaseURL, chromaCollectionID)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(queryBody))
	if err != nil {
		return nil, nil, fmt.Errorf("create query request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		return nil, nil, fmt.Errorf("http query: %w", err)
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, fmt.Errorf("read query response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, nil, fmt.Errorf("chromadb query returned status %d: %s", resp.StatusCode, string(respBytes))
	}

	var queryResp chromaQueryResponse
	if err := json.Unmarshal(respBytes, &queryResp); err != nil {
		return nil, nil, fmt.Errorf("unmarshal query response: %w", err)
	}

	if len(queryResp.Documents) == 0 {
		return []string{}, []float64{}, nil
	}

	return queryResp.Documents[0], queryResp.Distances[0], nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

// getOrCreateCollection ensures a ChromaDB collection named name exists and
// returns its internal UUID.
func (s *ChromaDBService) getOrCreateCollection(ctx context.Context, name string) (string, error) {
	createReq := chromaCreateCollectionRequest{Name: name}
	body, err := json.Marshal(createReq)
	if err != nil {
		return "", fmt.Errorf("marshal create collection: %w", err)
	}

	url := s.BaseURL + "/api/v1/collections"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("create collection request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		return "", fmt.Errorf("http create collection: %w", err)
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read create collection response: %w", err)
	}

	// 200 = collection already existed and was returned; 201 = newly created.
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return "", fmt.Errorf("chromadb create collection returned status %d: %s", resp.StatusCode, string(respBytes))
	}

	var createResp chromaCreateCollectionResponse
	if err := json.Unmarshal(respBytes, &createResp); err != nil {
		return "", fmt.Errorf("unmarshal create collection response: %w", err)
	}

	return createResp.ID, nil
}
