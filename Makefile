SHELL := /bin/bash

VERSION ?=
DESTINATION ?=

.PHONY: validate test prepare

validate:
	./scripts/validate-source.sh
	bash -n scripts/*.sh tests/*.sh

test: validate
	./tests/source-contract.sh
	./tests/upstream-readiness.sh
	./tests/prepare-upstream.sh
	./tests/extension-compatibility.sh
	./tests/build-local-components.sh
	./tests/assemble-installer.sh

prepare:
	@test -n "$(VERSION)" || { echo "VERSION is required" >&2; exit 2; }
	@test -n "$(DESTINATION)" || { echo "DESTINATION is required" >&2; exit 2; }
	./scripts/prepare-upstream.sh "$(VERSION)" "$(DESTINATION)"
