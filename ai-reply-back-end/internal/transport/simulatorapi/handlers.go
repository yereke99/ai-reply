package simulatorapi

import (
	"net/http"
	"time"

	"github.com/aireply/ai-reply-back-end/internal/domain"
	"github.com/aireply/ai-reply-back-end/internal/simulator"
	"github.com/aireply/ai-reply-back-end/internal/traits"
	"github.com/aireply/ai-reply-back-end/internal/transport/httpx"
	"github.com/aireply/ai-reply-back-end/internal/users"
)

// ---------------------------------------------------------------- bootstrap

func (s *Server) handleBootstrap(w http.ResponseWriter, r *http.Request) {
	snapshot, err := s.sim.Account(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	planList, err := s.sim.Plans(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	adminUser := adminFrom(r.Context())
	httpx.JSON(w, http.StatusOK, map[string]any{
		"admin": map[string]any{
			"id": adminUser.ID, "email": adminUser.Email, "name": adminUser.Name, "role": adminUser.Role,
		},
		"csrf":    sessionFrom(r.Context()).CSRFToken,
		"account": accountPayload(snapshot, s.sim.Timezone()),
		"plans":   planPayloads(planList),
		"health":  healthPayload(s.sim.Health(r.Context())),
	})
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	httpx.JSON(w, http.StatusOK, healthPayload(s.sim.Health(r.Context())))
}

// ---------------------------------------------------------------- аккаунт

func (s *Server) handleAccount(w http.ResponseWriter, r *http.Request) {
	snapshot, err := s.sim.Account(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, accountPayload(snapshot, s.sim.Timezone()))
}

type profileBody struct {
	DisplayName      *string   `json:"display_name"`
	Role             *string   `json:"role"`
	Description      *string   `json:"description"`
	PreferredTone    *string   `json:"preferred_tone"`
	BusinessOffering *string   `json:"business_offering"`
	BusinessSummary  *string   `json:"business_summary"`
	BusinessRules    *[]string `json:"business_rules"`
	Locale           *string   `json:"locale"`
	Completed        *bool     `json:"onboarding_completed"`
}

func (s *Server) handleSaveProfile(w http.ResponseWriter, r *http.Request) {
	var body profileBody
	if err := httpx.Decode(w, r, s.cfg.Limits.RequestBodyBytes, &body); err != nil {
		httpx.Fail(w, err)
		return
	}
	snapshot, err := s.sim.SaveProfile(r.Context(), users.ProfileUpdate{
		DisplayName: body.DisplayName, Role: body.Role, Description: body.Description,
		PreferredTone: body.PreferredTone, BusinessOffering: body.BusinessOffering,
		BusinessSummary: body.BusinessSummary, BusinessRules: body.BusinessRules,
		Locale: body.Locale, Completed: body.Completed,
	})
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, accountPayload(snapshot, s.sim.Timezone()))
}

func (s *Server) handleSetPlan(w http.ResponseWriter, r *http.Request) {
	var body struct {
		PlanID string `json:"plan_id"`
	}
	if err := httpx.Decode(w, r, 1024, &body); err != nil {
		httpx.Fail(w, err)
		return
	}
	snapshot, err := s.sim.AssignPlan(r.Context(), body.PlanID)
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, accountPayload(snapshot, s.sim.Timezone()))
}

func (s *Server) handleReset(w http.ResponseWriter, r *http.Request) {
	snapshot, err := s.sim.ResetAccount(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, accountPayload(snapshot, s.sim.Timezone()))
}

func (s *Server) handleResetQuota(w http.ResponseWriter, r *http.Request) {
	snapshot, err := s.sim.ResetQuota(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, accountPayload(snapshot, s.sim.Timezone()))
}

// ---------------------------------------------------------------- генерация

type generateBody struct {
	SourceText  string        `json:"source_text"`
	Instruction string        `json:"instruction"`
	Language    string        `json:"language"`
	TemplateID  string        `json:"template_id"`
	Platform    string        `json:"platform"`
	Override    *overrideBody `json:"override"`
}

type overrideBody struct {
	Description      string   `json:"description"`
	Role             string   `json:"role"`
	Tone             string   `json:"preferred_tone"`
	BusinessOffering string   `json:"business_offering"`
	BusinessSummary  string   `json:"business_summary"`
	BusinessRules    []string `json:"business_rules"`
}

func (s *Server) handleGenerate(w http.ResponseWriter, r *http.Request) {
	started := time.Now()
	var body generateBody
	if err := httpx.Decode(w, r, s.cfg.Limits.RequestBodyBytes, &body); err != nil {
		httpx.Fail(w, err)
		return
	}

	input := simulator.GenerateInput{
		SourceText:  body.SourceText,
		Instruction: body.Instruction,
		Language:    body.Language,
		TemplateID:  body.TemplateID,
		Platform:    body.Platform,
	}
	if body.Override != nil {
		input.Override = &simulator.Override{
			Description:      body.Override.Description,
			Role:             body.Override.Role,
			Tone:             body.Override.Tone,
			BusinessOffering: body.Override.BusinessOffering,
			BusinessSummary:  body.Override.BusinessSummary,
			BusinessRules:    body.Override.BusinessRules,
		}
	}

	result, limit, err := s.sim.Generate(r.Context(), input)
	if err != nil {
		status, code, message := httpx.Translate(err)
		var details map[string]any
		if code == httpx.CodeDailyLimit || code == httpx.CodeMonthlyLimit {
			details = map[string]any{
				"daily_limit": limit.DailyLimit,
				"used_today":  limit.UsedToday,
				"resets_at":   limit.ResetsAt.Format(time.RFC3339),
			}
		}
		httpx.Error(w, status, code, message, details)
		return
	}

	// Із әдейі сұйылтылған: тақырыптар да, токендер де, кілт те жоқ.
	httpx.JSON(w, http.StatusOK, map[string]any{
		"reply":             result.Reply,
		"detected_language": result.DetectedLanguage,
		"usage":             usagePayload(result.Entitlement, s.sim.Timezone()),
		"trace": map[string]any{
			"endpoint":       "POST /api/v1/simulator/generate",
			"downstream":     "POST /api/v1/ai/reply → OpenAI Responses API",
			"model":          result.Model,
			"prompt_blocks":  result.Trace,
			"input_tokens":   result.InputTokens,
			"output_tokens":  result.OutputTokens,
			"provider_ms":    result.LatencyMS,
			"round_trip_ms":  int(time.Since(started).Milliseconds()),
			"source_chars":   traits.RuneLen(body.SourceText),
			"instruction_ch": traits.RuneLen(body.Instruction),
			"stored_text":    false,
		},
	})
}

// handleTranscribe — сервер жағындағы сөйлеуді тану әлі жоқ.
//
// Android қосымшасында тану құрылғының өзінде жүреді (SpeechRecognizer), ал
// бэкендте ондай эндпоинт жоқ. Жоқ нәрсені бар етіп көрсетпейміз: бұл жерде
// нақты код қайтарылады, ал симулятор браузердің өз танушысына ауысады.
func (s *Server) handleTranscribe(w http.ResponseWriter, r *http.Request) {
	httpx.Error(w, http.StatusNotImplemented, "TRANSCRIPTION_NOT_IMPLEMENTED",
		"Server-side speech recognition is not part of the backend. "+
			"Recognition runs on the device, exactly as it does in the Android app.",
		map[string]any{"on_device": true})
}

// ---------------------------------------------------------------- әкімші демо

func (s *Server) handleAdminOverview(w http.ResponseWriter, r *http.Request) {
	planList, err := s.sim.Plans(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	snapshot, err := s.sim.Account(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	metrics := simulator.Metrics()
	drafts := s.sim.Drafts()

	httpx.JSON(w, http.StatusOK, map[string]any{
		// Нақты: тариф каталогы, демонстрация аккаунтының квотасы, жүйе күйі.
		"plans":        planPayloadsWithDrafts(planList, drafts),
		"demo_account": accountPayload(snapshot, s.sim.Timezone()),
		"health":       healthPayload(s.sim.Health(r.Context())),
		// Демо: тізім де, графиктер де ойдан шығарылған.
		"metrics": map[string]any{
			"source":          "demo",
			"total_users":     metrics.TotalUsers,
			"new_today":       metrics.NewToday,
			"active_month":    metrics.ActiveMonth,
			"requests_today":  metrics.RequestsToday,
			"success_rate":    metrics.SuccessRate,
			"average_latency": metrics.AverageLatency,
			"tokens_month":    metrics.TokensMonth,
			"estimated_cost":  metrics.EstimatedCost,
			"paid_users":      metrics.PaidUsers,
			"free_users":      metrics.FreeUsers,
			"ios_users":       metrics.IOSUsers,
			"android_users":   metrics.AndroidUsers,
			"generations":     seriesPayload(metrics.Generations),
			"registrations":   seriesPayload(metrics.Registrations),
			"plan_mix":        seriesPayload(metrics.PlanMix),
			"platform_mix":    seriesPayload(metrics.PlatformMix),
			"language_mix":    seriesPayload(metrics.LanguageMix),
		},
		"users": demoUsersPayload(),
	})
}

type draftBody struct {
	PlanID       string `json:"plan_id"`
	Price        int64  `json:"price"`
	DailyLimit   int    `json:"daily_message_limit"`
	MonthlyLimit int    `json:"monthly_message_limit"`
	PeriodDays   int    `json:"period_days"`
}

func (s *Server) handleSaveDraft(w http.ResponseWriter, r *http.Request) {
	var body draftBody
	if err := httpx.Decode(w, r, 2048, &body); err != nil {
		httpx.Fail(w, err)
		return
	}
	if _, err := s.sim.SaveDraft(r.Context(), simulator.PlanDraft{
		PlanID: body.PlanID, Price: body.Price, DailyLimit: body.DailyLimit,
		MonthlyLimit: body.MonthlyLimit, PeriodDays: body.PeriodDays,
	}); err != nil {
		httpx.Fail(w, err)
		return
	}
	planList, err := s.sim.Plans(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"plans": planPayloadsWithDrafts(planList, s.sim.Drafts()),
		"scope": "demo",
	})
}

func (s *Server) handleResetDrafts(w http.ResponseWriter, r *http.Request) {
	s.sim.ClearDrafts()
	planList, err := s.sim.Plans(r.Context())
	if err != nil {
		httpx.Fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"plans": planPayloadsWithDrafts(planList, s.sim.Drafts()),
		"scope": "demo",
	})
}

// ---------------------------------------------------------------- payloads

func accountPayload(s simulator.Snapshot, tz string) map[string]any {
	rules := s.Profile.BusinessRules
	if rules == nil {
		rules = []string{}
	}
	return map[string]any{
		"id":    s.User.ID,
		"label": simulator.AccountLabel,
		"kind":  simulator.AccountKind,
		"profile": map[string]any{
			"display_name":         s.Profile.DisplayName,
			"role":                 s.Profile.Role,
			"description":          s.Profile.Description,
			"preferred_tone":       s.Profile.PreferredTone,
			"business_offering":    s.Profile.BusinessOffering,
			"business_summary":     s.Profile.BusinessSummary,
			"business_rules":       rules,
			"onboarding_completed": s.Profile.OnboardingCompleted,
		},
		"locale":       s.User.Locale,
		"subscription": subscriptionPayload(s.Entitlement),
		"usage":        usagePayload(s.Entitlement, tz),
	}
}

func subscriptionPayload(e domain.Entitlement) map[string]any {
	out := map[string]any{
		"plan":   planPayload(e.Plan),
		"status": "none",
	}
	if e.Subscription != nil {
		out["status"] = e.Subscription.Status
		out["source"] = e.Subscription.Source
		out["started_at"] = e.Subscription.StartedAt.Format(time.RFC3339)
		if e.Subscription.ExpiresAt != nil {
			out["expires_at"] = e.Subscription.ExpiresAt.Format(time.RFC3339)
		}
	}
	return out
}

func usagePayload(e domain.Entitlement, tz string) map[string]any {
	return map[string]any{
		"daily_limit":     e.DailyLimit,
		"used_today":      e.UsedToday,
		"remaining_today": e.Remaining(),
		"monthly_limit":   e.MonthlyLimit,
		"used_month":      e.UsedMonth,
		"resets_at":       e.ResetsAt.Format(time.RFC3339),
		"timezone":        tz,
	}
}

func planPayload(p domain.Plan) map[string]any {
	return map[string]any{
		"id":                    p.ID,
		"code":                  p.Code,
		"name":                  p.Name,
		"description":           p.Description,
		"price":                 p.Price,
		"price_text":            traits.FormatMoney(p.Price, p.Currency),
		"currency":              p.Currency,
		"daily_message_limit":   p.DailyLimit,
		"monthly_message_limit": p.MonthlyLimit,
		"period_days":           p.PeriodDays,
		"is_free":               p.IsFree,
		"is_active":             p.IsActive,
		"sort_order":            p.SortOrder,
	}
}

func planPayloads(list []domain.Plan) []map[string]any {
	out := make([]map[string]any, 0, len(list))
	for _, p := range list {
		out = append(out, planPayload(p))
	}
	return out
}

// planPayloadsWithDrafts — нақты тариф + демо қабаттағы өзгеріс қатар тұрады,
// сондықтан көрсетілім кезінде қайсысы нақты екені анық көрінеді.
func planPayloadsWithDrafts(list []domain.Plan, drafts map[string]simulator.PlanDraft) []map[string]any {
	out := make([]map[string]any, 0, len(list))
	for _, p := range list {
		item := planPayload(p)
		if draft, ok := drafts[p.ID]; ok {
			item["draft"] = map[string]any{
				"price":                 draft.Price,
				"price_text":            traits.FormatMoney(draft.Price, p.Currency),
				"daily_message_limit":   draft.DailyLimit,
				"monthly_message_limit": draft.MonthlyLimit,
				"period_days":           draft.PeriodDays,
				"updated_at":            draft.UpdatedAt.Format(time.RFC3339),
				"scope":                 "demo",
			}
		}
		out = append(out, item)
	}
	return out
}

func healthPayload(h simulator.Health) map[string]any {
	return map[string]any{
		"database":            h.Database,
		"provider_configured": h.ProviderConfigured,
		"model":               h.Model,
		"env":                 h.Env,
		"timezone":            h.Timezone,
		"payment_mode":        h.PaymentMode,
		"demo_auth":           h.DemoAuth,
		"legacy_api":          h.LegacyAPI,
		"limits": map[string]any{
			"source_text_chars": h.SourceTextChars,
			"instruction_chars": h.InstructionChars,
			"ai_per_minute":     h.AIPerMinute,
		},
		"checked_at": h.CheckedAt.Format(time.RFC3339),
	}
}

func seriesPayload(points []simulator.DemoSeries) []map[string]any {
	out := make([]map[string]any, 0, len(points))
	for _, p := range points {
		out = append(out, map[string]any{"label": p.Label, "value": p.Value})
	}
	return out
}

func demoUsersPayload() []map[string]any {
	list := simulator.DemoUsers()
	out := make([]map[string]any, 0, len(list))
	for _, u := range list {
		events := make([]map[string]any, 0, len(u.Events))
		for _, e := range u.Events {
			events = append(events, map[string]any{
				"at": e.At, "status": e.Status, "platform": e.Platform, "language": e.Language,
				"tokens": e.Tokens, "latency_ms": e.LatencyMS, "error_code": e.ErrorCode,
			})
		}
		out = append(out, map[string]any{
			"id": u.ID, "label": u.Label, "identifier": u.Identifier, "plan_code": u.PlanCode,
			"sub_status": u.SubStatus, "used_today": u.UsedToday, "daily_limit": u.DailyLimit,
			"tokens_month": u.TokensMonth, "platform": u.Platform, "app_version": u.AppVersion,
			"locale": u.Locale, "tone": u.Tone, "business": u.Business,
			"registered": u.Registered, "last_active": u.LastActive, "status": u.Status,
			"events": events, "source": "demo",
		})
	}
	return out
}
