.PHONY: build test clean demo doctor install format lint check verify tier-check contract-check verify-standalone bench coverage haddock container ci-local

build:
	cabal build all

test:
	cabal test all --test-show-details=direct

clean:
	cabal clean

demo:
	cabal run orchestrator -- demo

doctor:
	cabal run orchestrator -- doctor

install:
	cabal install exe:orchestrator --install-method=copy --overwrite-policy=always

format:
	ormolu --mode inplace $$(find src app test -name '*.hs')

lint:
	cabal build all -Wall -Werror 2>&1

check: build test
	@echo "All checks passed."

release-gate:
	@echo "Running release gate checks..."
	@./scripts/release-gate.sh
	@echo "Release gate: PASSED"

tier-check:
	@./scripts/check-tier-boundaries.sh

verify:
	@./scripts/verify-release.sh

contract-check:
	@./scripts/check-capability-contract.sh

verify-standalone:
	@./scripts/verify-standalone-install.sh

bench:
	cabal bench all

coverage:
	cabal test all --enable-coverage --test-show-details=direct

haddock:
	cabal haddock all --haddock-html

container:
	podman build -f Containerfile -t orchestrator:local .

ci-local: lint test coverage
	@echo "All local CI checks passed."
