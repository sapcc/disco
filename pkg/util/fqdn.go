// SPDX-FileCopyrightText: 2025 SAP SE or an SAP affiliate company
// SPDX-License-Identifier: Apache-2.0

package controllers

import (
	"strings"
)

// EnsureFQDN ensures the given name has a trailing '.'
func EnsureFQDN(s string) string {
	if !strings.HasSuffix(s, ".") {
		return s + "."
	}
	return s
}
