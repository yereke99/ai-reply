// Package repository — SQL қабаты. Домендік логика мұнда жоқ.
package repository

import (
	"database/sql"
	"strings"
	"time"

	"github.com/aireply/ai-reply-back-end/internal/database"
	"github.com/aireply/ai-reply-back-end/internal/traits"
)

// Store — барлық репозиторийлердің ортақ негізі.
type Store struct {
	db *database.DB
}

// New — репозиторий жиынтығын құрады.
func New(db *database.DB) *Store { return &Store{db: db} }

// DB — тікелей қол жеткізу (миграция, диагностика).
func (s *Store) DB() *database.DB { return s.db }

// ---------------------------------------------------------------- helpers

func ms(t time.Time) int64 { return traits.Millis(t) }

func msPtr(t *time.Time) any {
	if t == nil || t.IsZero() {
		return nil
	}
	return traits.Millis(*t)
}

func timeFrom(v int64) time.Time { return traits.FromMillis(v) }

func timePtr(v sql.NullInt64) *time.Time {
	if !v.Valid {
		return nil
	}
	t := traits.FromMillis(v.Int64)
	return &t
}

func text(v sql.NullString) string { return v.String }

func nullText(v string) any {
	if strings.TrimSpace(v) == "" {
		return nil
	}
	return v
}
