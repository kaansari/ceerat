SHELL := /usr/bin/env bash

RENDER_SERVICES := user-service agent-service web-ui admin-ui customer-ui ats-crawler

.PHONY: help deps test build clean local-check local-start local-stop local-status render-build render-build-user-service render-build-agent-service render-build-web-ui render-build-admin-ui render-build-customer-ui render-build-ats-crawler

help:
	@printf 'Ceerat Render build helpers\n\n'
	@printf 'Targets:\n'
	@printf '  make deps                         sync go workspace and download modules\n'
	@printf '  make test                         run tests for all workspace modules\n'
	@printf '  make build                        build all Render services into ./bin\n'
	@printf '  make local-check                  run tests and build all local binaries\n'
	@printf '  make local-start                  build and start the local stack\n'
	@printf '  make local-stop                   stop the local stack\n'
	@printf '  make local-status                 show local stack status\n'
	@printf '  make render-build SERVICE=<name>  build one service for Render\n'
	@printf '  make render-build-<service>       build one named service\n'
	@printf '  make clean                        remove ./bin\n\n'
	@printf 'Services: %s\n' "$(RENDER_SERVICES)"

deps:
	@./scripts/render-build.sh deps

test:
	@./scripts/render-build.sh test

build:
	@./scripts/render-build.sh all

local-check: test build

local-start:
	@./start-stack.sh

local-stop:
	@./stop-stack.sh

local-status:
	@./status.sh

render-build:
	@test -n "$(SERVICE)" || (echo "Usage: make render-build SERVICE=<$(RENDER_SERVICES)>"; exit 2)
	@./scripts/render-build.sh "$(SERVICE)"

render-build-user-service:
	@./scripts/render-build-user-service.sh

render-build-agent-service:
	@./scripts/render-build-agent-service.sh

render-build-web-ui:
	@./scripts/render-build-web-ui.sh

render-build-admin-ui:
	@./scripts/render-build-admin-ui.sh

render-build-customer-ui:
	@./scripts/render-build-customer-ui.sh

render-build-ats-crawler:
	@./scripts/render-build-ats-crawler.sh

clean:
	@rm -rf bin
