# Security Model

## Protected properties

- The contract cannot distribute more than the funded project budget.
- A milestone can be settled only once.
- Milestones are processed sequentially.
- Only the client can fund, approve, reject or cancel before work starts.
- Only the contractor can start, submit, claim timeout or open a dispute.
- Only the arbitrator can pause and resolve a disputed milestone.
- Arbitration can allocate only the current milestone amount.
- Protocol fees are capped at 5% and fixed at deployment.
- State and accounting update before external token transfers.
- No owner, upgrade proxy or emergency sweep can extract escrowed funds.

## Defensive controls

- Checks-effects-interactions ordering
- Reentrancy guard around every fund-moving path
- Safe support for ERC-20 tokens that return `true` or no return data
- Immutable participant and fee configuration
- Explicit custom errors and state-machine checks
- Review deadline prevents strategic late rejection after contractor timeout matures
- Emergency pause blocks submissions and settlements
- Unit, fuzz and invariant testing
- Slither in continuous integration

## Trust assumptions

- The payment token is assumed not to be rebasing, fee-on-transfer or malicious.
- The arbitrator is trusted to resolve disputes fairly and can temporarily pause the protocol.
- Evidence hashes prove commitment to content, not the correctness of the deliverable.
- Parties must evaluate legal enforceability in their jurisdiction.

## Known limitations

- No appeal layer or multi-arbitrator quorum in version 1.
- No support for native ETH, rebasing tokens or transfer-fee tokens.
- Due dates are metadata; review timeouts are enforced from submission time.
- This repository has not received an independent professional audit.

## Responsible disclosure

Do not exploit suspected vulnerabilities against deployed contracts. Open a private security advisory in the GitHub repository with reproduction steps and impact.

