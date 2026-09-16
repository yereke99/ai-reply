package traits

import "time"

// Clock тестте уақытты басқаруға мүмкіндік беретін шағын абстракция.
type Clock interface {
	Now() time.Time
}

// SystemClock нақты уақыт.
type SystemClock struct{}

func (SystemClock) Now() time.Time { return time.Now().UTC() }

// FixedClock тесттерге арналған тұрақты уақыт.
type FixedClock struct{ T time.Time }

func (c *FixedClock) Now() time.Time          { return c.T.UTC() }
func (c *FixedClock) Advance(d time.Duration) { c.T = c.T.Add(d) }

// Millis уақытты UTC unix миллисекундқа айналдырады (БД-дағы жалғыз формат).
func Millis(t time.Time) int64 { return t.UTC().UnixMilli() }

// FromMillis кері түрлендіру.
func FromMillis(ms int64) time.Time { return time.UnixMilli(ms).UTC() }

// NullMillis нөлдік уақытты NULL ретінде береді.
func NullMillis(t *time.Time) *int64 {
	if t == nil || t.IsZero() {
		return nil
	}
	v := Millis(*t)
	return &v
}
