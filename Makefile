.PHONY: build run pr pull-request release

build:
	./build.sh

run: build
	open "build/Codex Costs.app"

pr: pull-request

pull-request:
	./scripts/pull-request.sh

release:
	./scripts/release.sh
