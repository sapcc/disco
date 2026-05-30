// SPDX-FileCopyrightText: 2022 SAP SE or an SAP affiliate company
// SPDX-License-Identifier: Apache-2.0

package disco

const (
	// AnnotationRecord allows setting a different record than the default per ingress or service.
	AnnotationRecord = "record"

	// AnnotationRecordType allows setting the record type. Must be CNAME, A, NS, SOA. Default: CNAME.
	AnnotationRecordType = "record-type"

	// AnnotationRecordZoneName allows creating a record in a different DNS zone.
	AnnotationRecordZoneName = "zone-name"
)

// DefaultDNSZoneName is the name of the default DNS zone.
var DefaultDNSZoneName string
