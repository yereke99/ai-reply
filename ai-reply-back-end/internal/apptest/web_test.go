package apptest

import (
	"io"
	"net/http"
	"strings"
	"testing"
)

func fetch(t *testing.T, h *harness, path string) (int, string) {
	t.Helper()
	client := h.server.Client()
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	res, err := client.Get(h.server.URL + path)
	if err != nil {
		t.Fatalf("get %s: %v", path, err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	return res.StatusCode, string(body)
}

// Лендинг төрт тілде де рендерленеді және тарифтерді дерекқордан алады.
func TestLandingRendersInAllLocales(t *testing.T) {
	h := newHarness(t)
	expect := map[string]string{
		"kk": "Тегін",
		"ru": "Бесплатный",
		"en": "Free",
		"uz": "Bepul",
	}
	for locale, needle := range expect {
		status, body := fetch(t, h, "/?lang="+locale)
		if status != http.StatusOK {
			t.Fatalf("landing %s: status %d", locale, status)
		}
		if !strings.Contains(body, needle) {
			t.Fatalf("landing %s does not contain the localized free plan name %q", locale, needle)
		}
		if !strings.Contains(body, `lang="`+locale+`"`) {
			t.Fatalf("landing %s has the wrong html lang attribute", locale)
		}
	}
	// Лендингте жалған уәде жоқ: жазысуды автоматты оқу туралы мәлімдеме болмауы керек.
	_, body := fetch(t, h, "/?lang=en")
	if strings.Contains(strings.ToLower(body), "reads all your chats") {
		t.Fatal("landing makes a capability claim the platform does not allow")
	}
}

// Заң беттері ашылады.
func TestLegalPages(t *testing.T) {
	h := newHarness(t)
	for _, path := range []string{"/terms?lang=kk", "/privacy?lang=ru", "/terms?lang=uz", "/privacy?lang=en"} {
		if status, _ := fetch(t, h, path); status != http.StatusOK {
			t.Fatalf("%s: status %d", path, status)
		}
	}
}

// Әкімші қосымшасы сессиясыз кіру бетіне бағыттайды.
func TestAdminAppRequiresLogin(t *testing.T) {
	h := newHarness(t)
	status, _ := fetch(t, h, "/admin")
	if status != http.StatusSeeOther {
		t.Fatalf("status = %d, want 303 redirect to login", status)
	}
	status, body := fetch(t, h, "/admin/login")
	if status != http.StatusOK {
		t.Fatalf("login page status %d", status)
	}
	if !strings.Contains(body, "csrf") {
		t.Fatal("login form has no CSRF token")
	}
}

// Кіргеннен кейін SPA қабығы беріледі, ішінде CSRF пен аудармалар бар.
func TestAdminAppShell(t *testing.T) {
	h := newHarness(t)
	adminSession := h.signInAdmin()

	req, _ := http.NewRequest(http.MethodGet, h.server.URL+"/admin/users", nil)
	req.AddCookie(&http.Cookie{Name: h.cfg.Admin.CookieName, Value: adminSession.cookie})
	res, err := h.server.Client().Do(req)
	if err != nil {
		t.Fatalf("shell: %v", err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	page := string(body)

	if res.StatusCode != http.StatusOK {
		t.Fatalf("shell status %d", res.StatusCode)
	}
	for _, needle := range []string{"vue.global.prod.js", "admin-app.js", "\"csrf\"", "admin.nav.dashboard"} {
		if !strings.Contains(page, needle) {
			t.Fatalf("admin shell missing %q", needle)
		}
	}
}

// Денсаулық тексеру.
func TestHealthEndpoints(t *testing.T) {
	h := newHarness(t)
	for _, path := range []string{"/healthz", "/readyz"} {
		status, body := fetch(t, h, path)
		if status != http.StatusOK || !strings.Contains(body, `"ok":true`) {
			t.Fatalf("%s: %d %s", path, status, body)
		}
	}
}

// Статикалық файлдар беріледі (Vue, CSS, скрипттер).
func TestStaticAssets(t *testing.T) {
	h := newHarness(t)
	for _, path := range []string{"/static/landing.css", "/static/admin.css", "/static/admin-app.js",
		"/static/landing.js", "/static/vendor/vue.global.prod.js", "/static/favicon.svg"} {
		if status, _ := fetch(t, h, path); status != http.StatusOK {
			t.Fatalf("%s: status %d", path, status)
		}
	}
}
