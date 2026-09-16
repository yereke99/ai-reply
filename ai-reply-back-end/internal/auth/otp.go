package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"math/big"
	"net/mail"
	"strings"

	"github.com/aireply/ai-reply-back-end/internal/phone"
)

// Identity — нормаланған кіру идентификаторы.
type Identity struct {
	Kind    string // phone | email
	Value   string
	Country string
	Masked  string
}

// ParseIdentity — телефон (E.164, 12 ел) немесе email.
func ParseIdentity(raw string) (Identity, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return Identity{}, phone.ErrEmpty
	}
	if strings.Contains(trimmed, "@") {
		addr, err := mail.ParseAddress(trimmed)
		if err != nil {
			return Identity{}, err
		}
		value := strings.ToLower(addr.Address)
		return Identity{Kind: "email", Value: value, Masked: maskEmail(value)}, nil
	}
	num, err := phone.Parse(trimmed)
	if err != nil {
		return Identity{}, err
	}
	return Identity{Kind: "phone", Value: num.E164, Country: num.Country, Masked: maskPhone(num.E164)}, nil
}

// GenerateCode — 4 таңбалы кездейсоқ код (демо режимінде қолданылмайды).
func GenerateCode(length int) (string, error) {
	if length < 4 {
		length = 4
	}
	digits := make([]byte, length)
	for i := range digits {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			return "", err
		}
		digits[i] = byte('0' + n.Int64())
	}
	return string(digits), nil
}

// HashCode — кодты HMAC-пен хэштейді (ашық түрде ешқашан сақталмайды).
func HashCode(secret, kind, value, code string) string {
	sum := sha256.Sum256([]byte(secret + "|" + kind + "|" + value + "|" + code))
	return base64.RawStdEncoding.EncodeToString(sum[:])
}

// CompareCode — тұрақты уақытта салыстыру.
func CompareCode(expectedHash, actualHash string) bool {
	return subtle.ConstantTimeCompare([]byte(expectedHash), []byte(actualHash)) == 1
}

// LegacyClientID — ескі install_id-ден тұрақты, кері қайтарылмайтын идентификатор.
func LegacyClientID(secret, installID string) string {
	sum := sha256.Sum256([]byte(secret + "|install:" + installID))
	return hex.EncodeToString(sum[:])[:32]
}

func maskPhone(v string) string {
	if len(v) < 6 {
		return "***"
	}
	return v[:len(v)-6] + "***" + v[len(v)-2:]
}

func maskEmail(v string) string {
	at := strings.IndexByte(v, '@')
	if at <= 0 {
		return "***"
	}
	name := v[:at]
	if len(name) <= 2 {
		return "*" + v[at:]
	}
	return name[:1] + strings.Repeat("*", len(name)-2) + name[len(name)-1:] + v[at:]
}
