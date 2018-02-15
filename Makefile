# The Docker registry where images are pushed.
# Note that if you use an org (like on Quay and DockerHub), you should
# include that: quay.io/foo
DOCKER_REGISTRY    ?= lukepatrick
DOCKER_BUILD_FLAGS :=
LDFLAGS            :=

BINS        = brigade-gitlab-gateway
IMAGES      = brigade-gitlab-gateway
DOCKER_BINS = brigade-gitlab-gateway

GIT_TAG   = $(shell git describe --tags --always 2>/dev/null)
VERSION   ?= ${GIT_TAG}
IMAGE_TAG ?= ${VERSION}
LDFLAGS   += -X github.com/lukepatrick/brigade-gitlab-gateway/pkg/version.Version=$(VERSION)

# Build native binaries
.PHONY: build
build: $(BINS)

.PHONY: $(BINS)
$(BINS):
	go build -ldflags '$(LDFLAGS)' -o bin/$@ ./$@/cmd/$@

# Cross-compile for Docker+Linux
build-docker-bins: $(addsuffix -docker-bin,$(DOCKER_BINS))

%-docker-bin:
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags '$(LDFLAGS)' -o ./$*/rootfs/$* ./$*/cmd/$*

# To use docker-build, you need to have Docker installed and configured. You should also set
# DOCKER_REGISTRY to your own personal registry if you are not pushing to the official upstream.
.PHONY: docker-build
docker-build: build-docker-bins
docker-build: $(addsuffix -image,$(IMAGES))

%-image:
	docker build $(DOCKER_BUILD_FLAGS) -t $(DOCKER_REGISTRY)/$*:$(IMAGE_TAG) $*

# You must be logged into DOCKER_REGISTRY before you can push.
.PHONY: docker-push
docker-push: $(addsuffix -push,$(IMAGES))

%-push:
	docker push $(DOCKER_REGISTRY)/$*:$(IMAGE_TAG)

.PRECIOUS: build-chart
.PHONY: build-chart
build-chart:
	helm package -d docs/ ./charts/brigade-gitlab-gateway
	helm repo index docs/

# All non-functional tests
.PHONY: test
test: test-style
test: test-unit
test: test-js

# Unit tests. Local only.
.PHONY: test-unit
test-unit:
	go test -v ./...

# Functional tests assume access to github.com
# To set this up in your local environment:
# - Make sure kubectl is pointed to the right cluster
# - Create "myvals.yaml" and set to something like this:
#   project: "deis/empty-testbed"
#   repository: "github.com/deis/empty-testbed"
#   secret: "MySecret"
# - Run "helm install ./charts/brigade-project -f myvals.yaml
# - Run "make run" in one terminal
# - Run "make test-functional" in another terminal
#
# This will clone the github.com/deis/empty-testbed repo and run the brigade.js
# file found there.
.PHONY: test-functional
test-functional: test-functional-prepare
test-functional:
	go test --tags integration ./tests

# Test Repo is https://github.com/deis/empty-testbed
TEST_REPO_COMMIT =  589e15029e1e44dee48de4800daf1f78e64287c0
KUBECONFIG       ?= ${HOME}/.kube/config
.PHONY: test-functional-prepare
test-functional-prepare:
	go run ./tests/cmd/generate.go -kubeconfig $(KUBECONFIG) $(TEST_REPO_COMMIT)

# JS test is local only
.PHONY: test-js
test-js:
	cd brigade-worker && yarn test

.PHONY: test-style
test-style:
	gometalinter \
		--disable-all \
		--enable deadcode \
		--severity deadcode:error \
		--enable gofmt \
		--enable ineffassign \
		--enable misspell \
		--enable vet \
		--tests \
		--vendor \
		--deadline 60s \
		./...
	@echo "Recommended style checks ===>"
	gometalinter \
		--disable-all \
		--enable golint \
		--vendor \
		--deadline 60s \
		./... || :

.PHONY: format
format:
	test -z "$$(find . -path ./vendor -prune -type f -o -name '*.go' -exec gofmt -d {} + | tee /dev/stderr)" || \
	test -z "$$(find . -path ./vendor -prune -type f -o -name '*.go' -exec gofmt -w {} + | tee /dev/stderr)"

HAS_NPM          := $(shell command -v npm;)
HAS_ESLINT       := $(shell command -v eslint;)
HAS_GOMETALINTER := $(shell command -v gometalinter;)
HAS_DEP          := $(shell command -v dep;)
HAS_GIT          := $(shell command -v git;)
HAS_BINDATA      := $(shell command -v go-bindata;)

.PHONY: bootstrap
bootstrap:
ifndef HAS_NPM
	$(error You must install npm)
endif
ifndef HAS_GIT
	$(error You must install git)
endif
ifndef HAS_ESLINT
	npm install -g eslint
endif
ifndef HAS_GOMETALINTER
	go get -u github.com/alecthomas/gometalinter
	gometalinter --install
endif
ifndef HAS_DEP
	go get -u github.com/golang/dep/cmd/dep
endif
ifndef HAS_BINDATA
	go get github.com/jteeuwen/go-bindata/...
endif
	dep ensure
