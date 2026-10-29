.PHONY: build run

build:
	./build.sh

run: build
	open "build/Codex Costs.app"
