package database

import (
	"context"
	"database/sql"
	"fmt"
	"io/fs"
	"sort"
	"strings"
	"time"
)

// Migrate қолданылмаған миграцияларды реті бойынша жүргізеді.
// SQL көзі — migrations пакеті (бинарге кіріктірілген).
func Migrate(ctx context.Context, db *DB, source fs.FS) ([]string, error) {
	if _, err := db.Writer().ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			name       TEXT PRIMARY KEY,
			applied_at INTEGER NOT NULL
		)`); err != nil {
		return nil, fmt.Errorf("migrate: bootstrap: %w", err)
	}

	entries, err := fs.ReadDir(source, ".")
	if err != nil {
		return nil, fmt.Errorf("migrate: read dir: %w", err)
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	applied := map[string]bool{}
	rows, err := db.Reader().QueryContext(ctx, `SELECT name FROM schema_migrations`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		applied[name] = true
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	var run []string
	for _, name := range names {
		if applied[name] {
			continue
		}
		body, err := fs.ReadFile(source, name)
		if err != nil {
			return nil, err
		}
		err = db.Tx(ctx, func(tx *sql.Tx) error {
			if _, err := tx.ExecContext(ctx, string(body)); err != nil {
				return fmt.Errorf("migrate %s: %w", name, err)
			}
			_, err := tx.ExecContext(ctx,
				`INSERT INTO schema_migrations (name, applied_at) VALUES (?, ?)`,
				name, time.Now().UTC().UnixMilli())
			return err
		})
		if err != nil {
			return run, err
		}
		run = append(run, name)
	}
	return run, nil
}
