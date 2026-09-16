// Package traits — жоба бойынша қайталанатын ұсақ көмекші мінез-құлықтар.
package traits

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
)

// NewID RFC 4122 v4 UUID қайтарады (домендік нысандардың бірегей идентификаторы).
func NewID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic("traits: entropy unavailable: " + err.Error())
	}
	b[6] = (b[6] & 0x0f) | 0x40 // version 4
	b[8] = (b[8] & 0x3f) | 0x80 // variant RFC 4122
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// RandomToken қайтарымсыз кездейсоқ токен (refresh, сессия, CSRF үшін).
func RandomToken(size int) string {
	if size <= 0 {
		size = 32
	}
	b := make([]byte, size)
	if _, err := rand.Read(b); err != nil {
		panic("traits: entropy unavailable: " + err.Error())
	}
	return hex.EncodeToString(b)
}
