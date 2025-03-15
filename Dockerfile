# syntax=docker/dockerfile:experimental
# Build the manager binary
FROM --platform=${BUILDPLATFORM:-linux/amd64} golang:1.23 as builder
ARG TARGETOS
ARG TARGETARCH

WORKDIR /workspace
# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum

COPY . .
# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

# Build
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -a -o disco main.go

# Use distroless as minimal base image to package the manager binary
# Refer to https://github.com/GoogleContainerTools/distroless for more details
FROM --platform=${BUILDPLATFORM:-linux/amd64} gcr.io/distroless/static:nonroot
LABEL source_repository="https://github.com/sapcc/disco"
LABEL org.opencontainers.image.source="https://github.com/sapcc/disco"
WORKDIR /
COPY --from=builder /workspace/disco .
USER 65532:65532

ENTRYPOINT ["/disco"]
