// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BriefsToken} from "../src/BriefsToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./helpers/TestBase.sol";

contract BriefsTokenTest is TestBase {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    // Local test actors only; no production deployment uses these addresses.
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    BriefsToken internal token;

    function setUp() public {
        token = new BriefsToken();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Briefs");
        assertEq(token.symbol(), "BRIEFS");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ConstructorEmitsFullSupplyMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new BriefsToken();
    }

    function test_TransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 123 ether);
        assertTrue(token.transfer(ALICE, 123 ether));
        assertEq(token.balanceOf(ALICE), 123 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_CanTransferEntireSupplyAndReturnIt() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_ZeroTransferFromEmptyAccountSucceedsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToZeroRevertsWithoutBurning() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferToZeroStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_InsufficientBalanceRevertsAtomically() public {
        token.transfer(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10, 11));
        vm.prank(ALICE);
        token.transfer(BOB, 11);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxUintTransferCannotOverflowOrMint() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventAndDoesNotMoveBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 77 ether);
        assertTrue(token.approve(SPENDER, 77 ether));
        assertEq(token.allowance(address(this), SPENDER), 77 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    function test_ApprovalReplacementAndRevocation() public {
        token.approve(SPENDER, 100);
        token.approve(SPENDER, 40);
        assertEq(token.allowance(address(this), SPENDER), 40);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 0);
        assertTrue(token.approve(SPENDER, 0));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 100);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_HolderWithoutBalanceCanApproveForFutureReceipts() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 20));
        token.transfer(ALICE, 20);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 20));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 20);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_TransferFromSpendsExactAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 60);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 60));
        assertEq(token.allowance(address(this), SPENDER), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY - 60);
        assertEq(token.balanceOf(ALICE), 60);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 40));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 100);
    }

    function test_InfiniteAllowanceRemainsUntilRevoked() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 100));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 200));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        token.approve(SPENDER, 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_UnapprovedSpenderCannotUseAnotherSpendersAllowance() public {
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_DeployerCannotSpendHolderTokensWithoutApproval() public {
        token.transfer(ALICE, 100);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1)
        );
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
    }

    function test_TransferFromInsufficientBalanceRestoresAllowance() public {
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(SPENDER, 20);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10, 20));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 20);
        assertEq(token.allowance(ALICE, SPENDER), 20);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_TransferFromZeroRecipientRestoresAllowance() public {
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroSenderRejectedEvenForZeroTransferFrom() public {
        // Allowance accounting validates the source before the transfer's sender check.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_TransferFromToSameHolderConsumesAllowanceWithoutCreatingTokens() public {
        token.approve(SPENDER, 100);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 100));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NativeCurrencyAndUnknownCallsAreRejected() public {
        vm.deal(address(this), 1 ether);
        (bool paid,) = address(token).call{value: 1 ether}("");
        assertFalse(paid);
        assertEq(address(token).balance, 0);
        (bool unknown,) = address(token).call(hex"12345678");
        assertFalse(unknown);
    }

    function testFuzz_ConstructorMintsOnlyToDeployer(address deployer) public {
        vm.assume(deployer != address(0) && deployer != address(vm));
        vm.prank(deployer);
        BriefsToken deployed = new BriefsToken();
        assertEq(deployed.balanceOf(deployer), SUPPLY);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = rawAmount % (SUPPLY + 1);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SelfTransferCannotCreateTokens(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransferConservesSupply(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approved = rawApproval % (SUPPLY + 1);
        uint256 amount = rawAmount % (approved + 1);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approved - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverAllowanceRevertsWithoutChangingState(uint256 rawApproval) public {
        uint256 approved = rawApproval % SUPPLY;
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, approved + 1
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, approved + 1);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverBalanceRevertsWithoutChangingState(uint256 rawBalance) public {
        uint256 held = rawBalance % (SUPPLY + 1);
        token.transfer(ALICE, held);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, held + 1)
        );
        vm.prank(ALICE);
        token.transfer(BOB, held + 1);
        assertEq(token.balanceOf(ALICE), held);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Exercise mixed transfers and delegated transfers against an independent balance model.
    function testFuzz_MixedTransferSequenceConservesEveryBalance(uint256[32] memory actions) public {
        address[4] memory actors = [address(this), ALICE, BOB, SPENDER];
        uint256[4] memory model = [SUPPLY, uint256(0), uint256(0), uint256(0)];
        for (uint256 i; i < actions.length; ++i) {
            uint256 action = actions[i];
            uint256 from = action % actors.length;
            uint256 to = (action >> 8) % actors.length;
            uint256 amount = (action >> 16) % (model[from] + 1);
            if ((action & 4) == 0) {
                vm.prank(actors[from]);
                assertTrue(token.transfer(actors[to], amount));
            } else {
                address spender = actors[(from + 1) % actors.length];
                vm.prank(actors[from]);
                assertTrue(token.approve(spender, amount));
                vm.prank(spender);
                assertTrue(token.transferFrom(actors[from], actors[to], amount));
                assertEq(token.allowance(actors[from], spender), 0);
            }
            model[from] -= amount;
            model[to] += amount;
            uint256 sum;
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.balanceOf(actors[j]), model[j]);
                sum += token.balanceOf(actors[j]);
            }
            assertEq(sum, SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
        }
    }
}
