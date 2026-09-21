package apptest

import (
	"bytes"
	"net/http"
	"strings"
	"testing"

	"github.com/aireply/ai-reply-back-end/internal/simulator"
)

// signInSimulator — симулятордың өз кіру беті арқылы кіру.
//
// Тіркелгі деректері әкімші панелімен бірдей: бөлек құпиясөз жоқ.
func (h *harness) signInSimulator() adminSession {
	h.t.Helper()
	client := h.server.Client()
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }

	form, err := client.Get(h.server.URL + "/simulator/login")
	if err != nil {
		h.t.Fatalf("simulator login form: %v", err)
	}
	defer form.Body.Close()
	var csrfCookie string
	for _, c := range form.Cookies() {
		if c.Name == "aireply_sim_csrf" {
			csrfCookie = c.Value
		}
	}
	if csrfCookie == "" {
		h.t.Fatal("simulator csrf cookie missing")
	}

	req, _ := http.NewRequest(http.MethodPost, h.server.URL+"/simulator/login",
		bytes.NewReader([]byte("email="+adminEmail+"&password="+adminPassword+"&csrf="+csrfCookie)))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.AddCookie(&http.Cookie{Name: "aireply_sim_csrf", Value: csrfCookie})
	res, err := client.Do(req)
	if err != nil {
		h.t.Fatalf("simulator login: %v", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/simulator" {
		h.t.Fatalf("simulator login status %d → %q", res.StatusCode, res.Header.Get("Location"))
	}
	var sessionCookie string
	for _, c := range res.Cookies() {
		if c.Name == h.cfg.Admin.CookieName {
			sessionCookie = c.Value
		}
	}
	if sessionCookie == "" {
		h.t.Fatal("simulator session cookie missing")
	}

	boot := h.do(http.MethodGet, "/api/v1/simulator/bootstrap", nil,
		map[string]string{"Cookie": h.cfg.Admin.CookieName + "=" + sessionCookie})
	if boot.status != http.StatusOK {
		h.t.Fatalf("bootstrap: %d %s", boot.status, boot.raw)
	}
	return adminSession{cookie: sessionCookie, csrf: boot.str("csrf")}
}

// TestSimulatorIsClosedWithoutASession — симулятор ешқашан ашық тұрмайды.
func TestSimulatorIsClosedWithoutASession(t *testing.T) {
	h := newHarness(t)
	client := h.server.Client()
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }

	page, err := client.Get(h.server.URL + "/simulator")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	defer page.Body.Close()
	if page.StatusCode != http.StatusSeeOther || page.Header.Get("Location") != "/simulator/login" {
		t.Fatalf("expected redirect to the login page, got %d → %q",
			page.StatusCode, page.Header.Get("Location"))
	}

	for _, path := range []string{
		"/api/v1/simulator/bootstrap", "/api/v1/simulator/account",
		"/api/v1/simulator/admin/overview", "/api/v1/simulator/health",
	} {
		if got := h.do(http.MethodGet, path, nil, nil); got.status != http.StatusUnauthorized {
			t.Fatalf("%s: expected 401 without a session, got %d", path, got.status)
		}
	}
	if got := h.do(http.MethodPost, "/api/v1/simulator/generate",
		map[string]any{"source_text": "hi"}, nil); got.status != http.StatusUnauthorized {
		t.Fatalf("generate: expected 401 without a session, got %d", got.status)
	}
}

// TestSimulatorSignsInWithTheAdminAccount — бөлек құпиясөз жоқ екенін бекітеді.
func TestSimulatorSignsInWithTheAdminAccount(t *testing.T) {
	h := newHarness(t)
	session := h.signInSimulator()
	if session.csrf == "" {
		t.Fatal("bootstrap returned no CSRF token")
	}

	page := h.do(http.MethodGet, "/simulator", nil,
		map[string]string{"Cookie": h.cfg.Admin.CookieName + "=" + session.cookie})
	if page.status != http.StatusOK {
		t.Fatalf("simulator page: %d", page.status)
	}
	body := string(page.raw)
	for _, want := range []string{"/static/simulator.css", "/static/simulator/app.js", "noindex"} {
		if !strings.Contains(body, want) {
			t.Fatalf("simulator shell is missing %q", want)
		}
	}
	// Бетте ешқандай құпия болмауы керек.
	for _, secret := range []string{adminPassword, h.cfg.OpenAI.APIKey, h.cfg.Auth.AccessSecret} {
		if strings.Contains(body, secret) {
			t.Fatal("the simulator shell leaked a secret into the page")
		}
	}
}

// TestSimulatorGeneratesThroughTheRealGateway — генерация нақты шлюзбен жүреді.
func TestSimulatorGeneratesThroughTheRealGateway(t *testing.T) {
	h := newHarness(t)
	session := h.signInSimulator()
	headers := session.headers(h.cfg.Admin.CookieName)

	before := h.provider.calls
	res := h.do(http.MethodPost, "/api/v1/simulator/generate", map[string]any{
		"source_text": "Здравствуйте! Товар в наличии?",
		"instruction": "Ответь вежливо.",
		"language":    "ru",
		"template_id": "client",
		"platform":    "ios",
	}, headers)
	if res.status != http.StatusOK {
		t.Fatalf("generate: %d %s", res.status, res.raw)
	}
	if h.provider.calls != before+1 {
		t.Fatalf("expected exactly one provider call, got %d", h.provider.calls-before)
	}
	if res.str("reply") == "" {
		t.Fatal("no reply returned")
	}
	if res.num("usage", "used_today") != 1 {
		t.Fatalf("quota was not consumed: used_today = %v", res.num("usage", "used_today"))
	}
	// Із тазартылған: кілт те, тақырып та жоқ.
	trace := string(res.raw)
	for _, forbidden := range []string{h.cfg.OpenAI.APIKey, "Authorization", "Bearer ", session.cookie} {
		if strings.Contains(trace, forbidden) {
			t.Fatalf("the response trace leaked %q", forbidden)
		}
	}
	if res.str("trace", "model") == "" {
		t.Fatal("trace has no model")
	}
}

// TestSimulatorStoresNoMessageText — көрсетілім де мәтін қалдырмайды.
func TestSimulatorStoresNoMessageText(t *testing.T) {
	h := newHarness(t)
	session := h.signInSimulator()

	needle := "ZZQX-simulator-secret-payload-4417"
	res := h.do(http.MethodPost, "/api/v1/simulator/generate", map[string]any{
		"source_text": needle, "instruction": "Reply politely.", "language": "en",
		"template_id": "client", "platform": "web",
	}, session.headers(h.cfg.Admin.CookieName))
	if res.status != http.StatusOK {
		t.Fatalf("generate: %d %s", res.status, res.raw)
	}
	if h.dbContains(needle) {
		t.Fatal("the copied message reached the database")
	}
	if strings.Contains(h.logs.String(), needle) {
		t.Fatal("the copied message reached the logs")
	}
}

// TestSimulatorProfileIsSavedThroughTheRealService — профиль нақты сақталады.
func TestSimulatorProfileIsSavedThroughTheRealService(t *testing.T) {
	h := newHarness(t)
	session := h.signInSimulator()
	headers := session.headers(h.cfg.Admin.CookieName)

	saved := h.do(http.MethodPost, "/api/v1/simulator/account/profile", map[string]any{
		"preferred_tone":   "formal",
		"role":             "business",
		"business_summary": "Legal consulting for small businesses.",
	}, headers)
	if saved.status != http.StatusOK {
		t.Fatalf("save profile: %d %s", saved.status, saved.raw)
	}
	if saved.str("profile", "preferred_tone") != "formal" {
		t.Fatalf("tone was not saved: %q", saved.str("profile", "preferred_tone"))
	}

	again := h.do(http.MethodGet, "/api/v1/simulator/account", nil, headers)
	if again.str("profile", "business_summary") != "Legal consulting for small businesses." {
		t.Fatalf("business summary did not survive a reload: %q", again.str("profile", "business_summary"))
	}
	if again.str("id") != simulator.AccountID {
		t.Fatalf("the simulator wrote to the wrong account: %q", again.str("id"))
	}
}

// TestSimulatorRespectsTheDailyLimit — квота симуляторда да нақты.
func TestSimulatorRespectsTheDailyLimit(t *testing.T) {
	h := newHarness(t)
	session := h.signInSimulator()
	headers := session.headers(h.cfg.Admin.CookieName)

	account := h.do(http.MethodGet, "/api/v1/simulator/account", nil, headers)
	limit := int(account.num("usage", "daily_limit"))
	if limit <= 0 || limit > 20 {
		t.Fatalf("unexpected free daily limit: %d", limit)
	}

	body := map[string]any{"source_text": "Hello, is it available?", "instruction": "",
		"language": "en", "template_id": "client", "platform": "android"}
	for i := 0; i < limit; i++ {
		if got := h.do(http.MethodPost, "/api/v1/simulator/generate", body, headers); got.status != http.StatusOK {
			t.Fatalf("generation %d failed: %d %s", i+1, got.status, got.raw)
		}
	}
	blocked := h.do(http.MethodPost, "/api/v1/simulator/generate", body, headers)
	if blocked.status != http.StatusTooManyRequests || blocked.errorCode() != "DAILY_LIMIT_REACHED" {
		t.Fatalf("expected the limit to stop generation, got %d %s", blocked.status, blocked.raw)
	}

	reset := h.do(http.MethodPost, "/api/v1/simulator/account/reset-quota", map[string]any{}, headers)
	if reset.status != http.StatusOK || reset.num("usage", "used_today") != 0 {
		t.Fatalf("quota reset failed: %d %s", reset.status, reset.raw)
	}
}

// TestSimulatorPricingStaysInTheDemoLayer — өндірістік баға қозғалмайды.
func TestSimulatorPricingStaysInTheDemoLayer(t *testing.T) {
	h := newHarness(t)
	session := h.signInSimulator()
	headers := session.headers(h.cfg.Admin.CookieName)

	public := h.do(http.MethodGet, "/api/v1/plans", nil, nil)
	if public.status != http.StatusOK {
		t.Fatalf("plans: %d", public.status)
	}
	list, _ := public.body["plans"].([]any)
	if len(list) == 0 {
		t.Fatal("no plans in the catalogue")
	}
	first, _ := list[0].(map[string]any)
	planID, _ := first["id"].(string)
	originalPrice, _ := first["price"].(float64)
	originalLimit, _ := first["daily_message_limit"].(float64)

	draft := h.do(http.MethodPost, "/api/v1/simulator/admin/plan-draft", map[string]any{
		"plan_id": planID, "price": int64(originalPrice) + 500000,
		"daily_message_limit": int(originalLimit) + 43, "monthly_message_limit": 0, "period_days": 30,
	}, headers)
	if draft.status != http.StatusOK {
		t.Fatalf("plan draft: %d %s", draft.status, draft.raw)
	}
	if draft.str("scope") != "demo" {
		t.Fatalf("the draft was not marked as demo: %q", draft.str("scope"))
	}

	// Өндірістік каталог сол күйінде.
	after := h.do(http.MethodGet, "/api/v1/plans", nil, nil)
	afterList, _ := after.body["plans"].([]any)
	afterFirst, _ := afterList[0].(map[string]any)
	if afterFirst["price"] != originalPrice || afterFirst["daily_message_limit"] != originalLimit {
		t.Fatalf("the demo edit changed the production plan: %v", afterFirst)
	}

	if got := h.do(http.MethodPost, "/api/v1/simulator/admin/plan-draft/reset",
		map[string]any{}, headers); got.status != http.StatusOK {
		t.Fatalf("draft reset: %d %s", got.status, got.raw)
	}
}

// TestSimulatorAdminOverviewShowsOnlySeededUsers — нақты клиент дерегі шықпайды.
func TestSimulatorAdminOverviewShowsOnlySeededUsers(t *testing.T) {
	h := newHarness(t)
	// Нақты қолданушы жасаймыз: ол тізімде көрінбеуі керек.
	real := h.signIn("+77015550101")
	_ = real

	session := h.signInSimulator()
	overview := h.do(http.MethodGet, "/api/v1/simulator/admin/overview", nil,
		session.headers(h.cfg.Admin.CookieName))
	if overview.status != http.StatusOK {
		t.Fatalf("overview: %d %s", overview.status, overview.raw)
	}
	body := string(overview.raw)
	if strings.Contains(body, "77015550101") {
		t.Fatal("a real phone number reached the simulator's admin view")
	}
	users, _ := overview.body["users"].([]any)
	if len(users) == 0 {
		t.Fatal("no demo users returned")
	}
	for _, item := range users {
		row, _ := item.(map[string]any)
		if row["source"] != "demo" {
			t.Fatalf("a user row is not flagged as demo: %v", row)
		}
	}
	metrics, _ := overview.body["metrics"].(map[string]any)
	if metrics["source"] != "demo" {
		t.Fatal("dashboard metrics are not flagged as demo")
	}
}

// TestSimulatorRequiresCSRFOnWrites — cookie жеткіліксіз.
func TestSimulatorRequiresCSRFOnWrites(t *testing.T) {
	h := newHarness(t)
	session := h.signInSimulator()
	onlyCookie := map[string]string{"Cookie": h.cfg.Admin.CookieName + "=" + session.cookie}

	for _, path := range []string{
		"/api/v1/simulator/generate",
		"/api/v1/simulator/account/profile",
		"/api/v1/simulator/admin/plan-draft",
	} {
		got := h.do(http.MethodPost, path, map[string]any{"source_text": "x"}, onlyCookie)
		if got.status != http.StatusForbidden {
			t.Fatalf("%s: expected 403 without a CSRF token, got %d", path, got.status)
		}
	}
}

// TestSimulatorDoesNotPretendToTranscribe — жоқ мүмкіндік бар болып көрінбейді.
func TestSimulatorDoesNotPretendToTranscribe(t *testing.T) {
	h := newHarness(t)
	session := h.signInSimulator()
	got := h.do(http.MethodPost, "/api/v1/simulator/transcribe", map[string]any{},
		session.headers(h.cfg.Admin.CookieName))
	if got.status != http.StatusNotImplemented || got.errorCode() != "TRANSCRIPTION_NOT_IMPLEMENTED" {
		t.Fatalf("expected an honest 501, got %d %s", got.status, got.raw)
	}
}

// TestSimulatorHeadersOpenTheMicrophoneOnlyThere — микрофон тек симуляторда.
func TestSimulatorHeadersOpenTheMicrophoneOnlyThere(t *testing.T) {
	h := newHarness(t)
	session := h.signInSimulator()

	sim := h.do(http.MethodGet, "/simulator", nil,
		map[string]string{"Cookie": h.cfg.Admin.CookieName + "=" + session.cookie})
	if got := sim.header.Get("Permissions-Policy"); !strings.Contains(got, "microphone=(self)") {
		t.Fatalf("the simulator should be allowed the microphone, got %q", got)
	}
	if got := sim.header.Get("Content-Security-Policy"); !strings.Contains(got, "script-src 'self' 'unsafe-eval'") {
		t.Fatalf("the simulator needs Vue's runtime compiler, got %q", got)
	}

	landing := h.do(http.MethodGet, "/", nil, nil)
	if got := landing.header.Get("Permissions-Policy"); !strings.Contains(got, "microphone=()") {
		t.Fatalf("the landing page must keep the microphone closed, got %q", got)
	}
	if got := landing.header.Get("Content-Security-Policy"); strings.Contains(got, "unsafe-eval") {
		t.Fatalf("the landing page must keep the strict script policy, got %q", got)
	}
}
