package phone

import "testing"

func TestParseValid(t *testing.T) {
	cases := map[string]struct{ e164, iso string }{
		"+7 701 123 45 67":   {"+77011234567", "KZ"},
		"87011234567":        {"+77011234567", "KZ"},
		"8 (777) 123-45-67":  {"+77771234567", "KZ"},
		"+7 912 345 67 89":   {"+79123456789", "RU"},
		"+998901234567":      {"+998901234567", "UZ"},
		"00998 90 123 45 67": {"+998901234567", "UZ"},
		"+996700123456":      {"+996700123456", "KG"},
		"+992901234567":      {"+992901234567", "TJ"},
		"+99365123456":       {"+99365123456", "TM"},
		"+994501234567":      {"+994501234567", "AZ"},
		"+995555123456":      {"+995555123456", "GE"},
		"+380501234567":      {"+380501234567", "UA"},
		"+375291234567":      {"+375291234567", "BY"},
		"+905321234567":      {"+905321234567", "TR"},
		"+971501234567":      {"+971501234567", "AE"},
	}
	for in, want := range cases {
		got, err := Parse(in)
		if err != nil {
			t.Fatalf("Parse(%q) error: %v", in, err)
		}
		if got.E164 != want.e164 || got.Country != want.iso {
			t.Fatalf("Parse(%q) = %+v, want %s/%s", in, got, want.e164, want.iso)
		}
	}
}

func TestParseInvalid(t *testing.T) {
	for _, in := range []string{"", "123", "+7 111 123 45 67", "+77011234", "+1 202 555 0143", "+998 12 345 67 89"} {
		if n, err := Parse(in); err == nil {
			t.Fatalf("Parse(%q) = %+v, want error", in, n)
		}
	}
}
