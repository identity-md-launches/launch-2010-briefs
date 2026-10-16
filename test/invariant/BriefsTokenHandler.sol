// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BriefsToken} from "../../src/BriefsToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "../helpers/TestBase.sol";

/// @dev Contract-shaped holder so the actor set mixes EOAs and contracts (a pool, a distributor,
///      a vault would all be contracts). It holds tokens; it does nothing clever.
contract ContractHolder {}

/// @notice Drives BriefsToken with bounded inputs from a fixed set of actors and keeps an
///         independent ghost model of balances, allowances and cumulative flows.
/// @dev The handler is the token's deployer, so it stands where the launch factory stands and
///      holds the full supply at the start of every run. Every handler function is clamped so that
///      the calls it *expects* to succeed cannot revert for a trivial reason, and the calls it
///      *expects* to fail are caught and checked. The invariant suite runs with fail-on-revert so
///      an unexpected revert anywhere is itself a failure.
contract BriefsTokenHandler is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    BriefsToken public immutable token;

    /// @dev Tracked accounts: 0 = this handler (the deployer), 1..5 = EOAs, 6 = a contract holder,
    ///      7 = the token's own address (tokens sent there are stranded, but still exist).
    address[] public actors;

    // ---- ghost state -------------------------------------------------------------------------
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;
    mapping(address => uint256) public ghostReceived;
    mapping(address => uint256) public ghostSent;
    uint256 public ghostVolume;

    // ---- call accounting ---------------------------------------------------------------------
    uint256 public transfers;
    uint256 public selfTransfers;
    uint256 public zeroValueTransfers;
    uint256 public fullBalanceTransfers;
    uint256 public approvals;
    uint256 public infiniteApprovals;
    uint256 public delegatedTransfers;
    uint256 public rejectedOverdraws;
    uint256 public rejectedOverAllowance;
    uint256 public rejectedZeroRecipients;
    uint256 public rejectedZeroSpenders;
    uint256 public adminAttempts;
    uint256 public adminSuccesses;
    uint256 public rejectedNativeDeposits;

    constructor() {
        token = new BriefsToken();
        actors.push(address(this));
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA201));
        actors.push(address(0xDA7E));
        actors.push(address(0xE4A));
        actors.push(address(new ContractHolder()));
        actors.push(address(token));
        ghostBalance[address(this)] = SUPPLY;
        ghostReceived[address(this)] = SUPPLY;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // ---- clamped, expected-to-succeed actions ------------------------------------------------

    /// @dev Plain transfer of any amount the sender can afford, including zero and the full balance.
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        if (from == address(token)) from = address(this); // the token cannot act; nobody holds its key
        uint256 balance = token.balanceOf(from);
        uint256 amount = bound(rawAmount, 0, balance);
        uint256 toBefore = token.balanceOf(to);

        vm.prank(from);
        bool ok = token.transfer(to, amount);
        assertTrue(ok, "transfer returned false");

        if (from == to) {
            assertEq(token.balanceOf(from), balance, "self-transfer changed the balance");
            selfTransfers++;
        } else {
            assertEq(token.balanceOf(from), balance - amount, "sender debited the wrong amount");
            assertEq(token.balanceOf(to), toBefore + amount, "recipient credited the wrong amount");
        }
        if (amount == 0) zeroValueTransfers++;
        if (amount == balance && balance > 0) fullBalanceTransfers++;
        _recordMove(from, to, amount);
        transfers++;
    }

    /// @dev Approve any amount at all, including the infinite sentinel, from any actor to any other.
    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address owner = _actor(ownerSeed);
        if (owner == address(token)) owner = address(this);
        address spender = _actor(spenderSeed);
        // Three in sixteen approvals are infinite so delegated transfers exercise that branch.
        uint256 amount = (rawAmount % 16 < 3) ? type(uint256).max : bound(rawAmount, 0, SUPPLY);

        vm.prank(owner);
        bool ok = token.approve(spender, amount);
        assertTrue(ok, "approve returned false");
        assertEq(token.allowance(owner, spender), amount, "allowance not replaced");

        ghostAllowance[owner][spender] = amount;
        approvals++;
        if (amount == type(uint256).max) infiniteApprovals++;
    }

    /// @dev Delegated transfer bounded by both the owner's balance and the spender's allowance.
    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount)
        external
    {
        address owner = _actor(ownerSeed);
        if (owner == address(token)) owner = address(this);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowance = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        uint256 cap = allowance < balance ? allowance : balance;
        uint256 amount = bound(rawAmount, 0, cap);
        uint256 toBefore = token.balanceOf(to);

        vm.prank(spender);
        bool ok = token.transferFrom(owner, to, amount);
        assertTrue(ok, "transferFrom returned false");

        if (allowance == type(uint256).max) {
            assertEq(token.allowance(owner, spender), allowance, "infinite allowance was consumed");
        } else {
            assertEq(token.allowance(owner, spender), allowance - amount, "allowance not reduced exactly");
            ghostAllowance[owner][spender] = allowance - amount;
        }
        if (owner == to) {
            assertEq(token.balanceOf(owner), balance, "self transferFrom changed the balance");
        } else {
            assertEq(token.balanceOf(owner), balance - amount, "owner debited the wrong amount");
            assertEq(token.balanceOf(to), toBefore + amount, "recipient credited the wrong amount");
        }
        _recordMove(owner, to, amount);
        delegatedTransfers++;
    }

    // ---- expected-to-fail actions: the failure paths ------------------------------------------

    /// @dev Spending more than the balance must revert with the exact ERC-6093 error and leave
    ///      every balance where it was.
    function transferOverdraw(uint256 fromSeed, uint256 toSeed, uint256 rawExcess) external {
        address from = _actor(fromSeed);
        if (from == address(token)) from = address(this);
        address to = _actor(toSeed);
        uint256 balance = token.balanceOf(from);
        uint256 amount = balance + bound(rawExcess, 1, type(uint256).max - balance);
        uint256 toBefore = token.balanceOf(to);

        vm.prank(from);
        try token.transfer(to, amount) returns (bool) {
            revert("overdraw did not revert");
        } catch (bytes memory reason) {
            assertEq(
                reason,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        }
        assertEq(token.balanceOf(from), balance, "overdraw changed the sender balance");
        assertEq(token.balanceOf(to), toBefore, "overdraw changed the recipient balance");
        rejectedOverdraws++;
    }

    /// @dev Spending above a finite allowance, or above the balance under an infinite one, reverts
    ///      and restores both the allowance and the balances.
    function transferFromOverLimit(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawExcess)
        external
    {
        address owner = _actor(ownerSeed);
        if (owner == address(token)) owner = address(this);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowance = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);

        bytes memory expected;
        uint256 amount;
        if (allowance < type(uint256).max) {
            amount = allowance + bound(rawExcess, 1, type(uint256).max - allowance);
            expected = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount
            );
        } else {
            amount = balance + bound(rawExcess, 1, type(uint256).max - balance);
            expected = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount
            );
        }

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) returns (bool) {
            revert("over-limit transferFrom did not revert");
        } catch (bytes memory reason) {
            assertEq(reason, expected);
        }
        assertEq(token.allowance(owner, spender), allowance, "failed transferFrom changed the allowance");
        assertEq(token.balanceOf(owner), balance, "failed transferFrom changed the owner balance");
        assertEq(token.balanceOf(to), toBefore, "failed transferFrom changed the recipient balance");
        rejectedOverAllowance++;
    }

    /// @dev The zero address can never receive, so nothing is ever burned by accident.
    function transferToZero(uint256 fromSeed, uint256 rawAmount, bool delegated) external {
        address from = _actor(fromSeed);
        if (from == address(token)) from = address(this);
        uint256 balance = token.balanceOf(from);
        uint256 amount = bound(rawAmount, 0, balance);
        bytes memory expected = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));

        if (delegated) {
            // Grant exactly what is needed so the receiver check, not the allowance, is what fails.
            vm.prank(from);
            token.approve(address(this), amount);
            ghostAllowance[from][address(this)] = amount;
            try token.transferFrom(from, address(0), amount) returns (bool) {
                revert("transferFrom to zero did not revert");
            } catch (bytes memory reason) {
                assertEq(reason, expected);
            }
            assertEq(token.allowance(from, address(this)), amount, "allowance not restored");
        } else {
            vm.prank(from);
            try token.transfer(address(0), amount) returns (bool) {
                revert("transfer to zero did not revert");
            } catch (bytes memory reason) {
                assertEq(reason, expected);
            }
        }
        assertEq(token.balanceOf(from), balance, "rejected transfer to zero changed the balance");
        rejectedZeroRecipients++;
    }

    /// @dev Approving the zero spender is rejected and leaves the owner's other allowances intact.
    function approveZeroSpender(uint256 ownerSeed, uint256 rawAmount) external {
        address owner = _actor(ownerSeed);
        if (owner == address(token)) owner = address(this);
        vm.prank(owner);
        try token.approve(address(0), rawAmount) returns (bool) {
            revert("approve of zero spender did not revert");
        } catch (bytes memory reason) {
            assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        }
        assertEq(token.allowance(owner, address(0)), 0, "zero spender gained an allowance");
        rejectedZeroSpenders++;
    }

    /// @dev Privileged-looking selectors from any actor, the deployer included, must all fail and
    ///      must not move a single unit or change the supply.
    function adminAttempt(uint256 callerSeed, uint256 selectorSeed, uint256 targetSeed, uint256 rawAmount)
        external
    {
        address caller = _actor(callerSeed);
        if (caller == address(token)) caller = address(this);
        address target = _actor(targetSeed);
        uint256 supplyBefore = token.totalSupply();
        uint256 targetBefore = token.balanceOf(target);
        uint256 callerBefore = token.balanceOf(caller);

        bytes memory data = _adminCalldata(selectorSeed % 16, target, rawAmount);
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        if (ok) adminSuccesses++;

        assertEq(token.totalSupply(), supplyBefore, "an admin selector changed the supply");
        assertEq(token.balanceOf(target), targetBefore, "an admin selector moved a holder's balance");
        assertEq(token.balanceOf(caller), callerBefore, "an admin selector paid its caller");
        adminAttempts++;
    }

    /// @dev Native currency never enters the token, with or without calldata.
    function donateNative(uint256 rawAmount, bool withCalldata) external {
        uint256 amount = bound(rawAmount, 1, 1_000 ether);
        vm.deal(address(this), amount);
        (bool ok,) = withCalldata
            ? address(token).call{value: amount}(abi.encodeCall(token.totalSupply, ()))
            : address(token).call{value: amount}("");
        assertFalse(ok, "the token accepted native currency");
        assertEq(address(token).balance, 0, "the token holds native currency");
        rejectedNativeDeposits++;
    }

    // ---- internals ---------------------------------------------------------------------------

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _recordMove(address from, address to, uint256 amount) internal {
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostSent[from] += amount;
        ghostReceived[to] += amount;
        ghostVolume += amount;
    }

    function _adminCalldata(uint256 which, address target, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        if (which == 0) return abi.encodeWithSignature("mint(address,uint256)", target, amount);
        if (which == 1) return abi.encodeWithSignature("mint(uint256)", amount);
        if (which == 2) return abi.encodeWithSignature("burn(uint256)", amount);
        if (which == 3) return abi.encodeWithSignature("burnFrom(address,uint256)", target, amount);
        if (which == 4) return abi.encodeWithSignature("pause()");
        if (which == 5) return abi.encodeWithSignature("blacklist(address)", target);
        if (which == 6) return abi.encodeWithSignature("freeze(address)", target);
        if (which == 7) return abi.encodeWithSignature("seize(address)", target);
        if (which == 8) return abi.encodeWithSignature("transferOwnership(address)", target);
        if (which == 9) return abi.encodeWithSignature("upgradeTo(address)", target);
        if (which == 10) return abi.encodeWithSignature("initialize(address)", target);
        if (which == 11) return abi.encodeWithSignature("setMinter(address)", target);
        if (which == 12) return abi.encodeWithSignature("setBlacklist(address,bool)", target, true);
        if (which == 13) return abi.encodeWithSignature("disableTransfers()");
        if (which == 14) return abi.encodeWithSignature("owner()");
        return abi.encodeWithSignature("increaseAllowance(address,uint256)", target, amount);
    }
}
