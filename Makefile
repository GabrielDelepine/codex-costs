.PHONY: build run pr pull-request release

build:
	./build.sh

run: build
	open "build/Codex Costs.app"

pr: pull-request

pull-request:
	./scripts/pull-request.sh $(ARGS)

release:
	./scripts/release.sh
