package apptest

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/aireply/ai-reply-back-end/internal/domain"
)

// Симулятор мәтіні төрт тілде де толық болуы керек.
//
// Аударма табылмағанда bundle ағылшыншаға түседі, сондықтан «жетіспейтін кілт»
// браузерде тек кілттің өзі болып көрінеді — оны көзбен байқау қиын. Бұл тест
// екі нәрсені бірдей тексереді: JS-те қолданылған әрбір статикалық кілт бар ма,
// және динамикалық кілт отбасылары (қадамдар, сценарий, архитектура, тон, тур)
// толық па.

func loadLocale(t *testing.T, locale string) map[string]string {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "localization", "locales", locale+".json"))
	if err != nil {
		t.Fatalf("read %s: %v", locale, err)
	}
	var parsed map[string]string
	if err := json.Unmarshal(raw, &parsed); err != nil {
		t.Fatalf("parse %s: %v", locale, err)
	}
	return parsed
}

// staticKeys — симулятор кодындағы 'sim.*' жол тұрақтылары.
func staticKeys(t *testing.T) []string {
	t.Helper()
	pattern := regexp.MustCompile(`['"](sim\.[a-z0-9_.]+)['"]`)
	found := map[string]bool{}

	roots := []string{
		filepath.Join("..", "transport", "web", "static", "simulator"),
		filepath.Join("..", "transport", "web", "templates"),
	}
	for _, root := range roots {
		entries, err := os.ReadDir(root)
		if err != nil {
			t.Fatalf("read dir %s: %v", root, err)
		}
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			name := entry.Name()
			if !strings.HasSuffix(name, ".js") && !strings.HasPrefix(name, "simulator_") {
				continue
			}
			raw, err := os.ReadFile(filepath.Join(root, name))
			if err != nil {
				t.Fatalf("read %s: %v", name, err)
			}
			for _, match := range pattern.FindAllStringSubmatch(string(raw), -1) {
				key := match[1]
				// Біріктіріліп құралатын бөліктер (мысалы "sim.wf." + id)
				// бөлек тізімде тексеріледі.
				if strings.HasSuffix(key, ".") || strings.HasSuffix(key, "_") {
					continue
				}
				found[key] = true
			}
		}
	}

	out := make([]string, 0, len(found))
	for key := range found {
		out = append(out, key)
	}
	sort.Strings(out)
	return out
}

// dynamicKeys — кодта жолдарды қосу арқылы құралатын кілттер.
func dynamicKeys() []string {
	var keys []string
	add := func(prefix string, names []string, suffixes []string) {
		for _, name := range names {
			for _, suffix := range suffixes {
				keys = append(keys, prefix+name+suffix)
			}
		}
	}

	steps := []string{"welcome", "register", "verify", "setup", "preferences",
		"messenger", "keyboard", "voice", "insert"}
	add("sim.step.", steps, []string{"_nav", "_panel"})

	flow := []string{"account", "configure", "keyboard_on", "incoming", "copy", "open_kbd",
		"instruction", "request", "context", "openai", "return", "edit", "insert", "send",
		"generating", "draft"}
	add("sim.wf.", flow, []string{"_title", "_sub", "_body", "_system", "_component"})

	nodes := []string{"ios", "android", "transport", "auth", "limits", "context",
		"gateway", "openai", "storage", "admin"}
	add("sim.arch.", nodes, []string{"", "_sub", "_detail", "_where", "_never"})

	tones := []string{"natural", "friendly", "professional", "formal", "short"}
	add("sim.tone.", tones, []string{"", "_hint"})

	add("sim.prefs.audience_", []string{"retail", "business", "leads", "support", "mixed"}, []string{""})
	add("sim.template.", []string{"client", "business", "work", "friend"}, []string{""})
	add("sim.lang.", domain.Locales, []string{""})

	tour := []string{"configure", "incoming", "open", "instruction", "generate",
		"insert", "limits", "pricing", "usage"}
	add("sim.tour.", tour, []string{"_title", "_body"})

	anatomy := []string{"bar", "templates", "quote", "instruction", "mic", "generate", "draft", "insert"}
	add("sim.keyboard.", anatomy, []string{"a_", "b_"}) // орны ауысады, төменде түзетіледі
	keys = keys[:len(keys)-len(anatomy)*2]
	for _, name := range anatomy {
		keys = append(keys, "sim.keyboard.a_"+name, "sim.keyboard.b_"+name)
	}

	routes := []string{"overview", "ios", "android", "keyboard", "personalization",
		"workflow", "architecture", "screens", "admin", "pricing"}
	add("sim.nav.", routes, []string{""})
	add("sim.group.", []string{"product", "explain", "business"}, []string{""})

	return keys
}

func TestSimulatorTranslationsAreCompleteInEveryLocale(t *testing.T) {
	required := append(staticKeys(t), dynamicKeys()...)
	if len(required) < 200 {
		t.Fatalf("suspiciously few keys collected: %d", len(required))
	}

	for _, locale := range domain.Locales {
		messages := loadLocale(t, locale)
		var missing []string
		for _, key := range required {
			if strings.TrimSpace(messages[key]) == "" {
				missing = append(missing, key)
			}
		}
		if len(missing) > 0 {
			sort.Strings(missing)
			if len(missing) > 12 {
				missing = append(missing[:12], "…")
			}
			t.Fatalf("locale %s is missing %d simulator keys: %v", locale, len(missing), missing)
		}
	}
}

func TestSimulatorLocalesHaveTheSameKeys(t *testing.T) {
	base := loadLocale(t, "en")
	for _, locale := range domain.Locales {
		if locale == "en" {
			continue
		}
		other := loadLocale(t, locale)
		var missing, extra []string
		for key := range base {
			if _, ok := other[key]; !ok {
				missing = append(missing, key)
			}
		}
		for key := range other {
			if _, ok := base[key]; !ok {
				extra = append(extra, key)
			}
		}
		sort.Strings(missing)
		sort.Strings(extra)
		if len(missing) > 0 || len(extra) > 0 {
			t.Fatalf("locale %s drifted from en — missing %v, extra %v", locale, missing, extra)
		}
	}
}
