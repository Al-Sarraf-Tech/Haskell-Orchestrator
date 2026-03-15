.PHONY: build test clean demo doctor install format lint check

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
