package traits

import (
	"strings"
	"unicode"
)

// RuneLen Unicode таңбаларын санайды (Swift String.count-пен бірдей мағына).
func RuneLen(s string) int { return len([]rune(s)) }

// Clamp мәтінді кесіп, шектен асырмайды.
func Clamp(s string, max int) string {
	s = strings.TrimSpace(s)
	if max <= 0 || RuneLen(s) <= max {
		return s
	}
	return string([]rune(s)[:max])
}

// CollapseSpaces артық бос орындарды жинайды.
func CollapseSpaces(s string) string {
	return strings.Join(strings.FieldsFunc(s, unicode.IsSpace), " ")
}

// MaskIdentifier телефон/поштаны әкімші панелінде көрсетуге жарамды түрге келтіреді.
func MaskIdentifier(value string) string {
	if value == "" {
		return ""
	}
	if at := strings.IndexByte(value, '@'); at > 0 {
		name := value[:at]
		if len(name) <= 2 {
			return "*@" + value[at+1:]
		}
		return name[:1] + strings.Repeat("*", len(name)-2) + name[len(name)-1:] + value[at:]
	}
	r := []rune(value)
	if len(r) <= 4 {
		return strings.Repeat("*", len(r))
	}
	return string(r[:len(r)-6]) + "***" + string(r[len(r)-2:])
}

// OneOf мәннің рұқсат етілген жиында болуын тексереді.
func OneOf(value string, allowed ...string) bool {
	for _, a := range allowed {
		if value == a {
			return true
		}
	}
	return false
}

// FormatMoney — ең кіші бірліктегі бағаны адам оқитын түрге келтіреді.
func FormatMoney(amount int64, currency string) string {
	if amount == 0 {
		return "0"
	}
	whole := amount / 100
	cents := amount % 100
	out := groupThousands(whole)
	if cents != 0 {
		out += "." + string(rune('0'+cents/10)) + string(rune('0'+cents%10))
	}
	if currency != "" {
		out += " " + currency
	}
	return out
}

func groupThousands(v int64) string {
	sign := ""
	if v < 0 {
		sign, v = "-", -v
	}
	digits := []byte{}
	for v > 0 {
		digits = append([]byte{byte('0' + v%10)}, digits...)
		v /= 10
	}
	if len(digits) == 0 {
		return sign + "0"
	}
	var out []byte
	for i, d := range digits {
		if i > 0 && (len(digits)-i)%3 == 0 {
			out = append(out, ' ')
		}
		out = append(out, d)
	}
	return sign + string(out)
}
