# Briefs (BRIEFS)

Small entry. Big $IMD pots. An AI jury. Finish on top and take all.
The court is cooked 🐸⚖️

Project links supplied in the brief: [briefs.fun](https://briefs.fun) · [@Briefs_fun](https://x.com/Briefs_fun).

This project implements the custom launch token. The jury and pot description is treated as branding:
the brief supplies no entry, adjudication, funding, or payout rules for an application. This token
does not collect entries, operate a jury, or promise payouts. There are no application contracts.

## Token behavior

| Property | Value |
| --- | --- |
| Solidity contract | `BriefsToken` in `src/BriefsToken.sol` |
| Name / symbol | `Briefs` / `BRIEFS` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None |
| Initial recipient | `msg.sender`, the immediate deployer |

The constructor mints the entire supply once and emits the standard `Transfer` event from the zero
address. Transfers deliver the full requested amount. There is no transfer tax, burn, rebase, wallet
limit, trading switch, blacklist, pause, mint role, owner, or upgrade mechanism. The constructor does
not call any other contract. Inherited mint/burn helpers are internal and have no external entry point.

The implementation inherits the vendored
[OpenZeppelin Contracts v5.0.2 ERC20](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/ERC20.sol)
without overriding transfer or approval behavior. ERC-20 operations return `true` on success and
revert with ERC-6093 custom errors on invalid addresses, insufficient balances, or insufficient
allowances. Zero-value transfers between valid addresses succeed and emit `Transfer`; transfers
to the zero address fail, even for zero amounts. Self-transfers preserve balances.

`approve` replaces the caller's allowance for one spender and emits `Approval`. `transferFrom`
consumes finite allowance; a maximum `uint256` allowance remains unchanged until replaced or revoked.
As in the vendored implementation, spending allowance does not emit another `Approval` event;
indexers should read `allowance()` for current values. A reverted delegated transfer restores both
balances and allowance. The deployer has no special ability to spend another holder's tokens.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 available:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimization with 200 runs, and
`bytecode_hash = "none"`. All five OpenZeppelin source files needed by the token are vendored as
ordinary files in `lib/openzeppelin-contracts/`, together with their MIT license, provenance, and
SHA-256 checksums. The tests use a small local cheatcode interface and assertion helper. Building
and testing require no dependency downloads, fork, RPC, environment configuration, FFI, or filesystem
cheatcode permissions.

The configured fuzz seed is the assignment's
`0x8448fc74c31c4ec6ed4817c0888972c734737f19e58e173001f4524393810b29`, with 1,024 cases per fuzz test.
Tests cover metadata, constructor issuance and events, CREATE/CREATE2 factory deployment, exact
transfers, zero/self/full-balance transfers, approvals and revocation, finite/infinite allowances,
unauthorized spending, atomic rollback, invalid addresses and oversized values, unavailable admin
selectors, runtime constraints, and 32-operation randomized sequences checked against a balance model.
Every test creates isolated state; none depends on a test order or reads or changes environment variables.

The local launch tests exercise token accounting through contract actors for distribution, claims,
and transfers in both trading directions. Those actors do not implement Uniswap v4 or verify actual
pool pricing and settlement. The supplied protected tests run those full launch integration checks
in the network's separate harness; its imported launch infrastructure is not included in this repository.

## Deployment parameters and responsibilities

The launch deployer should use `src/BriefsToken.sol:BriefsToken` with an empty constructor argument
list. The intended chain is Ethereum (chain ID `1`). Deploy through the launch factory: the immediate
caller receives all `10^27` units, including when using CREATE2. A direct deployment would instead
mint them to that direct deployer. No initialization transaction, linked library address, external
service setting, or administrative wallet is required by the token.

The launch parameters below are supplied by the assignment and belong to the factory and manifest
process. They are not embedded in the token:

| Launch parameter | Assignment value |
| --- | --- |
| Paired token | IMD at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals) |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Pool initialPrice provenance value | `79228162514264337593543950336` |
| `economics.poolBps` | `5000` |
| `economics.initialMarketCapWei` | `8888000000000000000000` (8,888 IMD) |
| `economics.remainderTo` | `0xee2aaa315cf7ed169f93148d30d24af9318dbb66` |

The factory handles the launch allocation: 10% (100 million BRIEFS) to its MerkleDistributor,
50% (500 million) to liquidity, and 40% (400 million) to the supplied remainder recipient. The token
allocates none of these separately. The factory/deployer derives the actual opening pool price
from the market cap and token address; the provenance value is not an instruction to open at 1:1.
The separate manifest step creates `launch.json` after acceptance.

## After launch

No token setters, owner duties, keepers, or ongoing token administration exist. The launch operator
is responsible for the factory distribution, actual pool initialization, source verification, and
publishing the deployed address. The project operator is responsible for any separately built
website, jury, contest, or prize service described by the branding.

Holders control transfers and approvals. Wallets should request only the allowance needed and
allow holders to revoke it. Replacing an existing nonzero allowance has the standard ERC-20
transaction-ordering risk; revoke it and wait for confirmation before granting a new amount.
Native currency sent normally is rejected. Tokens sent to this token's own address, and assets
otherwise stuck there, have no recovery mechanism. There is no administrator who can undo mistakes.

The security review and verification scope are recorded in `SECURITY.md`. Local test results are
not an independent audit or a substitute for the launch's protected checks and adversarial review.
