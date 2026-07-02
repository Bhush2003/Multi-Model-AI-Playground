library;

/// Data models for the Prompt Templates API.
///
/// Mirrors the backend JSON contract for:
///   GET /api/v1/templates → [TemplatesResponse]

// ---------------------------------------------------------------------------
// Template models
// ---------------------------------------------------------------------------

/// A single prompt template.
///
/// ```json
/// { "id": "<uuid>", "title": "Debug this code", "body": "..." }
/// ```
class TemplateItem {
  const TemplateItem({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;

  factory TemplateItem.fromJson(Map<String, dynamic> json) {
    return TemplateItem(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
    );
  }
}

/// A named category containing one or more [TemplateItem]s.
///
/// ```json
/// { "category": "Coding", "templates": [...] }
/// ```
class TemplateCategory {
  const TemplateCategory({
    required this.category,
    required this.templates,
  });

  final String category;
  final List<TemplateItem> templates;

  factory TemplateCategory.fromJson(Map<String, dynamic> json) {
    final rawTemplates = json['templates'] as List<dynamic>? ?? [];
    return TemplateCategory(
      category: json['category'] as String,
      templates: rawTemplates
          .cast<Map<String, dynamic>>()
          .map(TemplateItem.fromJson)
          .toList(),
    );
  }
}

/// Top-level response from `GET /api/v1/templates`.
///
/// ```json
/// { "categories": [ { "category": "Coding", "templates": [...] } ] }
/// ```
class TemplatesResponse {
  const TemplatesResponse({required this.categories});

  final List<TemplateCategory> categories;

  factory TemplatesResponse.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'] as List<dynamic>? ?? [];
    return TemplatesResponse(
      categories: rawCategories
          .cast<Map<String, dynamic>>()
          .map(TemplateCategory.fromJson)
          .toList(),
    );
  }
}
