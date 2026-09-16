package auth

import (
	"context"
	"errors"
	"log/slog"
)

// Destination — кодты қайда жіберу керек.
type Destination struct {
	Kind    string // phone | email
	Value   string // E.164 немесе email
	Country string
	Locale  string
}

// Sender — OTP жеткізу арнасы.
//
// The demo ships with a stub. Plugging in a real provider (SMS aggregator,
// WhatsApp Business API, transactional email) means writing one implementation
// of this interface and registering it in NewSender — no other file changes.
type Sender interface {
	Channel() string
	Send(ctx context.Context, dst Destination, code string) error
}

// ErrSenderUnavailable — нақты провайдер әлі қосылмаған.
var ErrSenderUnavailable = errors.New("auth: otp sender is not configured")

// StubSender — демо режимі: ештеңе жібермейді, кодты ешқашан жазбайды.
type StubSender struct{ Log *slog.Logger }

// Channel — арна аты.
func (StubSender) Channel() string { return "stub" }

// Send — жеткізу жоқ; тек оқиға белгіленеді (кодсыз).
func (s StubSender) Send(_ context.Context, dst Destination, _ string) error {
	if s.Log != nil {
		s.Log.Info("otp issued", "channel", "stub", "kind", dst.Kind, "country", dst.Country)
	}
	return nil
}

// UnavailableSender — арна таңдалған, бірақ адаптер жоқ. Жалған «сәтті» жауап бермейді.
type UnavailableSender struct{ Name string }

// Channel — арна аты.
func (u UnavailableSender) Channel() string { return u.Name }

// Send — әрқашан қате: жеткізілмеген хабарды жеткізілді деп көрсетпейміз.
func (u UnavailableSender) Send(context.Context, Destination, string) error {
	return ErrSenderUnavailable
}

// NewSender — арна атауы бойынша жеткізушіні таңдайды.
//
// sms/whatsapp/email нұсқалары әдейі «қолжетімсіз» күйінде: нақты интеграция
// қосылғанда осы жерге бір жол қосылады.
func NewSender(channel string, log *slog.Logger) Sender {
	switch channel {
	case "stub", "":
		return StubSender{Log: log}
	default:
		return UnavailableSender{Name: channel}
	}
}
