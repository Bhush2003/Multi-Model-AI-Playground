package db

import (
	"errors"
	"fmt"
	"strings"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

// RunMigrations applies all pending "up" migrations from the db/migrations/
// directory. It returns nil both on success and when no migrations are pending
// (migrate.ErrNoChange).
//
// NOTE: The "file://db/migrations" source path is relative to the working
// directory of the running binary. When starting the server from the backend/
// directory (e.g. `go run .` or `./server`), this path resolves correctly to
// backend/db/migrations. If the binary is run from a different directory, set
// the MIGRATIONS_PATH environment variable or adjust the path accordingly.
func RunMigrations(databaseURL string) error {
	// golang-migrate's pgx/v5 driver expects the "pgx5://" scheme instead of
	// the standard "postgres://" or "postgresql://" scheme.
	migrateURL := toPgx5URL(databaseURL)

	m, err := migrate.New(
		"file://db/migrations",
		migrateURL,
	)
	if err != nil {
		return fmt.Errorf("migrate: init: %w", err)
	}
	defer m.Close()

	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("migrate: up: %w", err)
	}
	return nil
}

// toPgx5URL converts a standard postgres:// or postgresql:// connection URL
// to the pgx5:// scheme required by the golang-migrate pgx/v5 driver.
func toPgx5URL(databaseURL string) string {
	for _, prefix := range []string{"postgresql://", "postgres://"} {
		if strings.HasPrefix(databaseURL, prefix) {
			return "pgx5://" + databaseURL[len(prefix):]
		}
	}
	// Already using pgx5:// or some other scheme — return as-is.
	return databaseURL
}
