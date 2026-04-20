# SPDX-FileCopyrightText: 2025 SAP SE or an SAP affiliate company
#
# SPDX-License-Identifier: Apache-2.0

# syntax=docker/dockerfile:experimental
# Build the manager binary
FROM --platform=${BUILDPLATFORM:-linux/amd64} golang:1.24 as builder
ARG TARGETOS
ARG TARGETARCH

WORKDIR /workspace
# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum
# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

# Miscellaneous
COPY Makefile Makefile
COPY hack/ hack/

# Copy the go source
COPY main.go main.go
COPY api/ api/
COPY controllers/ controllers/
COPY pkg/ pkg/

# Build
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} make build

# Use distroless as minimal base image to package the manager binary
# Refer to https://github.com/GoogleContainerTools/distroless for more details
FROM --platform=${BUILDPLATFORM:-linux/amd64} gcr.io/distroless/static:nonroot
LABEL source_repository="https://github.com/sapcc/disco"
LABEL org.opencontainers.image.source="https://github.com/sapcc/disco"
WORKDIR /
COPY --from=builder /workspace/bin/linux/disco .
USER 65532:65532

ENTRYPOINT ["/disco"]
