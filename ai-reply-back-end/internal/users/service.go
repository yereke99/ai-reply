// Package users — профиль және құрылғылар.
package users

import (
	"context"
	"strings"

	"github.com/aireply/ai-reply-back-end/internal/domain"
	"github.com/aireply/ai-reply-back-end/internal/repository"
	"github.com/aireply/ai-reply-back-end/internal/traits"
)

// Service — қолданушы деректері.
type Service struct{ repo *repository.Store }

// New — қызмет.
func New(repo *repository.Store) *Service { return &Service{repo: repo} }

// Profile — профильді оқу.
func (s *Service) Profile(ctx context.Context, userID string) (domain.Profile, error) {
	return s.repo.Profile(ctx, userID)
}

// ProfileUpdate — тіркеуді аяқтау/өңдеу сұранысы.
type ProfileUpdate struct {
	DisplayName      *string
	Role             *string
	Description      *string
	PreferredTone    *string
	BusinessOffering *string
	BusinessSummary  *string
	BusinessRules    *[]string
	Locale           *string
	Timezone         *string
	Completed        *bool
}

// UpdateProfile — тек берілген өрістер өзгереді.
func (s *Service) UpdateProfile(ctx context.Context, userID string, in ProfileUpdate) (domain.Profile, error) {
	profile, err := s.repo.Profile(ctx, userID)
	if err != nil {
		return domain.Profile{}, err
	}
	profile.UserID = userID

	if in.DisplayName != nil {
		profile.DisplayName = traits.Clamp(*in.DisplayName, 80)
	}
	if in.Role != nil {
		profile.Role = traits.Clamp(*in.Role, 120)
	}
	if in.Description != nil {
		profile.Description = traits.Clamp(*in.Description, 1000)
	}
	if in.PreferredTone != nil {
		tone := strings.ToLower(strings.TrimSpace(*in.PreferredTone))
		if !traits.OneOf(tone, "natural", "friendly", "professional", "formal", "short") {
			return domain.Profile{}, domain.ErrInvalidRequest
		}
		profile.PreferredTone = tone
	}
	if in.BusinessOffering != nil {
		profile.BusinessOffering = traits.Clamp(*in.BusinessOffering, 120)
	}
	if in.BusinessSummary != nil {
		profile.BusinessSummary = traits.Clamp(*in.BusinessSummary, 400)
	}
	if in.BusinessRules != nil {
		rules := make([]string, 0, 8)
		for _, r := range *in.BusinessRules {
			if r = traits.Clamp(r, 200); r != "" {
				rules = append(rules, r)
			}
			if len(rules) == 8 {
				break
			}
		}
		profile.BusinessRules = rules
	}
	if in.Completed != nil {
		profile.OnboardingCompleted = *in.Completed
	}
	if err := s.repo.SaveProfile(ctx, profile); err != nil {
		return domain.Profile{}, err
	}

	if in.Locale != nil || in.Timezone != nil {
		locale, timezone := "", ""
		if in.Locale != nil {
			locale = domain.NormalizeLocale(*in.Locale)
		}
		if in.Timezone != nil {
			timezone = traits.Clamp(*in.Timezone, 64)
		}
		if err := s.repo.UpdateUserMeta(ctx, userID, "", "", "", locale, timezone); err != nil {
			return domain.Profile{}, err
		}
	}
	return profile, nil
}

// RegisterDevice — құрылғыны тіркеу (push негізі).
func (s *Service) RegisterDevice(ctx context.Context, d domain.Device) (domain.Device, error) {
	d.Platform = strings.ToLower(strings.TrimSpace(d.Platform))
	if d.Platform != "" && !traits.OneOf(d.Platform, domain.PlatformIOS, domain.PlatformAndroid, domain.PlatformWeb) {
		return domain.Device{}, domain.ErrInvalidRequest
	}
	d.AppVersion = traits.Clamp(d.AppVersion, 32)
	d.OSVersion = traits.Clamp(d.OSVersion, 32)
	d.Model = traits.Clamp(d.Model, 64)
	d.PushToken = traits.Clamp(d.PushToken, 512)
	return s.repo.UpsertDevice(ctx, d)
}

// Devices — қолданушының құрылғылары.
func (s *Service) Devices(ctx context.Context, userID string) ([]domain.Device, error) {
	return s.repo.DevicesByUser(ctx, userID)
}

// RemoveDevice — құрылғыны өшіру.
func (s *Service) RemoveDevice(ctx context.Context, userID, deviceID string) error {
	return s.repo.RevokeDevice(ctx, userID, deviceID)
}
