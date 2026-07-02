package services

import "strings"

const (
	// ChunkSize is the maximum number of tokens (approximated as whitespace-separated
	// words) per chunk. Req 10 AC4 specifies ≤ 512 tokens.
	ChunkSize = 512
	// ChunkOverlap is the number of tokens that overlap between consecutive chunks.
	// Req 10 AC4 specifies 50-token overlap.
	ChunkOverlap = 50
)

// ChunkText splits text into overlapping segments of at most ChunkSize tokens
// with ChunkOverlap tokens of overlap between consecutive segments.
//
// Tokenisation is approximated by splitting on whitespace (one word ≈ one token).
// Returns an empty slice when text is blank.
func ChunkText(text string) []string {
	words := strings.Fields(text)
	if len(words) == 0 {
		return []string{}
	}

	chunks := []string{}
	step := ChunkSize - ChunkOverlap // advance window by (512 - 50) = 462 tokens each step

	for start := 0; start < len(words); start += step {
		end := start + ChunkSize
		if end > len(words) {
			end = len(words)
		}

		chunk := strings.Join(words[start:end], " ")
		chunks = append(chunks, chunk)

		// If we've reached the last word, stop.
		if end == len(words) {
			break
		}
	}

	return chunks
}
