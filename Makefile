.PHONY: build run pr pull-request release

build:
	./build.sh

run:
	./scripts/run.sh $(ARGS)

pr: pull-request

pull-request:
	./scripts/pull-request.sh $(ARGS)

release:
	./scripts/release.sh
