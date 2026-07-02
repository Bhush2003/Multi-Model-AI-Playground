-- Migration: 000001_initial_schema (down)
-- Drops all core tables in reverse dependency order.

DROP TABLE IF EXISTS evaluations;
DROP TABLE IF EXISTS templates;
DROP TABLE IF EXISTS ratings;
DROP TABLE IF EXISTS responses;
DROP TABLE IF EXISTS prompts;
DROP TABLE IF EXISTS documents;
DROP TABLE IF EXISTS users;
