// SPDX-FileCopyrightText: 2022 SAP SE or an SAP affiliate company
// SPDX-License-Identifier: Apache-2.0

package v1

import (
	"context"
	"fmt"

	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"

	"github.com/sapcc/disco/pkg/disco"
	util "github.com/sapcc/disco/pkg/util"
)

type RecordDefaulter struct {
}

func SetupWebhookWithManager(mgr ctrl.Manager) error {
	return ctrl.NewWebhookManagedBy(mgr).
		For(&Record{}).
		WithDefaulter(&RecordDefaulter{}).
		Complete()
}

//+kubebuilder:webhook:path=/mutate-disco-stable-sap-cc-v1-record,mutating=true,failurePolicy=fail,sideEffects=None,groups=disco.stable.sap.cc,resources=records,verbs=create;update,versions=v1,name=mrecord.kb.io,admissionReviewVersions=v1

var _ admission.CustomDefaulter = &RecordDefaulter{}

// Default implements webhook.Defaulter so a webhook will be registered for the type
func (rd *RecordDefaulter) Default(_ context.Context, obj runtime.Object) error {
	record, ok := obj.(*Record)
	if !ok {
		return fmt.Errorf("expected an Record object but got %T", obj)
	}

	if record.Spec.ZoneName == "" {
		record.Spec.ZoneName = util.EnsureFQDN(disco.DefaultDNSZoneName)
	}

	// Ensure a FQDN for CNAME records.
	if record.Spec.Type == RecordTypeCNAME {
		record.Spec.Record = util.EnsureFQDN(record.Spec.Record)
		for idx, host := range record.Spec.Hosts {
			record.Spec.Hosts[idx] = util.EnsureFQDN(host)
		}
	}
	return nil
}
