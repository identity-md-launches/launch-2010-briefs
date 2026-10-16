// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BriefsToken} from "../../src/BriefsToken.sol";
import {TestBase} from "../helpers/TestBase.sol";
import {BriefsTokenHandler} from "./BriefsTokenHandler.sol";

/// @notice Invariants of BriefsToken under random sequences of bounded calls from several actors.
/// @dev The token holds no external value, but it *is* the ledger of value: what it must keep is
///      that the supply never changes, that the ledger always sums to the supply, that every
///      balance and allowance equals what the independent ghost model says, that nobody ever sends
///      more than they received, and that no privileged selector ever works. Runs with
///      fail-on-revert so a handler call that reverts unexpectedly is reported, not swallowed.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract BriefsTokenInvariantTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    BriefsTokenHandler internal handler;
    BriefsToken internal token;

    function setUp() public {
        handler = new BriefsTokenHandler();
        token = handler.token();
    }

    /// @dev Tells forge's invariant runner to drive only the handler.
    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    // ---- supply ------------------------------------------------------------------------------

    function invariant_SupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY, "total supply drifted from the minted amount");
        assertEq(token.INITIAL_SUPPLY(), SUPPLY, "the supply constant changed");
    }

    function invariant_LedgerSumsToSupply() public view {
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, token.totalSupply(), "tracked balances do not sum to the supply");
    }

    function invariant_ZeroAddressHoldsNothing() public view {
        assertEq(token.balanceOf(address(0)), 0, "the zero address holds tokens");
    }

    // ---- ledger matches the independent model ------------------------------------------------

    function invariant_BalancesMatchGhostModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.ghostBalance(actor), "a balance diverged from the model");
            assertLe(token.balanceOf(actor), SUPPLY, "a balance exceeds the supply");
        }
    }

    function invariant_AllowancesMatchGhostModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < n; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.ghostAllowance(owner, spender),
                    "an allowance diverged from the model"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0, "the zero spender has an allowance");
        }
    }

    /// @dev Nobody ever sends out more than they were ever credited with; the deployer's credit is
    ///      the constructor mint. This is the "no withdrawing more than you put in" property.
    function invariant_NobodySendsMoreThanReceived() public view {
        uint256 n = handler.actorCount();
        uint256 totalSent;
        uint256 totalReceived;
        for (uint256 i; i < n; ++i) {
            address actor = handler.actors(i);
            uint256 sent = handler.ghostSent(actor);
            uint256 received = handler.ghostReceived(actor);
            assertLe(sent, received, "an account sent more than it ever received");
            assertEq(received - sent, token.balanceOf(actor), "flows do not reconcile with the balance");
            totalSent += sent;
            totalReceived += received;
        }
        // The constructor mint is the only credit that is not also somebody's debit.
        assertEq(totalReceived - totalSent, SUPPLY, "net flows do not equal the minted supply");
        assertEq(totalSent, handler.ghostVolume(), "volume ghost disagrees with per-account flows");
    }

    // ---- authority and value boundaries ------------------------------------------------------

    function invariant_NoPrivilegedSelectorEverSucceeds() public view {
        assertEq(handler.adminSuccesses(), 0, "a privileged selector succeeded");
    }

    function invariant_TokenHoldsNoNativeCurrency() public view {
        assertEq(address(token).balance, 0, "the token accumulated native currency");
    }

    function invariant_TokenRuntimeIsImmutable() public view {
        assertEq(address(token).code, type(BriefsToken).runtimeCode);
    }
}
