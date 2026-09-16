package web

import (
	"encoding/json"
	"html/template"
	"net/http"
	"strings"
	"time"

	"github.com/aireply/ai-reply-back-end/internal/domain"
	"github.com/aireply/ai-reply-back-end/internal/localization"
	"github.com/aireply/ai-reply-back-end/internal/traits"
	"github.com/aireply/ai-reply-back-end/internal/transport/httpx"
)

func clientIP(r *http.Request, trustProxy bool) string { return httpx.ClientIP(r, trustProxy) }

type planView struct {
	Name        string
	Description string
	PriceText   string
	DailyLimit  int
	IsFree      bool
	Featured    bool
}

type landingView struct {
	baseView
	Plans []planView
	Boot  template.JS
}

// demoScene — лендингтегі анимацияланған мысал.
type demoScene struct {
	Incoming         string `json:"incoming"`
	Instruction      string `json:"instruction"`
	Reply            string `json:"reply"`
	LabelIncoming    string `json:"labelIncoming"`
	LabelInstruction string `json:"labelInstruction"`
	LabelReply       string `json:"labelReply"`
}

// demoScenes — үш сценарий: сатылым, кездесу, тапсырыс.
func (s *Server) demoScenes(locale string) []demoScene {
	prefixes := []string{"hero.demo", "hero.demo2", "hero.demo3"}
	scenes := make([]demoScene, 0, len(prefixes))
	for _, prefix := range prefixes {
		scenes = append(scenes, demoScene{
			Incoming:         s.bundle.T(locale, prefix+"_incoming"),
			Instruction:      s.bundle.T(locale, prefix+"_instruction"),
			Reply:            s.bundle.T(locale, prefix+"_reply"),
			LabelIncoming:    s.bundle.T(locale, "hero.demo_label_incoming"),
			LabelInstruction: s.bundle.T(locale, "hero.demo_label_instruction"),
			LabelReply:       s.bundle.T(locale, "hero.demo_label_reply"),
		})
	}
	return scenes
}

// handleLanding — басты бет.
func (s *Server) handleLanding(w http.ResponseWriter, r *http.Request) {
	locale := s.locale(w, r)
	list, err := s.plans.Active(r.Context())
	if err != nil {
		s.log.Error("landing plans failed", "error", err.Error())
	}

	boot, err := json.Marshal(map[string]any{"scenes": s.demoScenes(locale), "locale": locale})
	if err != nil {
		boot = []byte("{}")
	}
	view := landingView{baseView: s.base(locale), Boot: template.JS(boot)}
	for i, p := range list {
		view.Plans = append(view.Plans, planView{
			Name:        p.LocalizedName(locale),
			Description: p.LocalizedDescription(locale),
			PriceText:   traits.FormatMoney(p.Price, p.Currency),
			DailyLimit:  p.DailyLimit,
			IsFree:      p.IsFree,
			Featured:    i == 1,
		})
	}
	s.render(w, "landing", "public_layout", view)
}

type legalView struct {
	baseView
	Title   string
	Updated string
	Body    template.HTML
	Boot    template.JS
}

// handleTerms — пайдалану шарттары.
func (s *Server) handleTerms(w http.ResponseWriter, r *http.Request) {
	locale := s.locale(w, r)
	s.render(w, "legal", "public_layout", legalView{
		baseView: s.base(locale),
		Title:    s.bundle.T(locale, "legal.terms.title"),
		Updated:  time.Now().Format("2006-01-02"),
		Body:     template.HTML(termsBody(locale)),
		Boot:     template.JS("{}"),
	})
}

// handlePrivacy — құпиялық саясаты.
func (s *Server) handlePrivacy(w http.ResponseWriter, r *http.Request) {
	locale := s.locale(w, r)
	s.render(w, "legal", "public_layout", legalView{
		baseView: s.base(locale),
		Title:    s.bundle.T(locale, "legal.privacy.title"),
		Updated:  time.Now().Format("2006-01-02"),
		Body:     template.HTML(privacyBody(locale)),
		Boot:     template.JS("{}"),
	})
}

// locale — тілді анықтап, cookie-ге жазады.
func (s *Server) locale(w http.ResponseWriter, r *http.Request) string {
	locale := localization.Detect(r, "en")
	if r.URL.Query().Get("lang") != "" {
		localization.SetCookie(w, locale, s.cfg.App.IsProduction())
	}
	return domain.NormalizeLocale(locale)
}

// Заң мәтіндері — демо нұсқасы. Нақты жариялау алдында заңгермен келісіледі.
func termsBody(locale string) string {
	sections := map[string][][2]string{
		"kk": {
			{"Қызмет туралы", "AI Reply — мессенджерлерде жауап жазуға көмектесетін мобильді қосымша және пернетақта. Қызмет «қалай бар, солай» ұсынылады."},
			{"Есептік жазба", "Тіркелу телефон нөмірі немесе электрондық пошта арқылы жүреді. Есептік жазбаңыздың қауіпсіздігі үшін жауапкершілік сізде."},
			{"Лимиттер мен тарифтер", "Әр тарифте күндік генерация лимиті бар. Лимит сервер уақыт белдеуі бойынша тәулік сайын жаңарады."},
			{"Жауапкершілік", "Жасалған мәтін — ұсыныс. Жіберер алдында оны өзіңіз тексересіз; мазмұн үшін жауапкершілік жіберушіде."},
			{"Өзгерістер", "Шарттар жаңарғанда бет жаңартылады. Қызметті пайдалануды жалғастыру жаңа редакцияны қабылдағаныңызды білдіреді."},
		},
		"ru": {
			{"О сервисе", "AI Reply — мобильное приложение и клавиатура, которые помогают писать ответы в мессенджерах. Сервис предоставляется «как есть»."},
			{"Аккаунт", "Регистрация выполняется по номеру телефона или электронной почте. Ответственность за сохранность доступа к аккаунту лежит на вас."},
			{"Лимиты и тарифы", "У каждого тарифа есть дневной лимит генераций. Лимит обновляется ежедневно по часовому поясу сервера."},
			{"Ответственность", "Сгенерированный текст — это черновик. Вы проверяете его перед отправкой; ответственность за содержание несёт отправитель."},
			{"Изменения", "При обновлении условий эта страница изменяется. Продолжение использования означает согласие с новой редакцией."},
		},
		"en": {
			{"About the service", "AI Reply is a mobile app and keyboard that helps you write replies in messengers. The service is provided as is."},
			{"Account", "You sign in with a phone number or an email address. Keeping access to your account safe is your responsibility."},
			{"Limits and plans", "Every plan has a daily generation limit. The limit resets each day in the server's timezone."},
			{"Responsibility", "A generated reply is a draft. You review it before sending; the sender remains responsible for the content."},
			{"Changes", "This page is updated when the terms change. Continued use means you accept the current version."},
		},
		"uz": {
			{"Xizmat haqida", "AI Reply — messenjerlarda javob yozishga yordam beradigan mobil ilova va klaviatura. Xizmat «qanday boʻlsa, shundayligicha» taqdim etiladi."},
			{"Hisob", "Roʻyxatdan oʻtish telefon raqami yoki elektron pochta orqali amalga oshiriladi. Hisobingiz xavfsizligi uchun javobgarlik sizda."},
			{"Limitlar va tariflar", "Har bir tarifda kunlik generatsiya limiti bor. Limit server vaqt mintaqasi boʻyicha har kuni yangilanadi."},
			{"Javobgarlik", "Yaratilgan matn — qoralama. Yuborishdan oldin uni oʻzingiz tekshirasiz; mazmun uchun javobgarlik yuboruvchida."},
			{"Oʻzgarishlar", "Shartlar yangilanganda bu sahifa oʻzgaradi. Foydalanishni davom ettirish yangi tahrirni qabul qilganingizni bildiradi."},
		},
	}
	return renderSections(sections, locale)
}

func privacyBody(locale string) string {
	sections := map[string][][2]string{
		"kk": {
			{"Не жинаймыз", "Есептік жазба деректері (телефон нөмірі не пошта), тариф, күндік санағыш, техникалық метадерек: платформа, қосымша нұсқасы, сұраныс уақыты мен ұзақтығы, токен саны."},
			{"Нені жинамаймыз", "Көшірілген хабарлама мәтіні, жасалған жауап, дауыстық танудың мазмұны, контакт тізімі, геолокация, жарнама идентификаторлары сақталмайды."},
			{"Мәтін қалай өңделеді", "Жауап жазу үшін мәтін серверде тек сол сұраныс кезінде жадта болады және AI провайдеріне жіберіледі. Ол дерекқорға да, журналға да жазылмайды."},
			{"Кім көре алады", "Әкімші панелінде хабарлама мазмұны жоқ — тек метадерек. Мұндай функция әдейі жасалмаған."},
			{"Деректі жою", "Есептік жазбаны жою сұранысы бойынша қолданушының жазбалары мен санағыштары жойылады."},
		},
		"ru": {
			{"Что мы собираем", "Данные аккаунта (телефон или почта), тариф, дневной счётчик, технические метаданные: платформа, версия приложения, время и длительность запроса, число токенов."},
			{"Что мы не собираем", "Текст скопированного сообщения, сгенерированный ответ, содержимое распознанной речи, список контактов, геолокацию и рекламные идентификаторы."},
			{"Как обрабатывается текст", "Для генерации текст находится в памяти сервера только во время запроса и передаётся AI-провайдеру. В базу и логи он не попадает."},
			{"Кто имеет доступ", "В админ-панели нет содержимого сообщений — только метаданные. Такая функция намеренно не реализована."},
			{"Удаление данных", "По запросу на удаление аккаунта записи и счётчики пользователя удаляются."},
		},
		"en": {
			{"What we collect", "Account data (phone or email), plan, daily counter, and technical metadata: platform, app version, request time and duration, token counts."},
			{"What we do not collect", "The copied message, the generated reply, speech-recognition content, contact lists, location, and advertising identifiers."},
			{"How text is processed", "To write a reply, the text stays in server memory for the duration of the request and is passed to the AI provider. It is not written to the database or the logs."},
			{"Who can see it", "The admin panel holds no message content — only metadata. That capability is deliberately absent."},
			{"Deleting data", "On an account deletion request, the user's records and counters are removed."},
		},
		"uz": {
			{"Nimalarni yigʻamiz", "Hisob maʼlumotlari (telefon yoki pochta), tarif, kunlik hisoblagich, texnik metamaʼlumot: platforma, ilova versiyasi, soʻrov vaqti va davomiyligi, token soni."},
			{"Nimalarni yigʻmaymiz", "Nusxalangan xabar matni, yaratilgan javob, nutq tanish mazmuni, kontaktlar roʻyxati, geolokatsiya va reklama identifikatorlari."},
			{"Matn qanday qayta ishlanadi", "Javob yozish uchun matn faqat soʻrov davomida server xotirasida boʻladi va AI provayderiga uzatiladi. U bazaga ham, jurnalga ham yozilmaydi."},
			{"Kim koʻra oladi", "Admin panelda xabar mazmuni yoʻq — faqat metamaʼlumot. Bunday funksiya ataylab yaratilmagan."},
			{"Maʼlumotlarni oʻchirish", "Hisobni oʻchirish soʻroviga koʻra foydalanuvchining yozuvlari va hisoblagichlari oʻchiriladi."},
		},
	}
	return renderSections(sections, locale)
}

func renderSections(all map[string][][2]string, locale string) string {
	sections, ok := all[locale]
	if !ok {
		sections = all["en"]
	}
	var b strings.Builder
	for _, s := range sections {
		b.WriteString("<h2>")
		b.WriteString(template.HTMLEscapeString(s[0]))
		b.WriteString("</h2><p>")
		b.WriteString(template.HTMLEscapeString(s[1]))
		b.WriteString("</p>")
	}
	return b.String()
}
