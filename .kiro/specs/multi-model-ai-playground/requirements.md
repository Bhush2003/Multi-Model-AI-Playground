# Requirements Document

## Introduction

The Multi-Model AI Playground is a unified LLM comparison and evaluation platform that allows users to submit a single prompt to multiple AI models (GPT, Gemini, Claude) simultaneously and compare responses side-by-side. The platform is built in four phases: an MVP focused on core comparison functionality, followed by cost analytics and prompt templates, then RAG (Retrieval-Augmented Generation) support, and finally an AI Judge evaluation layer. The system uses a Flutter frontend communicating with a Go/Gin API gateway that fans out requests to each AI provider and persists results in PostgreSQL.

## Glossary

- **Playground**: The primary UI screen where users submit prompts and view multi-model responses side-by-side
- **API_Gateway**: The Go/Gin backend service that receives requests from the Flutter frontend and fans them out to AI provider APIs
- **Model**: One of the supported LLM providers — OpenAI (GPT), Google (Gemini), or Anthropic (Claude)
- **Prompt**: A user-submitted text input sent simultaneously to all selected models
- **Response**: The text output returned by a Model for a given Prompt, stored with latency and token metadata
- **Prompt_History**: The persisted list of a user's previously submitted prompts and their associated responses
- **Cost_Analytics_Dashboard**: The UI screen that displays aggregated token usage, request counts, and estimated costs per model
- **Prompt_Template**: A pre-defined prompt skeleton categorized by use case (Coding, Interview Preparation, Content Writing, Summarization)
- **Rating**: A user-submitted evaluation of a Response across three dimensions: Accuracy, Clarity, and Helpfulness
- **RAG_Pipeline**: The Retrieval-Augmented Generation subsystem that chunks uploaded documents, generates embeddings, stores them in a vector database, and retrieves relevant context at query time
- **Document**: A user-uploaded PDF or DOCX file ingested by the RAG_Pipeline
- **Chunk**: A fixed-size text segment produced by splitting a Document for embedding
- **Embedding**: A vector representation of a Chunk produced by an embedding model
- **Vector_DB**: The ChromaDB instance that stores and retrieves Embeddings by semantic similarity
- **AI_Judge**: The GPT-based evaluator that scores and ranks all model Responses for a given Prompt and provides reasoning
- **Latency_ms**: The elapsed time in milliseconds from when the API_Gateway dispatches a request to a Model until the full response is received
- **Token_Count**: The number of tokens consumed by a Model for a single request/response pair
- **Cost**: The estimated monetary cost of a request calculated from Token_Count and the model's published per-token pricing

---

## Requirements

---

### Requirement 1: User Authentication

**User Story:** As a user, I want to create an account and log in, so that my prompt history and settings are saved and private to me.

#### Acceptance Criteria

1. WHEN a new user submits a valid name, email address, and password, THE API_Gateway SHALL create a user record in the `users` table and return a session token.
2. WHEN an existing user submits a valid email and password, THE API_Gateway SHALL authenticate the user and return a session token.
3. IF a login attempt is made with an unrecognised email or incorrect password, THEN THE API_Gateway SHALL return an error response with HTTP status 401 and a message indicating invalid credentials.
4. WHILE a user holds a valid session token, THE API_Gateway SHALL accept that token to authorise subsequent requests.
5. IF a request is received without a valid session token, THEN THE API_Gateway SHALL reject it with HTTP status 401.

---

### Requirement 2: Model Selection

**User Story:** As a user, I want to select which AI models receive my prompt, so that I can control which responses I see side-by-side.

#### Acceptance Criteria

1. THE Playground SHALL display a selectable list containing at minimum the following models: GPT (OpenAI), Gemini (Google), and Claude (Anthropic).
2. WHEN a user selects one or more models before submitting a prompt, THE Playground SHALL include only the selected models in the submission request sent to the API_Gateway.
3. IF a user attempts to submit a prompt without selecting at least one model, THEN THE Playground SHALL display an inline validation message and prevent submission.
4. THE Playground SHALL allow a user to select any combination of the available models simultaneously.

---

### Requirement 3: Prompt Submission and Parallel Dispatch

**User Story:** As a user, I want to submit a single prompt to multiple models at once, so that I receive all responses without manually repeating the request per model.

#### Acceptance Criteria

1. WHEN a user submits a prompt, THE API_Gateway SHALL dispatch the prompt concurrently to all selected models.
2. WHEN a prompt is submitted, THE API_Gateway SHALL persist a record in the `prompts` table containing the user ID, prompt text, and creation timestamp before dispatching to models.
3. WHEN all selected models have responded, THE API_Gateway SHALL persist each response in the `responses` table with the associated prompt ID, model name, response text, Latency_ms, Token_Count, and Cost.
4. IF a prompt text is empty or consists solely of whitespace, THEN THE API_Gateway SHALL return HTTP status 400 with a descriptive validation error.
5. IF the prompt text exceeds 32,000 characters, THEN THE API_Gateway SHALL return HTTP status 400 with an error message stating the character limit.

---

### Requirement 4: Side-by-Side Response Display

**User Story:** As a user, I want to see responses from all selected models displayed side-by-side, so that I can compare them easily at a glance.

#### Acceptance Criteria

1. WHEN responses are received, THE Playground SHALL render each model's response in a separate, labelled panel displayed in parallel layout.
2. WHILE a model's response is pending, THE Playground SHALL display a loading indicator in that model's panel.
3. WHEN a response is rendered, THE Playground SHALL display the model name, response text, and Latency_ms for that response.
4. IF a model returns an error, THEN THE Playground SHALL display the error message in that model's panel without hiding the successful responses from other models.
5. THE Playground SHALL support rendering markdown formatting within response panels.

---

### Requirement 5: Response Latency Display

**User Story:** As a user, I want to see how long each model took to respond, so that I can factor response speed into my model preference.

#### Acceptance Criteria

1. WHEN a response is displayed, THE Playground SHALL show the Latency_ms value for that response, formatted as a human-readable duration (e.g., "1.23 s").
2. THE Playground SHALL begin measuring Latency_ms at the moment the API_Gateway dispatches the request to a Model and stop at the moment the full response is received.
3. WHEN multiple models have responded, THE Playground SHALL visually highlight the panel with the lowest Latency_ms value.

---

### Requirement 6: Prompt History

**User Story:** As a user, I want to view my previously submitted prompts and their responses, so that I can revisit and reuse past work.

#### Acceptance Criteria

1. THE Playground SHALL provide a navigable Prompt_History screen listing all prompts submitted by the authenticated user, ordered by creation timestamp descending.
2. WHEN a user selects a prompt from Prompt_History, THE Playground SHALL display the prompt text and all stored responses associated with that prompt.
3. WHEN a user selects a historical prompt, THE Playground SHALL provide a one-tap action to resubmit that prompt to the currently selected models.
4. THE Prompt_History list SHALL display the prompt text (truncated to 120 characters) and creation timestamp for each entry.
5. IF the authenticated user has no prior prompts, THEN THE Playground SHALL display an empty-state message on the Prompt_History screen.

---

### Requirement 7: Cost Analytics Dashboard

**User Story:** As a user, I want to see a summary of my API usage and estimated costs, so that I can monitor spending across models.

#### Acceptance Criteria

1. THE Cost_Analytics_Dashboard SHALL display the total number of requests made, aggregated across all models, for the authenticated user.
2. THE Cost_Analytics_Dashboard SHALL display the total Token_Count consumed, broken down per model.
3. THE Cost_Analytics_Dashboard SHALL display the total estimated Cost, broken down per model.
4. WHEN a new response is stored, THE API_Gateway SHALL update the aggregated analytics data so that the Cost_Analytics_Dashboard reflects the latest values within 5 seconds.
5. THE Cost_Analytics_Dashboard SHALL allow the user to filter aggregated data by a date range with a start date and an end date.
6. IF the selected date range contains no data, THEN THE Cost_Analytics_Dashboard SHALL display a zero-state indicating no activity for that period.

---

### Requirement 8: Prompt Templates

**User Story:** As a user, I want to select from pre-defined prompt templates, so that I can start common tasks quickly without writing prompts from scratch.

#### Acceptance Criteria

1. THE Playground SHALL expose a Prompt_Template picker containing at minimum four categories: Coding, Interview Preparation, Content Writing, and Summarization.
2. WHEN a user selects a Prompt_Template, THE Playground SHALL populate the prompt input field with the template text, leaving the cursor positioned for the user to customise the placeholder values.
3. THE Playground SHALL allow a user to edit the populated template text before submitting.
4. WHEN a user selects a Prompt_Template, THE Playground SHALL not automatically submit the prompt.

---

### Requirement 9: Response Rating

**User Story:** As a user, I want to rate each model's response, so that I can record which responses I found most useful.

#### Acceptance Criteria

1. WHEN a Response is displayed, THE Playground SHALL show rating controls for Accuracy, Clarity, and Helpfulness, each accepting an integer value from 1 to 5.
2. WHEN a user submits a Rating, THE API_Gateway SHALL persist the rating values against the associated response ID in the database.
3. THE Playground SHALL allow a user to update a previously submitted Rating for a response, replacing the stored values.
4. WHEN a Rating has been submitted for a response, THE Playground SHALL display the stored rating values alongside the response.
5. IF a rating value submitted by the user is outside the range 1–5, THEN THE API_Gateway SHALL return HTTP status 400 with a descriptive validation error.

---

### Requirement 10: Document Upload for RAG Mode

**User Story:** As a user, I want to upload a PDF or DOCX document, so that I can ask questions that are grounded in the content of that document.

#### Acceptance Criteria

1. THE Playground SHALL provide a document upload control that accepts files with `.pdf` and `.docx` extensions.
2. WHEN a Document is uploaded, THE API_Gateway SHALL validate that the file is a well-formed PDF or DOCX and that its size does not exceed 20 MB.
3. IF an uploaded file fails format validation or exceeds the size limit, THEN THE API_Gateway SHALL return HTTP status 422 with an error message identifying the specific violation.
4. WHEN a valid Document is uploaded, THE API_Gateway SHALL split the document text into Chunks of at most 512 tokens with a 50-token overlap between consecutive Chunks.
5. WHEN Chunks are produced, THE API_Gateway SHALL generate an Embedding for each Chunk and persist all Embeddings in the Vector_DB, associated with the Document ID and the authenticated user.
6. WHEN document processing completes, THE API_Gateway SHALL notify the Playground so that RAG Mode becomes available for that Document.

---

### Requirement 11: RAG Mode Query

**User Story:** As a user, I want to submit a question that is answered using the content of my uploaded document across all selected models, so that I can compare how each model interprets and uses my document.

#### Acceptance Criteria

1. WHILE RAG Mode is active for a Document, THE Playground SHALL indicate to the user that responses will be grounded in that Document's content.
2. WHEN a user submits a prompt in RAG Mode, THE API_Gateway SHALL query the Vector_DB to retrieve the top-5 most semantically similar Chunks from the active Document.
3. WHEN relevant Chunks are retrieved, THE API_Gateway SHALL prepend the Chunk text as context to the prompt before dispatching to each selected model.
4. WHEN RAG Mode responses are displayed, THE Playground SHALL indicate which Document was used as context.
5. IF the Vector_DB returns no Chunks with a cosine similarity above 0.5 for a given prompt, THEN THE API_Gateway SHALL inform the Playground that no relevant context was found and SHALL proceed to dispatch the prompt without injected context.

---

### Requirement 12: AI Judge Evaluation

**User Story:** As a user, I want an AI-powered evaluation of all model responses to a prompt, so that I can understand which response is most accurate, detailed, and factually correct.

#### Acceptance Criteria

1. WHEN all selected models have responded to a prompt, THE Playground SHALL display an "Evaluate with AI Judge" action.
2. WHEN the user triggers AI Judge evaluation, THE API_Gateway SHALL submit all model responses for the prompt to the GPT-based AI_Judge with an evaluation rubric covering factual accuracy, depth of explanation, and quality of examples.
3. WHEN the AI_Judge returns results, THE API_Gateway SHALL parse the evaluation output into a structured result containing: a ranked list of models, a score per model (integer 1–100), and a text reasoning per model.
4. WHEN the AI Judge evaluation result is displayed, THE Playground SHALL render the ranked list, per-model scores, and reasoning text in a dedicated evaluation panel.
5. IF the AI_Judge call fails or returns a malformed response, THEN THE API_Gateway SHALL return an error to the Playground with HTTP status 502 and a message indicating the evaluation service is unavailable.
6. THE AI_Judge evaluation result SHALL be persisted in the database associated with the originating prompt ID so that it can be retrieved from Prompt_History.

---

### Requirement 13: API Gateway Fan-Out Resilience

**User Story:** As a developer, I want the API gateway to handle individual model failures gracefully, so that a single provider outage does not prevent users from seeing results from the other models.

#### Acceptance Criteria

1. WHEN the API_Gateway dispatches a prompt to multiple models concurrently and one or more model requests fail, THE API_Gateway SHALL return the successful responses alongside per-model error details, rather than failing the entire request.
2. IF a model API call does not return a response within 30 seconds, THEN THE API_Gateway SHALL treat that call as a timeout, record a timeout error for that model, and continue processing other model responses.
3. WHEN a model request fails, THE API_Gateway SHALL record the failure reason (timeout, HTTP error code, or provider error message) in the `responses` table for that model/prompt combination.

---

### Requirement 14: Round-Trip Persistence Integrity

**User Story:** As a developer, I want prompts and responses stored and retrieved without data loss, so that prompt history is always accurate and complete.

#### Acceptance Criteria

1. FOR ALL prompts submitted by an authenticated user, THE API_Gateway SHALL store and retrieve the prompt text such that the retrieved text is identical to the submitted text (round-trip property).
2. FOR ALL responses received from a model, THE API_Gateway SHALL store and retrieve the response text such that the retrieved text is identical to the received text (round-trip property).
3. THE API_Gateway SHALL enforce a foreign-key constraint between the `responses` table and the `prompts` table such that no response record can exist without a corresponding prompt record.

