# Image URL to use all building/pushing image targets
IMG_REPO ?= ghcr.io/sapcc/disco
IMG_TAG ?= latest
IMG ?= ${IMG_REPO}:${IMG_TAG}

# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.28
## Tool Versions
KUSTOMIZE_VERSION ?= 5.6.0
CONTROLLER_TOOLS_VERSION ?= 0.18.0
GOLINT_VERSION ?= 2.1.6
GINKGOLINTER_VERSION ?= 0.19.1

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

OS := $(shell go env GOOS)

.PHONY: build-all
build-all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development
##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=deploy/kustomize/config/crd/bases output:rbac:artifacts:config=deploy/kustomize/config/rbac output:webhook:artifacts:config=deploy/kustomize/config/webhook

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) -p path)" go test ./... -coverprofile cover.out

##@ Build

.PHONY: build
build: GIT_BRANCH  = $(shell git rev-parse --abbrev-ref HEAD)
build: GIT_COMMIT  = $(shell git rev-parse --short HEAD)
build: GIT_STATE   = $(shell if git diff --quiet; then echo clean; else echo dirty; fi)
build: BUILD_DATE  = $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
build:
	@mkdir -p bin/$(OS)
	go build -mod=readonly -ldflags "-s -w -X github.com/sapcc/disco/pkg/version.GitBranch=$(GIT_BRANCH) -X github.com/sapcc/disco/pkg/version.GitCommit=$(GIT_COMMIT) -X github.com/sapcc/disco/pkg/version.GitState=$(GIT_STATE) -X github.com/sapcc/disco/pkg/version.BuildDate=$(BUILD_DATE)" -o bin/$(OS)/disco main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./main.go

.PHONY: docker-build
docker-build: GIT_COMMIT  = $(shell git rev-parse --short HEAD)
docker-build: test ## Build docker image with the manager.
	docker build --network=host -t ${IMG_REPO}:${GIT_COMMIT} .

.PHONY: docker-push-mac
docker-push-mac: GIT_COMMIT  = $(shell git rev-parse --short HEAD)
docker-push-mac: test ## Build docker image with the manager.
	docker buildx build --platform linux/amd64 -t ${IMG_REPO}:${GIT_COMMIT} . --push

.PHONY: docker-push
docker-push: GIT_COMMIT  = $(shell git rev-parse --short HEAD)
docker-push: ## Push docker image with the manager.
	docker push ${IMG_REPO}:${GIT_COMMIT}
	docker tag ${IMG_REPO}:${GIT_COMMIT} ${IMG_REPO}:latest && docker push ${IMG_REPO}:latest

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build deploy/kustomize/config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build deploy/kustomize/config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd deploy/kustomize/config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build deploy/kustomize/config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build deploy/kustomize/config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: generate-helm-chart
generate-helm-chart: manifests kustomize
	cd deploy/kustomize/config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build deploy/kustomize/config/default | go run ./hack/kustomize-to-helm.go --out=deploy/helm-chart

##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest
GOLINT ?= $(LOCALBIN)/golangci-lint

.PHONY: lint
lint: golint
	$(GOLINT) run -v --timeout 5m	

.PHONY: golint
golint: $(GOLINT)
$(GOLINT): $(LOCALBIN)
	GOBIN=$(LOCALBIN) go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v$(GOLINT_VERSION)
	GOBIN=$(LOCALBIN) go install github.com/nunnatsa/ginkgolinter/cmd/ginkgolinter@v$(GINKGOLINTER_VERSION)

KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	curl -s $(KUSTOMIZE_INSTALL_SCRIPT) | bash -s -- $(subst v,,$(KUSTOMIZE_VERSION)) $(LOCALBIN)

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary.
$(CONTROLLER_GEN): $(LOCALBIN)
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@v$(CONTROLLER_TOOLS_VERSION)

.PHONY: envtest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

install-go-licence-detector:
	@if ! hash go-licence-detector 2>/dev/null; then printf "\e[1;36m>> Installing go-licence-detector (this may take a while)...\e[0m\n"; go install go.elastic.co/go-licence-detector@latest; fi

check-dependency-licenses: install-go-licence-detector
	@printf "\e[1;36m>> go-licence-detector\e[0m\n"
	@go list -m -mod=readonly -json all | go-licence-detector -includeIndirect -rules .license-scan-rules.json -overrides .license-scan-overrides.jsonl

GO_TESTENV =
GO_BUILDFLAGS =
GO_LDFLAGS =
# which packages to test with test runner
GO_TESTPKGS := $(shell go list -f '{{if or .TestGoFiles .XTestGoFiles}}{{.ImportPath}}{{end}}' ./...)
ifeq ($(GO_TESTPKGS),)
GO_TESTPKGS := ./...
endif
# which packages to measure coverage for
GO_COVERPKGS := $(shell go list ./...)
# to get around weird Makefile syntax restrictions, we need variables containing nothing, a space and comma
null :=
space := $(null) $(null)
comma := ,

build/cover.out: build
	test -d build || mkdir build
	@printf "\e[1;36m>> Running tests\e[0m\n"
	@env $(GO_TESTENV) go test -shuffle=on -p 1 -coverprofile=$@ $(GO_BUILDFLAGS) -ldflags "-s -w -X github.com/sapcc/kube-fip-controller/pkg/version.Revision=$(GIT_REVISION) -X github.com/sapcc/kube-fip-controller/pkg/version.Branch=$(GIT_BRANCH) -X github.com/sapcc/kube-fip-controller/pkg/version.BuildDate=$(BUILD_DATE) -X github.com/sapcc/kube-fip-controller/pkg/version.Version=$(VERSION)" -covermode=count -coverpkg=$(subst $(space),$(comma),$(GO_COVERPKGS)) $(GO_TESTPKGS)
