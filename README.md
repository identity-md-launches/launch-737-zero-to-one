# Zero To One (ZTO)

A plain community token: fixed supply, no fees, no minting after launch, no owner powers, no
transfer rules.

| Property | Value |
| --- | --- |
| Contract | `src/ZeroToOne.sol` (`ZeroToOne`) |
| Name / symbol | `Zero To One` / `ZTO` |
| Decimals | 18 |
| Total supply | 1,000,000,000 ZTO = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Compiler | solc 0.8.26, optimizer 200 runs, `evm_version = cancun`, `bytecode_hash = "none"` |

## Behaviour

- The constructor mints the whole supply to `msg.sender` (the launch factory) and emits one
  `Transfer(address(0), deployer, supply)`. `totalSupply` is a constant; no code path mints or burns.
- `transfer`, `approve`, `transferFrom` follow ERC-20. Exactly the requested amount moves; nothing is
  deducted, redirected or burned, for any sender or receiver, so no launch address needs an exemption.
- There is no owner, admin, pause, blocklist, upgrade hook, `delegatecall`, `selfdestruct` or external
  call. The contract has no dependencies and does not accept ETH.

Deliberate choices (the usual ERC-20 conventions, not transfer rules):

- A transfer to the zero address reverts with `InvalidReceiver`, so tokens cannot be lost there by
  mistake. There is consequently no way to burn; holders who want to retire tokens must send them to
  an address nobody controls, and `totalSupply` will still report the full supply.
- `approve` to the zero address reverts with `InvalidSpender`.
- An allowance of `type(uint256).max` is unlimited and is not decreased by `transferFrom`.
- `approve` replaces the allowance (standard ERC-20 race applies: set to 0 first or use an exact-spend
  flow if changing a non-zero allowance for an untrusted spender). There is no `permit`.
- Failures revert with custom errors: `InsufficientBalance`, `InsufficientAllowance`.

## Launch parameters

Launch kind `custom_token`, deployed through the factory's `launchCustom`; no application contracts.

| Parameter | Value |
| --- | --- |
| `token.contract` | `ZeroToOne` |
| `token.constructorArgs` | `[]` |
| `token.totalSupply` | `1000000000000000000000000000` |
| `token.decimals` | `18` |
| `economics.poolBps` | `8800` (88% of the whole supply = 880,000,000 ZTO, single-sided seed) |
| `economics.initialMarketCapWei` | `2500000000000000000000` (2,500 IMD, 18 decimals assumed) |
| `economics.remainderTo` | `0x7B8C742F2e1eEB3fB2C10d72967Fa6d4a22f0479` |
| `pool.pairedCurrency` | IMD (the chain's pair token; address from the network configuration) |

Resulting split of the supply:

| Share | Amount (ZTO) | Recipient |
| --- | --- | --- |
| Swarm, 10% (fixed by the network) | 100,000,000 | the launch's MerkleDistributor |
| Pool, 88% | 880,000,000 | Uniswap v4 pool, single-sided |
| Remainder, 2% | 20,000,000 | `0x7B8C742F2e1eEB3fB2C10d72967Fa6d4a22f0479` |

A 2,500 IMD cap over 1,000,000,000 ZTO implies an opening price of 0.0000025 IMD per ZTO. The
`sqrtPriceX96`, pool fee, tick spacing and tick range are derived by the network's deployer and are
not fixed in this repository.

## Assumptions

- "All minted to the deployer" means `msg.sender` of the constructor, which in a launch is the factory.
- IMD has 18 decimals, so 2,500 IMD is `2500e18` minor units. If it does not, `initialMarketCapWei`
  must be restated in the pair token's actual minor units.
- The 10% swarm share comes out of the total, leaving the requester 88% pool + 2% remainder.
- The IMD token address, factory address and pool manager address are not known to this repository
  and are not needed by the token; they come from the network configuration at launch.

## Operational responsibilities

- Nobody operates the token after deployment: there is nothing to configure, renounce or upgrade.
- The network's deployer is responsible for the manifest, the pool price derivation, deployment and
  explorer verification. Nothing here broadcasts a transaction or handles a key.
- The holder of `0x7B8C…0479` is solely responsible for that key; the 20,000,000 ZTO sent there are
  unlocked and unvested.
- Pool liquidity custody and any locking are determined by the factory, not by this token.
- Tokens sent to the token contract itself or to any address without a key are unrecoverable.

## Development

```
forge build
forge test
forge fmt --check
```

`forge-std` v1.9.7 is vendored under `lib/forge-std` as ordinary files (no submodule). Tests need no
environment variables, network or ffi.

Tests cover metadata and supply, exact transfers, allowance spending, every revert path, the absence
of any admin or mint surface, a runtime opcode scan, fuzzed conservation, and an invariant run that
keeps the supply fixed and balances summing to it.

Passing tests are not a security audit. No static analyser (Slither, Mythril) was run. An independent
review is advisable before release.
