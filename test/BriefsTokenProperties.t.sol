// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BriefsToken} from "../src/BriefsToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./helpers/TestBase.sol";

/// @notice Stateless properties and pinned edge cases that the unit suite does not reach: the
///         zero address as sender or approver, allowances across the whole uint256 range, round
///         trips, and order-independence of splits. Inputs are constrained with `bound`, never
///         discarded, so every run checks something.
/// forge-config: default.fuzz.runs = 1000
contract BriefsTokenPropertiesTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    BriefsToken internal token;

    function setUp() public {
        token = new BriefsToken();
    }

    // ---- supply is exactly what the brief says ------------------------------------------------

    function test_SupplyIsOneBillionWholeTokensAtEighteenDecimals() public view {
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** uint256(token.decimals()));
        assertEq(token.totalSupply() / 10 ** uint256(token.decimals()), 1_000_000_000);
        assertEq(token.totalSupply() % 10 ** uint256(token.decimals()), 0);
    }

    function test_EachDeploymentIsAnIndependentFixedSupply() public {
        BriefsToken second = new BriefsToken();
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(second.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        // Moving tokens on one instance leaves the other untouched.
        token.transfer(ALICE, 1);
        assertEq(second.balanceOf(ALICE), 0);
        assertEq(second.balanceOf(address(this)), SUPPLY);
    }

    // ---- the zero address can neither send nor approve ---------------------------------------

    function test_ZeroAddressCannotSendEvenZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroAddressCannotMintBySending() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroAddressCannotApprove() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(SPENDER, 1);
        assertEq(token.allowance(address(0), SPENDER), 0);
    }

    /// @dev Nobody can hold an allowance from the zero address (it cannot approve), so the allowance
    ///      check fires first; with a zero amount the approver check fires instead (see the unit suite).
    ///      Either way nothing is minted out of the zero address.
    function test_TransferFromZeroSourceWithNonzeroAmountReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceDoesNotBypassZeroRecipientCheck() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 1);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceDoesNotBypassBalanceCheck() public {
        token.transfer(ALICE, 5);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 5, 6));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 6);
        assertEq(token.balanceOf(ALICE), 5);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
    }

    function test_AllowanceOneBelowInfiniteIsFinite() public {
        uint256 almost = type(uint256).max - 1;
        token.approve(SPENDER, almost);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), almost - 1);
    }

    function test_OneWeiTransfersAreExact() public {
        token.transfer(ALICE, 1);
        assertEq(token.balanceOf(ALICE), 1);
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
    }

    // ---- fuzzed properties -------------------------------------------------------------------

    /// @dev Approvals accept the full uint256 range and the latest one always wins.
    function testFuzz_ApproveStoresAnyAmountAndLatestWins(uint256 first, uint256 second) public {
        assertTrue(token.approve(SPENDER, first));
        assertEq(token.allowance(address(this), SPENDER), first);
        assertTrue(token.approve(SPENDER, second));
        assertEq(token.allowance(address(this), SPENDER), second);
        // Approving is idempotent and never touches balances.
        assertTrue(token.approve(SPENDER, second));
        assertEq(token.allowance(address(this), SPENDER), second);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    /// @dev Allowances are per (owner, spender) pair: granting one never leaks into another.
    function testFuzz_AllowanceIsIsolatedPerPair(address spenderA, address spenderB, uint256 amount) public {
        if (spenderA == address(0)) spenderA = SPENDER;
        if (spenderB == address(0) || spenderB == spenderA) spenderB = address(uint160(spenderA) ^ 1);
        if (spenderB == address(0)) spenderB = BOB;
        token.approve(spenderA, amount);
        assertEq(token.allowance(address(this), spenderA), amount);
        assertEq(token.allowance(address(this), spenderB), 0);
        assertEq(token.allowance(spenderA, address(this)), 0);
        assertEq(token.allowance(ALICE, spenderA), 0);
    }

    /// @dev Any amount strictly above the balance, all the way to the maximum, is rejected exactly.
    function testFuzz_AnyOverdrawRevertsExactly(uint256 rawHeld, uint256 rawAmount) public {
        uint256 held = bound(rawHeld, 0, SUPPLY);
        uint256 amount = bound(rawAmount, held + 1, type(uint256).max);
        token.transfer(ALICE, held);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount)
        );
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        assertEq(token.balanceOf(ALICE), held);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Any amount strictly above a finite allowance, up to the maximum, is rejected exactly.
    function testFuzz_AnyOverAllowanceRevertsExactly(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 allowance = bound(rawAllowance, 0, type(uint256).max - 1);
        uint256 amount = bound(rawAmount, allowance + 1, type(uint256).max);
        token.approve(SPENDER, allowance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowance, amount
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), allowance);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    /// @dev Under an infinite allowance the balance is the only limit, and the allowance never moves.
    function testFuzz_InfiniteAllowanceSpendsUpToBalanceOnly(uint256 rawHeld, uint256 rawAmount) public {
        uint256 held = bound(rawHeld, 0, SUPPLY);
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);

        uint256 amount = bound(rawAmount, 0, held);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(ALICE), held - amount);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);

        uint256 remaining = held - amount;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, ALICE, remaining, remaining + 1
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, remaining + 1);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
    }

    /// @dev Sending and sending back restores both balances exactly: there is no tax or rounding.
    function testFuzz_TransferRoundTripRestoresState(address counterparty, uint256 rawAmount) public {
        if (counterparty == address(0) || counterparty == address(this)) counterparty = ALICE;
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 otherBefore = token.balanceOf(counterparty);
        assertTrue(token.transfer(counterparty, amount));
        vm.prank(counterparty);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(counterparty), otherBefore);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Splitting a payment into two legs delivers the same total as one leg, in either order.
    function testFuzz_SplitTransfersAreOrderIndependent(uint256 rawTotal, uint256 rawSplit) public {
        uint256 total = bound(rawTotal, 0, SUPPLY);
        uint256 first = bound(rawSplit, 0, total);
        uint256 second = total - first;

        BriefsToken other = new BriefsToken();
        assertTrue(token.transfer(ALICE, first));
        assertTrue(token.transfer(ALICE, second));
        assertTrue(other.transfer(ALICE, second));
        assertTrue(other.transfer(ALICE, first));
        assertEq(token.balanceOf(ALICE), total);
        assertEq(other.balanceOf(ALICE), total);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(other.balanceOf(address(this)), SUPPLY - total);
    }

    /// @dev A delegated transfer and a direct transfer of the same amount leave identical ledgers.
    function testFuzz_DelegatedAndDirectTransfersAreEquivalent(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        BriefsToken other = new BriefsToken();
        assertTrue(token.transfer(BOB, amount));
        other.approve(SPENDER, amount);
        vm.prank(SPENDER);
        assertTrue(other.transferFrom(address(this), BOB, amount));
        assertEq(token.balanceOf(BOB), other.balanceOf(BOB));
        assertEq(token.balanceOf(address(this)), other.balanceOf(address(this)));
        assertEq(other.allowance(address(this), SPENDER), 0);
    }

    /// @dev Spending part of a finite allowance leaves exactly the remainder and no more is spendable.
    function testFuzz_FiniteAllowanceIsSpentExactlyOnce(uint256 rawAllowance, uint256 rawSpend) public {
        uint256 allowance = bound(rawAllowance, 0, SUPPLY);
        uint256 spend = bound(rawSpend, 0, allowance);
        token.approve(SPENDER, allowance);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spend));
        uint256 left = allowance - spend;
        assertEq(token.allowance(address(this), SPENDER), left);
        if (left < type(uint256).max) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, left, left + 1
                )
            );
            vm.prank(SPENDER);
            token.transferFrom(address(this), ALICE, left + 1);
        }
        assertEq(token.balanceOf(ALICE), spend);
    }

    /// @dev Whoever deploys receives everything, including when the deployer is a contract or any
    ///      arbitrary address; nobody else receives anything.
    function testFuzz_DeployerIsSoleInitialHolder(address deployer, address observer) public {
        if (deployer == address(0) || deployer == address(vm)) deployer = ALICE;
        if (observer == deployer) observer = address(uint160(deployer) ^ 1);
        vm.prank(deployer);
        BriefsToken fresh = new BriefsToken();
        assertEq(fresh.balanceOf(deployer), SUPPLY);
        assertEq(fresh.balanceOf(observer), 0);
        assertEq(fresh.balanceOf(address(fresh)), 0);
        assertEq(fresh.totalSupply(), SUPPLY);
    }
}
