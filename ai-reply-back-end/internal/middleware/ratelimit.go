package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/aireply/ai-reply-back-end/internal/transport/httpx"
)

// Limiter — жадтағы жылжымалы терезе.
//
// In memory is the right call for a single-instance deployment and the wrong
// call behind more than one replica: swap this type for Redis and nothing else
// changes. Saying that plainly beats shipping something that looks distributed
// and is not.
type Limiter struct {
	mu      sync.Mutex
	hits    map[string][]time.Time
	lastGC  time.Time
	maxKeys int
}

// NewLimiter — лимитер.
func NewLimiter() *Limiter {
	return &Limiter{hits: make(map[string][]time.Time), lastGC: time.Now(), maxKeys: 50000}
}

// Allow — берілген кілт үшін терезеде орын бар ма.
func (l *Limiter) Allow(key string, limit int, window time.Duration) (bool, time.Duration) {
	if limit <= 0 {
		return true, 0
	}
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()

	if now.Sub(l.lastGC) > 10*time.Minute || len(l.hits) > l.maxKeys {
		for k, v := range l.hits {
			live := filter(v, now, window)
			if len(live) == 0 {
				delete(l.hits, k)
			} else {
				l.hits[k] = live
			}
		}
		l.lastGC = now
	}

	live := filter(l.hits[key], now, window)
	if len(live) >= limit {
		retry := window - now.Sub(live[0])
		l.hits[key] = live
		if retry < time.Second {
			retry = time.Second
		}
		return false, retry
	}
	l.hits[key] = append(live, now)
	return true, 0
}

func filter(values []time.Time, now time.Time, window time.Duration) []time.Time {
	out := values[:0]
	for _, t := range values {
		if now.Sub(t) < window {
			out = append(out, t)
		}
	}
	return out
}

// KeyFunc — лимит кілтін есептеу.
type KeyFunc func(*http.Request) string

// RateLimit — миддлварь түріндегі шектеу.
func RateLimit(l *Limiter, bucket string, limit int, window time.Duration, key KeyFunc) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ok, retry := l.Allow(bucket+":"+key(r), limit, window)
			if !ok {
				w.Header().Set("Retry-After", itoa(int(retry.Seconds())))
				httpx.Error(w, http.StatusTooManyRequests, httpx.CodeRateLimited,
					"Too many requests. Try again shortly.",
					map[string]any{"retry_after_seconds": int(retry.Seconds())})
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func itoa(v int) string {
	if v <= 0 {
		return "1"
	}
	digits := ""
	for v > 0 {
		digits = string(rune('0'+v%10)) + digits
		v /= 10
	}
	return digits
}
