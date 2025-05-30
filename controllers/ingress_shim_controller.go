/*
Copyright 2022 SAP SE.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controllers

import (
	"context"
	"fmt"

	"github.com/go-logr/logr"
	"github.com/pkg/errors"
	networkingv1 "k8s.io/api/networking/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	discov1 "github.com/sapcc/disco/api/v1"
	"github.com/sapcc/disco/pkg/clientutil"
	"github.com/sapcc/disco/pkg/disco"
	util "github.com/sapcc/disco/pkg/util"
)

// IngressShimReconciler reconciles an ingress object
type IngressShimReconciler struct {
	AnnotationKey string
	DefaultRecord string
	logger        logr.Logger
	c             client.Client
	scheme        *runtime.Scheme
}

//+kubebuilder:rbac:groups=networking.k8s.io,resources=ingresses,verbs=get;list;watch
//+kubebuilder:rbac:groups=disco.stable.sap.cc,resources=records,verbs=get;list;watch;create;update;patch;delete

// SetupWithManager sets up the controller with the Manager.
func (r *IngressShimReconciler) SetupWithManager(mgr ctrl.Manager) error {
	if r.AnnotationKey == "" {
		return errors.New("annotation for ingress resources not provided")
	}
	if r.DefaultRecord == "" {
		return errors.New("default record not provided")
	}

	r.c = mgr.GetClient()
	r.scheme = mgr.GetScheme()

	name := "ingress-shim"
	r.logger = mgr.GetLogger().WithName(name)
	return ctrl.NewControllerManagedBy(mgr).
		Named(name).
		For(&networkingv1.Ingress{}).
		Watches(&discov1.Record{}, handler.EnqueueRequestForOwner(mgr.GetScheme(), mgr.GetRESTMapper(), &networkingv1.Ingress{})).
		WithOptions(controller.Options{LogConstructor: func(_ *reconcile.Request) logr.Logger { return r.logger }, MaxConcurrentReconciles: 1}).
		Complete(r)
}

func (r *IngressShimReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	ctx = log.IntoContext(ctx, r.logger.WithValues("ingress", req.String()))

	var ingress = new(networkingv1.Ingress)
	if err := r.c.Get(ctx, req.NamespacedName, ingress); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	if !isHandleObject(r.AnnotationKey, ingress) {
		log.FromContext(ctx).V(5).Info("ignoring ingress with missing annotation",
			"annotation", r.AnnotationKey)
		return ctrl.Result{}, nil
	}

	rec := r.DefaultRecord
	if v, ok := r.getAnnotationValue(disco.AnnotationRecord, ingress); ok {
		rec = v
	}

	recordsetType := discov1.RecordTypeCNAME
	if v, ok := r.getAnnotationValue(disco.AnnotationRecordType, ingress); ok {
		recordsetType = v
	}

	hosts := make([]string, 0)
	for _, host := range ingress.Spec.Rules {
		if host.Host != "" {
			hosts = append(hosts, util.EnsureFQDN(host.Host))
		}
	}
	if len(hosts) == 0 {
		log.FromContext(ctx).Info("ignoring ingress without hosts")
		return ctrl.Result{}, nil
	}

	var record = new(discov1.Record)
	record.Name = ingress.Name
	record.Namespace = ingress.Namespace

	result, err := clientutil.CreateOrPatch(ctx, r.c, record, func() error {
		record.Spec.Record = rec
		record.Spec.Type = discov1.RecordType(recordsetType)
		record.Spec.Hosts = hosts
		record.Spec.Description = fmt.Sprintf("Created for ingress %s/%s.", ingress.Namespace, ingress.Name)
		if v, ok := r.getAnnotationValue(disco.AnnotationRecordZoneName, ingress); ok {
			record.Spec.ZoneName = v
		}
		return controllerutil.SetOwnerReference(ingress, record, r.scheme)
	})
	if err != nil {
		return ctrl.Result{}, err
	}
	switch result {
	case clientutil.OperationResultCreated:
		log.FromContext(ctx).Info("created record", "namespace", record.Namespace, "name", record.Name)
	case clientutil.OperationResultUpdated:
		log.FromContext(ctx).Info("updated record", "namespace", record.Namespace, "name", record.Name)
	}
	return ctrl.Result{}, nil
}

func (r *IngressShimReconciler) getAnnotationValue(key string, ingress *networkingv1.Ingress) (string, bool) {
	if ingress.GetAnnotations() == nil {
		return "", false
	}
	v, ok := ingress.Annotations[makeAnnotation(r.AnnotationKey, key)]
	return v, ok
}
