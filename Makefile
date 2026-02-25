all: tools/anydbver


BUILD = $(shell date +%FT%T%z)
VERSION = $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
COMMIT = $(shell git rev-list -1 HEAD)
GO_VERSION = $(shell go version | cut -d " " -f3)\ -X\ main.Commit=$(COMMIT)
cmd/anydbver/Dockerfile.anydbver.cache: Dockerfile.anydbver.cache
	cp Dockerfile.anydbver.cache cmd/anydbver/Dockerfile.anydbver.cache
tools/anydbver: $(wildcard cmd/**/*.go) $(wildcard pkg/**/*.go) cmd/anydbver/Dockerfile.anydbver.cache Makefile
	go build -ldflags=-X\ main.Version=$(VERSION)\ -X\ main.GoVersion=$(GO_VERSION)\ -X\ main.Build=$(BUILD) -o tools/anydbver cmd/anydbver/anydbver.go

