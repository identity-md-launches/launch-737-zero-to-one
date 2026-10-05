# ZTO test coverage

The original `ZeroToOne.t.sol` checks metadata, the constructor mint, ordinary transfers,
approvals, common privileged selectors and forbidden opcodes. `ZeroToOne.edge.t.sol`
adds boundary and failure tests for:

- Zero and one-unit transfers, emitted events, the whole supply and `uint256.max`.
- Finite allowance exhaustion, replay after refilling the owner, maximum finite versus
  unlimited allowances, replacement, revocation and isolation between owners/spenders.
- Direct and delegated self-transfers, including insufficient balance.
- Balance and allowance preservation when authorization, balance or receiver checks fail.
- Exact fee-free round trips and transfers to a contract without a receiver callback.
- Deployment by a contract factory followed by actual transfers of 10% to a distributor,
  88% to a pool address and 2% to the requested remainder wallet. Claims and token-side
  buy/sell movements deliver their full amounts.

The launch-flow test covers the token side only. The checkout does not contain the
factory, distributor, Uniswap v4 manager or paired IMD implementation imported by the
supplied protected harness. It therefore does not execute actual swaps or verify the
2,500 IMD starting market cap; these belong to the launch integration checks.

## Stateful properties

`ZeroToOne.invariant.t.sol` drives 11 explicitly selected handler actions across four
funded actors, including self-transfers, full-balance transfers, finite/infinite approvals,
revocation, delegated spending and deliberately invalid calls. Expected failures use
exact custom errors; unexpected handler reverts fail the campaign.

The model starts with the requested supply and records successful authorized movements
and approvals. It is never resynchronized from the token's balances or allowances.
After each random handler call, the invariants check:

1. Supply remains exactly `1_000_000_000 * 10**18`.
2. The sum of tracked holder balances equals that supply.
3. Each individual balance agrees with the independent model.
4. Every tracked owner/spender allowance agrees with approvals and successful spending,
   including rollback after rejected transfers.
5. No tokens or approvals leak to zero, the handler or other tested untracked addresses.

All successful transfers in the invariant campaign stay within the actor set. Bounds
come from the model, and failure actions intentionally exceed them. A deterministic
mixed sequence additionally pins nonzero delegation, allowance exhaustion, refilling,
self-transfer and rollback checks. The campaign uses 256 runs of 64 calls by inline
configuration; new stateless properties use 1,000 runs each.

## Offline reproduction

From the repository root, keep generated artifacts in the disposable scratch directory:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache --fuzz-seed 0x5a17 --fuzz-runs 2000
forge fmt --check test/ZeroToOne.edge.t.sol test/ZeroToOne.invariant.t.sol
```

No new dependencies, environment mutation, network calls, forks or storage overrides
are used. Test design follows the supplied Pashov fizz conservation/handler guidance
and Trail of Bits property-testing guidance; implementation and configuration are unchanged.

## Recorded validation

Foundry 1.8.3 with solc 0.8.26: offline build and formatting check passed. Both full
test runs passed: 45 runner entries, zero failures and zero skips (Foundry groups the
five invariants into one entry). Each campaign executed 16,384 handler calls with zero
unexpected reverts or discards. The second run used seed `0x5a17`, with 2,000 cases per
original fuzz property; the new properties retained their inline 1,000-case setting.
No implementation defect was reproduced.
