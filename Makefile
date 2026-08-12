.PHONY: build test fuzz invariant format snapshot coverage slither
build:
	forge build --sizes
test:
	forge test -vvv
fuzz:
	forge test --match-path 'test/Fuzz.t.sol' -vv
invariant:
	forge test --match-path 'test/invariant/*.t.sol' -vv
format:
	forge fmt
snapshot:
	forge snapshot
coverage:
	forge coverage --report lcov
slither:
	slither . --foundry-out-directory out

