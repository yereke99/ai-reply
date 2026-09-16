// Package migrations — схема миграциялары бинарге кіріктірілген.
package migrations

import "embed"

// FS — барлық .sql файлдары. Аты бойынша реттеліп орындалады.
//
//go:embed *.sql
var FS embed.FS
