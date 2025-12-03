// SPDX-FileCopyrightText: 2025 SAP SE or an SAP affiliate company
// SPDX-License-Identifier: Apache-2.0

package controllers

import (
	"fmt"
	"slices"
	"unicode"

	"sigs.k8s.io/controller-runtime/pkg/client"
)

func makeAnnotation(prefix, annotationKey string) string {
	return fmt.Sprintf("%s/%s", prefix, annotationKey)
}

func isHandleObject(annotationKey string, o client.Object) bool {
	if o.GetAnnotations() == nil {
		return false
	}
	v, ok := o.GetAnnotations()[annotationKey]
	return ok && v == "true"
}

func appendIfNotContains(theStringSlice []string, theString string) []string {
	if slices.Contains(theStringSlice, theString) {
		return theStringSlice
	}
	return append(theStringSlice, theString)
}

func splitFunc(c rune) bool {
	return !unicode.IsLetter(c) && !unicode.IsNumber(c) && c != '.' && c != '_' && c != '-'
}
