package handlers

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"log"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	ledongpdf "github.com/ledongthuc/pdf"
	"github.com/yourusername/ai-playground/config"
	"github.com/yourusername/ai-playground/services"
)

const maxUploadBytes = 20 * 1024 * 1024 // 20 MB

// RAGHandler holds dependencies for the RAG pipeline routes.
type RAGHandler struct {
	DB  *pgxpool.Pool
	Cfg *config.Config
}

// NewRAGHandler constructs a RAGHandler with the provided pool and config.
func NewRAGHandler(db *pgxpool.Pool, cfg *config.Config) *RAGHandler {
	return &RAGHandler{DB: db, Cfg: cfg}
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/documents — upload a PDF or DOCX for RAG processing
// ─────────────────────────────────────────────────────────────────────────────

// UploadDocument handles POST /api/v1/documents.
//
// Req 10 AC2: validate MIME type (PDF/DOCX) and file size ≤ 20 MB; return 422 on violation.
// Req 10 AC4: chunk text into ≤512-token segments with 50-token overlap.
// Req 10 AC5: embed chunks via text-embedding-3-small; store in ChromaDB keyed by doc ID.
// Req 10 AC6: set document status to "ready" after successful processing; "error" on failure.
func (h *RAGHandler) UploadDocument(c *gin.Context) {
	userIDStr, ok := extractUserID(c)
	if !ok {
		return
	}

	// Parse multipart form with a 20 MB memory + disk limit.
	// MaxMultipartMemory is set on the Gin engine; here we enforce it via the
	// FormFile call which respects the engine limit, and then re-check size.
	if err := c.Request.ParseMultipartForm(maxUploadBytes); err != nil {
		c.JSON(http.StatusUnprocessableEntity, gin.H{"error": "file exceeds 20 MB limit"})
		return
	}

	fileHeader, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "multipart field 'file' is required"})
		return
	}

	// ── Size validation ──────────────────────────────────────────────────────
	if fileHeader.Size > maxUploadBytes {
		c.JSON(http.StatusUnprocessableEntity, gin.H{"error": "file exceeds 20 MB limit"})
		return
	}

	// ── MIME / extension validation ──────────────────────────────────────────
	ext := strings.ToLower(filepath.Ext(fileHeader.Filename))
	contentType := fileHeader.Header.Get("Content-Type")
	if !isAllowedFileType(ext, contentType) {
		c.JSON(http.StatusUnprocessableEntity, gin.H{"error": "unsupported file type; accepted: pdf, docx"})
		return
	}

	// Read file bytes once so we can pass them to the extractor.
	f, err := fileHeader.Open()
	if err != nil {
		log.Printf("rag upload: open file: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read uploaded file"})
		return
	}
	fileBytes, err := io.ReadAll(f)
	f.Close()
	if err != nil {
		log.Printf("rag upload: read file bytes: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read uploaded file"})
		return
	}

	// ── Insert document record with status="processing" ──────────────────────
	const insertSQL = `
		INSERT INTO documents (user_id, filename, file_size, status)
		VALUES ($1, $2, $3, 'processing')
		RETURNING id`

	var docID string
	err = h.DB.QueryRow(context.Background(), insertSQL,
		userIDStr, fileHeader.Filename, fileHeader.Size,
	).Scan(&docID)
	if err != nil {
		log.Printf("rag upload: insert document: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create document record"})
		return
	}

	// ── Launch async processing ───────────────────────────────────────────────
	go h.processDocument(docID, ext, fileBytes)

	c.JSON(http.StatusCreated, gin.H{
		"id":       docID,
		"filename": fileHeader.Filename,
		"status":   "processing",
	})
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/documents — list the authenticated user's documents
// ─────────────────────────────────────────────────────────────────────────────

// ListDocuments handles GET /api/v1/documents.
//
// Returns all documents belonging to the authenticated user, ordered by
// created_at DESC.
func (h *RAGHandler) ListDocuments(c *gin.Context) {
	userIDStr, ok := extractUserID(c)
	if !ok {
		return
	}

	const listSQL = `
		SELECT id, filename, status, created_at
		FROM documents
		WHERE user_id = $1
		ORDER BY created_at DESC`

	rows, err := h.DB.Query(context.Background(), listSQL, userIDStr)
	if err != nil {
		log.Printf("rag list documents: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list documents"})
		return
	}
	defer rows.Close()

	type docItem struct {
		ID        string `json:"id"`
		Filename  string `json:"filename"`
		Status    string `json:"status"`
		CreatedAt string `json:"created_at"`
	}

	docs := make([]docItem, 0)
	for rows.Next() {
		var d docItem
		if err := rows.Scan(&d.ID, &d.Filename, &d.Status, &d.CreatedAt); err != nil {
			log.Printf("rag list documents: scan row: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list documents"})
			return
		}
		docs = append(docs, d)
	}
	if err := rows.Err(); err != nil {
		log.Printf("rag list documents: rows error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list documents"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"documents": docs})
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/prompts/rag — RAG Mode Query (Task 15)
// ─────────────────────────────────────────────────────────────────────────────

// ragPromptRequest is the expected body for POST /api/v1/prompts/rag.
type ragPromptRequest struct {
	Prompt     string   `json:"prompt"`
	DocumentID string   `json:"document_id"`
	Models     []string `json:"models"`
}

// RAGPrompt handles POST /api/v1/prompts/rag.
//
// Req 11 AC2: query Vector_DB for top-5 most semantically similar chunks.
// Req 11 AC3: prepend chunk text as context to the prompt before dispatching.
// Req 11 AC5: if no chunk has cosine similarity > 0.5, dispatch without context
//
//	and include no_context_found: true in the response.
func (h *RAGHandler) RAGPrompt(c *gin.Context) {
	// 1. Extract user_id from JWT.
	userIDStr, ok := extractUserID(c)
	if !ok {
		return
	}

	// 2. Bind JSON body.
	var req ragPromptRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 3. Validate: prompt not empty, document_id not empty, models not empty.
	if strings.TrimSpace(req.Prompt) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "prompt must not be empty"})
		return
	}
	if strings.TrimSpace(req.DocumentID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "document_id must not be empty"})
		return
	}
	if len(req.Models) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "at least one model must be selected"})
		return
	}

	ctx := context.Background()

	// 4. Verify document exists, belongs to this user, and is ready.
	const docSQL = `
		SELECT status FROM documents
		WHERE id = $1 AND user_id = $2`

	var docStatus string
	err := h.DB.QueryRow(ctx, docSQL, req.DocumentID, userIDStr).Scan(&docStatus)
	if err != nil {
		// pgx returns pgx.ErrNoRows when no row found — treat as 404.
		c.JSON(http.StatusNotFound, gin.H{"error": "document not found"})
		return
	}
	if docStatus != "ready" {
		c.JSON(http.StatusConflict, gin.H{"error": "document is not ready for querying (status: " + docStatus + ")"})
		return
	}

	// 5. Embed the user prompt.
	embSvc := &services.EmbeddingService{APIKey: h.Cfg.OpenAIAPIKey}
	embeddings, err := embSvc.EmbedBatch(ctx, []string{req.Prompt})
	if err != nil {
		log.Printf("rag prompt: embed prompt: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to embed prompt"})
		return
	}
	promptEmbedding := embeddings[0]

	// 6. Query ChromaDB for top-5 similar chunks (Req 11 AC2).
	chromaSvc := &services.ChromaDBService{BaseURL: h.Cfg.ChromaURL}
	chunks, distances, err := chromaSvc.QuerySimilar(ctx, req.DocumentID, promptEmbedding, 5)
	if err != nil {
		log.Printf("rag prompt: query chromadb: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to query vector database"})
		return
	}

	// 7. Check if max similarity > 0.5.
	// ChromaDB returns cosine distance (0 = identical, 2 = opposite).
	// Cosine similarity = 1 - distance; similarity > 0.5 ⟺ distance < 0.5.
	noContextFound := true
	for _, dist := range distances {
		if dist < 0.5 {
			noContextFound = false
			break
		}
	}

	// 8. Build the prompt to dispatch.
	var dispatchPrompt string
	if !noContextFound {
		// 8a. Prepend retrieved chunk texts as context block (Req 11 AC3).
		var sb strings.Builder
		sb.WriteString("The following context was retrieved from the document. Use it to answer the question:\n\n")
		for _, chunk := range chunks {
			sb.WriteString("---\n")
			sb.WriteString(chunk)
			sb.WriteString("\n")
		}
		sb.WriteString("---\n\nUser question: ")
		sb.WriteString(req.Prompt)
		dispatchPrompt = sb.String()
	} else {
		// 8b. No relevant context — dispatch user prompt as-is (Req 11 AC5).
		dispatchPrompt = req.Prompt
	}

	// 9. INSERT into prompts with rag_doc_id = document_id.
	const insertPromptSQL = `
		INSERT INTO prompts (user_id, prompt, rag_doc_id)
		VALUES ($1, $2, $3)
		RETURNING id`

	var promptID string
	if err := h.DB.QueryRow(ctx, insertPromptSQL, userIDStr, req.Prompt, req.DocumentID).Scan(&promptID); err != nil {
		log.Printf("rag prompt: insert prompt: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist prompt"})
		return
	}

	// 10. Fan-out to selected models with the (possibly augmented) prompt.
	results := services.FanOut(ctx, dispatchPrompt, req.Models, h.Cfg)

	// 11. INSERT each response into responses table.
	const insertResponseSQL = `
		INSERT INTO responses (prompt_id, model_name, response, latency_ms, token_count, cost, error)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`

	jsonResults := make([]modelResultJSON, 0, len(results))

	for _, r := range results {
		var (
			responseText *string
			latencyMs    *int64
			tokenCount   *int
			cost         *float64
			errText      *string
		)

		if r.Err != nil {
			msg := r.Err.Error()
			errText = &msg
		} else {
			responseText = &r.Response
			latencyMs = &r.LatencyMs
			tokenCount = &r.TokenCount
			cost = &r.Cost
		}

		if _, dbErr := h.DB.Exec(ctx, insertResponseSQL,
			promptID,
			r.ModelName,
			responseText,
			latencyMs,
			tokenCount,
			cost,
			errText,
		); dbErr != nil {
			log.Printf("rag prompt: persist response for model %s: %v", r.ModelName, dbErr)
		}

		jsonResults = append(jsonResults, modelResultJSON{
			Model:      r.ModelName,
			Response:   responseText,
			LatencyMs:  latencyMs,
			TokenCount: tokenCount,
			Cost:       cost,
			Error:      errText,
		})
	}

	// 12. Return { prompt_id, no_context_found, results }.
	c.JSON(http.StatusOK, gin.H{
		"prompt_id":        promptID,
		"no_context_found": noContextFound,
		"results":          jsonResults,
	})
}

// ─────────────────────────────────────────────────────────────────────────────
// Async processing pipeline
// ─────────────────────────────────────────────────────────────────────────────

// processDocument runs the RAG pipeline in a goroutine:
// extract → chunk → embed → store in ChromaDB → update status.
//
// Req 10 AC4, AC5, AC6.
func (h *RAGHandler) processDocument(docID, ext string, fileBytes []byte) {
	ctx := context.Background()

	updateStatus := func(status string) {
		const updateSQL = `UPDATE documents SET status = $1 WHERE id = $2`
		if _, err := h.DB.Exec(ctx, updateSQL, status, docID); err != nil {
			log.Printf("rag process: update status %s for doc %s: %v", status, docID, err)
		}
	}

	// ── 1. Extract text ───────────────────────────────────────────────────────
	var text string
	var err error
	switch ext {
	case ".pdf":
		text, err = extractPDFText(fileBytes)
	case ".docx":
		text, err = extractDOCXText(fileBytes)
	default:
		log.Printf("rag process: unsupported extension %q for doc %s", ext, docID)
		updateStatus("error")
		return
	}
	if err != nil {
		log.Printf("rag process: extract text for doc %s: %v", docID, err)
		updateStatus("error")
		return
	}

	if strings.TrimSpace(text) == "" {
		log.Printf("rag process: extracted empty text for doc %s", docID)
		updateStatus("error")
		return
	}

	// ── 2. Chunk text ─────────────────────────────────────────────────────────
	chunks := services.ChunkText(text)
	if len(chunks) == 0 {
		log.Printf("rag process: no chunks produced for doc %s", docID)
		updateStatus("error")
		return
	}

	// ── 3. Embed chunks ───────────────────────────────────────────────────────
	embSvc := &services.EmbeddingService{APIKey: h.Cfg.OpenAIAPIKey}
	embeddings, err := embSvc.EmbedBatch(ctx, chunks)
	if err != nil {
		log.Printf("rag process: embed chunks for doc %s: %v", docID, err)
		updateStatus("error")
		return
	}

	// ── 4. Store in ChromaDB ──────────────────────────────────────────────────
	chromaSvc := &services.ChromaDBService{BaseURL: h.Cfg.ChromaURL}
	if err := chromaSvc.UpsertChunks(ctx, docID, chunks, embeddings); err != nil {
		log.Printf("rag process: store in chromadb for doc %s: %v", docID, err)
		updateStatus("error")
		return
	}

	// ── 5. Mark ready ─────────────────────────────────────────────────────────
	updateStatus("ready")
	log.Printf("rag process: doc %s processed successfully (%d chunks)", docID, len(chunks))
}

// ─────────────────────────────────────────────────────────────────────────────
// Text extraction helpers
// ─────────────────────────────────────────────────────────────────────────────

// extractPDFText reads raw bytes of a PDF file and returns all page text
// concatenated, using the github.com/ledongthuc/pdf library.
func extractPDFText(data []byte) (string, error) {
	r := bytes.NewReader(data)
	pdfReader, err := ledongpdf.NewReader(r, int64(len(data)))
	if err != nil {
		return "", fmt.Errorf("open pdf: %w", err)
	}

	var sb strings.Builder
	for i := 1; i <= pdfReader.NumPage(); i++ {
		page := pdfReader.Page(i)
		if page.V.IsNull() {
			continue
		}
		pageText, err := page.GetPlainText(nil)
		if err != nil {
			// Non-fatal: skip unreadable pages rather than aborting.
			log.Printf("extractPDFText: page %d: %v", i, err)
			continue
		}
		sb.WriteString(pageText)
		sb.WriteByte('\n')
	}

	return sb.String(), nil
}

// wordBody is a minimal struct used to walk the DOCX XML document body.
type wordBody struct {
	Paragraphs []wordParagraph `xml:"body>p"`
}

// wordParagraph represents a single paragraph in the DOCX XML.
type wordParagraph struct {
	Runs []wordRun `xml:"r"`
}

// wordRun represents a text run inside a paragraph.
type wordRun struct {
	Text string `xml:"t"`
}

// extractDOCXText reads a DOCX file (a ZIP archive containing word/document.xml)
// and returns plain text by stripping XML tags from the document body.
func extractDOCXText(data []byte) (string, error) {
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return "", fmt.Errorf("open docx zip: %w", err)
	}

	// Locate word/document.xml inside the ZIP.
	var docXMLFile *zip.File
	for _, f := range zr.File {
		if f.Name == "word/document.xml" {
			docXMLFile = f
			break
		}
	}
	if docXMLFile == nil {
		return "", fmt.Errorf("word/document.xml not found in docx archive")
	}

	rc, err := docXMLFile.Open()
	if err != nil {
		return "", fmt.Errorf("open word/document.xml: %w", err)
	}
	defer rc.Close()

	xmlBytes, err := io.ReadAll(rc)
	if err != nil {
		return "", fmt.Errorf("read word/document.xml: %w", err)
	}

	// Decode the XML, extracting text from w:t elements within w:p paragraphs.
	// We use a streaming decoder to handle arbitrarily large documents.
	var sb strings.Builder
	decoder := xml.NewDecoder(bytes.NewReader(xmlBytes))
	inParagraph := false
	inRun := false
	inText := false

	for {
		token, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", fmt.Errorf("xml decode: %w", err)
		}

		switch t := token.(type) {
		case xml.StartElement:
			localName := t.Name.Local
			switch localName {
			case "p":
				inParagraph = true
			case "r":
				if inParagraph {
					inRun = true
				}
			case "t":
				if inRun {
					inText = true
				}
			}
		case xml.EndElement:
			localName := t.Name.Local
			switch localName {
			case "p":
				if inParagraph {
					sb.WriteByte('\n')
				}
				inParagraph = false
				inRun = false
				inText = false
			case "r":
				inRun = false
				inText = false
			case "t":
				inText = false
			}
		case xml.CharData:
			if inText {
				sb.WriteString(string(t))
			}
		}
	}

	return sb.String(), nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Validation helper
// ─────────────────────────────────────────────────────────────────────────────

// isAllowedFileType returns true when the file extension or Content-Type header
// indicates a PDF or DOCX document.
func isAllowedFileType(ext, contentType string) bool {
	switch ext {
	case ".pdf":
		return true
	case ".docx":
		return true
	}
	// Fall back to Content-Type check.
	ct := strings.ToLower(contentType)
	if strings.Contains(ct, "application/pdf") {
		return true
	}
	if strings.Contains(ct, "application/vnd.openxmlformats-officedocument.wordprocessingml.document") {
		return true
	}
	return false
}
