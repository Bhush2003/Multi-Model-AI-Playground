-- Migration: 000002_seed_templates (up)
-- Seeds the templates table with pre-defined prompt skeletons for each
-- required category (Req 8 AC1).
-- Placeholders use [UPPER_CASE] notation so users can spot and replace them.

INSERT INTO templates (category, title, body) VALUES

-- ── Coding ──────────────────────────────────────────────────────────────────
('Coding', 'Debug this code',
'Please help me debug the following code:

```[LANGUAGE]
[PASTE YOUR CODE HERE]
```

The issue I am experiencing: [DESCRIBE THE BUG OR ERROR MESSAGE]

What I have already tried: [DESCRIBE ANY FIXES YOU ATTEMPTED]'),

('Coding', 'Explain this code',
'Please explain the following code in plain language:

```[LANGUAGE]
[PASTE YOUR CODE HERE]
```

I would like you to cover:
1. What the code does overall
2. How the key functions/sections work
3. Any potential edge cases or concerns you notice'),

('Coding', 'Write unit tests',
'Please write comprehensive unit tests for the following code:

```[LANGUAGE]
[PASTE YOUR CODE HERE]
```

Testing framework to use: [e.g. Jest, pytest, Go testing package]
Focus areas: [e.g. happy path, edge cases, error handling]'),

-- ── Interview Preparation ────────────────────────────────────────────────────
('Interview Preparation', 'Behavioral question practice',
'I am preparing for a behavioral interview at [COMPANY NAME] for a [JOB TITLE] role.

Please ask me the following behavioral question and then give me structured feedback on my answer:

Question: "[BEHAVIORAL QUESTION, e.g. Tell me about a time you handled a conflict with a teammate]"

My answer: [PASTE YOUR ANSWER HERE]

Evaluate my response against the STAR method (Situation, Task, Action, Result) and suggest improvements.'),

('Interview Preparation', 'System design question',
'Please walk me through a system design for the following problem:

"[SYSTEM DESIGN PROMPT, e.g. Design a URL shortener like bit.ly]"

I am interviewing at [COMPANY NAME] for a [SENIOR/STAFF] [ROLE] position.

Please cover:
1. Requirements clarification (functional and non-functional)
2. High-level architecture
3. Data model and storage choices
4. Scalability and bottlenecks
5. Trade-offs and alternatives'),

('Interview Preparation', 'Coding interview prep',
'I have a coding interview coming up. Please help me solve and explain the following problem:

Problem: [PASTE THE PROBLEM STATEMENT HERE]

Constraints:
- [CONSTRAINT 1, e.g. time complexity must be O(n log n)]
- [CONSTRAINT 2]

My current approach: [DESCRIBE YOUR INITIAL THOUGHTS OR PASTE YOUR ATTEMPT]

Please provide the optimal solution with a step-by-step explanation and time/space complexity analysis.'),

-- ── Content Writing ──────────────────────────────────────────────────────────
('Content Writing', 'Write a blog post',
'Write a [WORD COUNT, e.g. 800-word] blog post on the following topic:

Topic: [TOPIC OR TITLE]

Target audience: [DESCRIBE YOUR AUDIENCE, e.g. developers, beginners, business owners]
Tone: [e.g. conversational, professional, educational]
Key points to cover:
1. [POINT 1]
2. [POINT 2]
3. [POINT 3]

Include a compelling introduction, clear headings, and a call-to-action at the end.'),

('Content Writing', 'Write product description',
'Write a compelling product description for the following product:

Product name: [PRODUCT NAME]
Product category: [CATEGORY]

Key features:
- [FEATURE 1]
- [FEATURE 2]
- [FEATURE 3]

Target customer: [DESCRIBE THE IDEAL CUSTOMER]
Tone: [e.g. enthusiastic, professional, minimalist]
Length: [SHORT (50 words) / MEDIUM (100 words) / LONG (200+ words)]

Focus on benefits over features and include a clear value proposition.'),

-- ── Summarization ────────────────────────────────────────────────────────────
('Summarization', 'Summarize text',
'Please summarize the following text:

---
[PASTE YOUR TEXT HERE]
---

Summary format: [e.g. 3 bullet points / one paragraph / executive summary]
Target length: [e.g. under 100 words]
Focus: [e.g. main arguments, action items, key facts]'),

('Summarization', 'Key takeaways',
'Extract the key takeaways from the following content:

---
[PASTE YOUR CONTENT HERE]
---

Please provide:
1. The 3-5 most important insights
2. Any actionable recommendations
3. Open questions or areas that need further investigation

Audience for this summary: [DESCRIBE WHO WILL READ THIS, e.g. executive team, developers]');
