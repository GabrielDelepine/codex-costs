.PHONY: build run pr pull-request

build:
	./build.sh

run: build
	open "build/Codex Costs.app"

pr: pull-request

pull-request:
	./scripts/pull-request.sh
