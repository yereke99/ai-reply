package traits

// Page тізім сұраныстарының ортақ пішімі.
type Page struct {
	Limit  int
	Offset int
}

// NewPage шектерді қауіпсіз мәнге келтіреді.
func NewPage(limit, offset int) Page {
	if limit <= 0 || limit > 200 {
		limit = 25
	}
	if offset < 0 {
		offset = 0
	}
	return Page{Limit: limit, Offset: offset}
}
