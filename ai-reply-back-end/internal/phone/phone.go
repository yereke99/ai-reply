// Package phone — телефон нөмірін E.164 стандартына келтіру және тексеру.
//
// Scope is deliberately narrow: the countries AI Reply actually serves. Each
// country declares its dial code, national-number length and the mobile
// prefixes that exist there, so a landline or a typo is rejected before an OTP
// is ever requested. Adding a country is one entry in the table below.
package phone

import (
	"errors"
	"strings"
)

// Number — тексерілген нөмір.
type Number struct {
	E164     string // +77011234567
	Country  string // KZ
	Dial     string // 7
	National string // 7011234567
}

// Country — бір елдің нөмір ережесі.
type Country struct {
	ISO      string
	Dial     string
	NSNLen   []int    // ұлттық нөмір ұзындығы (елдік кодсыз)
	Prefixes []string // мобильді операторлар префикстері; бос болса — кез келген
	Example  string
	NameEN   string
}

// Supported — қолдау көрсетілетін елдер. Тізімді кеңейту үшін жол қосу жеткілікті.
var Supported = []Country{
	{ISO: "KZ", Dial: "7", NSNLen: []int{10}, Example: "+7 701 123 45 67", NameEN: "Kazakhstan",
		Prefixes: []string{"700", "701", "702", "703", "704", "705", "706", "707", "708", "709",
			"747", "750", "751", "760", "761", "762", "763", "764",
			"771", "775", "776", "777", "778"}},
	{ISO: "RU", Dial: "7", NSNLen: []int{10}, Example: "+7 912 345 67 89", NameEN: "Russia",
		Prefixes: []string{"9"}},
	{ISO: "UZ", Dial: "998", NSNLen: []int{9}, Example: "+998 90 123 45 67", NameEN: "Uzbekistan",
		Prefixes: []string{"33", "50", "55", "77", "88", "90", "91", "93", "94", "95", "97", "98", "99"}},
	{ISO: "KG", Dial: "996", NSNLen: []int{9}, Example: "+996 700 123 456", NameEN: "Kyrgyzstan",
		Prefixes: []string{"22", "50", "51", "55", "56", "57", "70", "75", "77", "88", "99"}},
	{ISO: "TJ", Dial: "992", NSNLen: []int{9}, Example: "+992 90 123 45 67", NameEN: "Tajikistan",
		Prefixes: []string{"50", "55", "77", "88", "90", "91", "92", "93", "98"}},
	{ISO: "TM", Dial: "993", NSNLen: []int{8}, Example: "+993 65 123456", NameEN: "Turkmenistan",
		Prefixes: []string{"6"}},
	{ISO: "AZ", Dial: "994", NSNLen: []int{9}, Example: "+994 50 123 45 67", NameEN: "Azerbaijan",
		Prefixes: []string{"10", "50", "51", "55", "60", "70", "77", "99"}},
	{ISO: "GE", Dial: "995", NSNLen: []int{9}, Example: "+995 555 12 34 56", NameEN: "Georgia",
		Prefixes: []string{"5", "7"}},
	{ISO: "UA", Dial: "380", NSNLen: []int{9}, Example: "+380 50 123 45 67", NameEN: "Ukraine",
		Prefixes: []string{"39", "50", "63", "66", "67", "68", "73", "91", "92", "93", "94", "95", "96", "97", "98", "99"}},
	{ISO: "BY", Dial: "375", NSNLen: []int{9}, Example: "+375 29 123 45 67", NameEN: "Belarus",
		Prefixes: []string{"25", "29", "33", "44"}},
	{ISO: "TR", Dial: "90", NSNLen: []int{10}, Example: "+90 532 123 45 67", NameEN: "Türkiye",
		Prefixes: []string{"5"}},
	{ISO: "AE", Dial: "971", NSNLen: []int{9}, Example: "+971 50 123 4567", NameEN: "United Arab Emirates",
		Prefixes: []string{"50", "52", "54", "55", "56", "58"}},
}

var (
	// ErrEmpty — нөмір берілмеген.
	ErrEmpty = errors.New("phone: empty")
	// ErrCountryUnsupported — ел тізімде жоқ.
	ErrCountryUnsupported = errors.New("phone: country not supported")
	// ErrInvalid — ұзындығы не префиксі дұрыс емес.
	ErrInvalid = errors.New("phone: invalid number")
)

// digitsOnly тек цифрларды қалдырады.
func digitsOnly(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// Parse кез келген жазылу түрін (8 707..., 8-707..., +7 707..., 00 7 707...) E.164-ке келтіреді.
func Parse(raw string) (Number, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return Number{}, ErrEmpty
	}

	hadPlus := strings.HasPrefix(trimmed, "+")
	digits := digitsOnly(trimmed)
	if digits == "" {
		return Number{}, ErrInvalid
	}

	// 00 халықаралық префиксі.
	if !hadPlus && strings.HasPrefix(digits, "00") {
		digits = digits[2:]
	}
	// Посткеңестік «8» ұлттық префиксі: 8 707 ... -> 7 707 ...
	if !hadPlus && len(digits) == 11 && strings.HasPrefix(digits, "8") {
		digits = "7" + digits[1:]
	}

	// Ұзын кодтан қысқасына қарай сәйкестендіру (998, 996 ... содан кейін 7).
	candidates := byDialLengthDesc()
	for _, c := range candidates {
		if !strings.HasPrefix(digits, c.Dial) {
			continue
		}
		national := digits[len(c.Dial):]
		if !lengthAllowed(c, len(national)) {
			continue
		}
		if !prefixAllowed(c, national) {
			continue
		}
		return Number{E164: "+" + c.Dial + national, Country: c.ISO, Dial: c.Dial, National: national}, nil
	}

	// Ел табылды, бірақ нөмір қате болса — нақтырақ қате қайтарамыз.
	for _, c := range candidates {
		if strings.HasPrefix(digits, c.Dial) {
			return Number{}, ErrInvalid
		}
	}
	return Number{}, ErrCountryUnsupported
}

func lengthAllowed(c Country, n int) bool {
	for _, l := range c.NSNLen {
		if l == n {
			return true
		}
	}
	return false
}

func prefixAllowed(c Country, national string) bool {
	if len(c.Prefixes) == 0 {
		return true
	}
	for _, p := range c.Prefixes {
		if strings.HasPrefix(national, p) {
			return true
		}
	}
	return false
}

func byDialLengthDesc() []Country {
	out := make([]Country, len(Supported))
	copy(out, Supported)
	for i := 1; i < len(out); i++ {
		for j := i; j > 0 && len(out[j].Dial) > len(out[j-1].Dial); j-- {
			out[j], out[j-1] = out[j-1], out[j]
		}
	}
	return out
}

// Countries — UI үшін қолдау көрсетілетін елдер тізімі.
func Countries() []Country { return Supported }
