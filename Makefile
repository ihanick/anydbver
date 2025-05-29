all: tools/anydbver


BUILD = $(shell date +%FT%T%z)
GO_VERSION = $(shell go version | cut -d " " -f3)\ -X\ main.Commit=$(git rev-list -1 HEAD)
tools/anydbver: $(wildcard cmd/**/*.go) $(wildcard pkg/**/*.go) Makefile
	go build -ldflags=-X\ main.Version=v0.1.21\ -X\ main.GoVersion=$(GO_VERSION)\ -X\ main.Build=$(BUILD) -o tools/anydbver cmd/anydbver/anydbver.go

