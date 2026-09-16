// Package localization — kk/ru/en/uz аудармалары (веб және әкімші панелі үшін).
package localization

import (
	"embed"
	"encoding/json"
	"net/http"
	"sort"
	"strings"

	"github.com/aireply/ai-reply-back-end/internal/domain"
)

//go:embed locales/*.json
var files embed.FS

// Bundle — барлық тілдегі жолдар.
type Bundle struct {
	messages map[string]map[string]string
}

// Load — аудармаларды оқиды.
func Load() (*Bundle, error) {
	bundle := &Bundle{messages: map[string]map[string]string{}}
	for _, locale := range domain.Locales {
		raw, err := files.ReadFile("locales/" + locale + ".json")
		if err != nil {
			return nil, err
		}
		var parsed map[string]string
		if err := json.Unmarshal(raw, &parsed); err != nil {
			return nil, err
		}
		bundle.messages[locale] = parsed
	}
	return bundle, nil
}

// T — кілт бойынша аударма; табылмаса ағылшынша, ол да жоқ болса кілттің өзі.
func (b *Bundle) T(locale, key string) string {
	if v, ok := b.messages[domain.NormalizeLocale(locale)][key]; ok && v != "" {
		return v
	}
	if v, ok := b.messages["en"][key]; ok && v != "" {
		return v
	}
	return key
}

// Translator — шаблонға берілетін функция.
func (b *Bundle) Translator(locale string) func(string) string {
	return func(key string) string { return b.T(locale, key) }
}

// Locales — қолдау көрсетілетін тілдер.
func (b *Bundle) Locales() []string { return domain.Locales }

// Detect — сұраныстан тіл: ?lang → cookie → Accept-Language → en.
func Detect(r *http.Request, fallback string) string {
	if q := r.URL.Query().Get("lang"); q != "" {
		return domain.NormalizeLocale(q)
	}
	if c, err := r.Cookie("lang"); err == nil && c.Value != "" {
		return domain.NormalizeLocale(c.Value)
	}
	for _, part := range strings.Split(r.Header.Get("Accept-Language"), ",") {
		tag := strings.TrimSpace(strings.SplitN(part, ";", 2)[0])
		if tag == "" {
			continue
		}
		if len(tag) >= 2 {
			candidate := strings.ToLower(tag[:2])
			for _, l := range domain.Locales {
				if l == candidate {
					return l
				}
			}
		}
	}
	if fallback != "" {
		return domain.NormalizeLocale(fallback)
	}
	return "en"
}

// SetCookie — таңдалған тілді есте сақтау.
func SetCookie(w http.ResponseWriter, locale string, secure bool) {
	http.SetCookie(w, &http.Cookie{
		Name:     "lang",
		Value:    domain.NormalizeLocale(locale),
		Path:     "/",
		MaxAge:   365 * 24 * 3600,
		HttpOnly: false,
		Secure:   secure,
		SameSite: http.SameSiteLaxMode,
	})
}

// Keys — барлық аударма кілттері (SPA-ға жіберілетін жиынды сүзу үшін).
func (b *Bundle) Keys() []string {
	base := b.messages["en"]
	keys := make([]string, 0, len(base))
	for k := range base {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
