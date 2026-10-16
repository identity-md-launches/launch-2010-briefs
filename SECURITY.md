# Security and review scope

The production change is a constructor-only extension of the vendored OpenZeppelin v5.0.2 ERC-20.
Its fixed constants are the name, symbol, and initial supply; it inherits 18 decimals. The only
mint call is in the constructor. No new transfer, allowance, external-call, or access-control logic
is introduced. The dependency's source and MIT license are included unchanged.

The pinned security reference was reviewed for applicable failure modes:

- **Supply and arithmetic:** `10^27` base units are minted once. Balance conservation, self-transfers,
  maximum inputs, overdraw attempts, and randomized multi-actor sequences are covered by tests.
- **Authorization:** balances move only through a holder's transfer or an authorized spender's
  transferFrom. The factory has no extra authority. Tests attempt mint, seize, freeze, burn, upgrade,
  and ownership selectors from both the deploying factory and a stranger.
- **Atomic failure:** invalid recipients, inadequate balances, and inadequate allowances revert.
  Tests verify both balances and allowances after rejected delegated transfers.
- **External interactions:** the constructor and ERC-20 operations perform no external calls and
  invoke no recipient hooks. There is no external interaction through which a recipient can reenter.
  There is no proxy or linked external library. Runtime tests scan for DELEGATECALL, CALLCODE,
  and SELFDESTRUCT while skipping PUSH data.
- **Launch transfers:** ordinary exact-amount transfers support the factory's distribution and both
  sides of trading without tax exemptions or address configuration. Local contract-actor tests
  check amounts, while actual AMM settlement belongs to the protected launch harness.
- **Allowances:** holders can revoke or replace them. Maximum allowances follow standard ERC-20
  behavior; they are supported, not recommended for wallet defaults. Approval replacement retains
  the usual ERC-20 ordering risk documented in the README.
- **Other systems:** no price oracle, randomness, signature verification, vault shares, lottery,
  staking, or jury settlement exists in this token. Those reference topics do not apply here.

Verification uses Solidity 0.8.26 and Foundry build, unit, fuzz, and formatting checks. Slither and
Mythril were not run. The supplied protected harness depends on launch infrastructure outside the
delivered project and is left to the network verifier. No deployment or broadcast was performed.
Independent adversarial review and the network's full launch checks remain release responsibilities.
