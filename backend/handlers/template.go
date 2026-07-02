package handlers

import (
	"context"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// TemplateHandler holds dependencies for the prompt template routes.
type TemplateHandler struct {
	DB *pgxpool.Pool
}

// NewTemplateHandler constructs a TemplateHandler.
func NewTemplateHandler(db *pgxpool.Pool) *TemplateHandler {
	return &TemplateHandler{DB: db}
}

// ────────────────────────────────────────────────────────────────────────────
// Response types
// ────────────────────────────────────────────────────────────────────────────

// templateItem represents a single prompt template.
type templateItem struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Body  string `json:"body"`
}

// templateCategory groups templates under a single category name.
type templateCategory struct {
	Category  string         `json:"category"`
	Templates []templateItem `json:"templates"`
}

// templatesResponse is the envelope for GET /api/v1/templates.
type templatesResponse struct {
	Categories []templateCategory `json:"categories"`
}

// ────────────────────────────────────────────────────────────────────────────
// GET /api/v1/templates
// ────────────────────────────────────────────────────────────────────────────

// GetTemplates handles GET /api/v1/templates.
//
// Returns all prompt templates from the database, grouped by category.
// Categories are ordered alphabetically; templates within each category are
// ordered by title ASC.
//
// Req 8 AC1.
func (h *TemplateHandler) GetTemplates(c *gin.Context) {
	ctx := context.Background()

	// Fetch all templates ordered so we can build the grouped structure in a
	// single pass: primary sort by category ASC, secondary by title ASC.
	const sql = `
		SELECT id, category, title, body
		FROM templates
		ORDER BY category ASC, title ASC`

	rows, err := h.DB.Query(ctx, sql)
	if err != nil {
		log.Printf("templates: query: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve templates"})
		return
	}
	defer rows.Close()

	// Build the grouped structure in a single pass.
	// We track insertion order via a slice of categories and a map for O(1) lookup.
	categoryOrder := make([]string, 0)
	categoryMap := make(map[string]*templateCategory)

	for rows.Next() {
		var (
			id       string
			category string
			title    string
			body     string
		)
		if err := rows.Scan(&id, &category, &title, &body); err != nil {
			log.Printf("templates: scan row: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve templates"})
			return
		}

		if _, exists := categoryMap[category]; !exists {
			categoryOrder = append(categoryOrder, category)
			categoryMap[category] = &templateCategory{
				Category:  category,
				Templates: make([]templateItem, 0),
			}
		}

		categoryMap[category].Templates = append(categoryMap[category].Templates, templateItem{
			ID:    id,
			Title: title,
			Body:  body,
		})
	}
	if err := rows.Err(); err != nil {
		log.Printf("templates: rows iteration error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retrieve templates"})
		return
	}

	// Assemble the final ordered slice.
	categories := make([]templateCategory, 0, len(categoryOrder))
	for _, cat := range categoryOrder {
		categories = append(categories, *categoryMap[cat])
	}

	c.JSON(http.StatusOK, templatesResponse{Categories: categories})
}
