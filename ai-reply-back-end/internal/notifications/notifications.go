// Package notifications — push негізі. APNs/FCM әлі қосылмаған: жалған «жіберілді» жоқ.
package notifications

import (
	"context"
	"errors"

	"github.com/aireply/ai-reply-back-end/internal/domain"
	"github.com/aireply/ai-reply-back-end/internal/repository"
)

// ErrUnavailable — жеткізу арнасы қосылмаған.
var ErrUnavailable = errors.New("notifications: delivery channel is not configured")

// Message — жіберілетін хабар (мазмұны маркетингтік, жеке жазысу емес).
type Message struct {
	Title string
	Body  string
	Data  map[string]string
}

// Transport — APNs/FCM келісімшарты.
type Transport interface {
	Platform() string
	Available() bool
	Send(ctx context.Context, tokens []string, msg Message) error
}

// APNs — iOS арнасы (интеграция кейін).
type APNs struct{}

// Platform — платформа.
func (APNs) Platform() string { return domain.PlatformIOS }

// Available — әлі қосылмаған.
func (APNs) Available() bool { return false }

// Send — интеграциясыз жіберілмейді.
func (APNs) Send(context.Context, []string, Message) error { return ErrUnavailable }

// FCM — Android арнасы (интеграция кейін).
type FCM struct{}

// Platform — платформа.
func (FCM) Platform() string { return domain.PlatformAndroid }

// Available — әлі қосылмаған.
func (FCM) Available() bool { return false }

// Send — интеграциясыз жіберілмейді.
func (FCM) Send(context.Context, []string, Message) error { return ErrUnavailable }

// Service — құрылғы тізілімі және арналар күйі.
type Service struct {
	repo       *repository.Store
	transports []Transport
}

// New — қызмет.
func New(repo *repository.Store) *Service {
	return &Service{repo: repo, transports: []Transport{APNs{}, FCM{}}}
}

// Status — әкімші панеліне: қай арна дайын.
func (s *Service) Status() map[string]bool {
	out := map[string]bool{}
	for _, t := range s.transports {
		out[t.Platform()] = t.Available()
	}
	return out
}

// Send — арна дайын болмаса, ашық қате қайтарады.
func (s *Service) Send(ctx context.Context, platform string, tokens []string, msg Message) error {
	for _, t := range s.transports {
		if t.Platform() == platform {
			if !t.Available() {
				return ErrUnavailable
			}
			return t.Send(ctx, tokens, msg)
		}
	}
	return ErrUnavailable
}
