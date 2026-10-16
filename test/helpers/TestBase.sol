// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Only the Foundry cheatcodes used by this project's tests.
interface Vm {
    function prank(address sender) external;
    function assume(bool condition) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function deal(address account, uint256 balance) external;
}

/// @dev Self-contained test assertions; no runtime dependency on forge-std.
abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool actual) internal pure {
        require(actual, "expected true");
    }

    function assertTrue(bool actual, string memory reason) internal pure {
        require(actual, reason);
    }

    function assertFalse(bool actual) internal pure {
        require(!actual, "expected false");
    }

    function assertFalse(bool actual, string memory reason) internal pure {
        require(!actual, reason);
    }

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "uint256 mismatch");
    }

    function assertEq(uint256 actual, uint256 expected, string memory reason) internal pure {
        require(actual == expected, reason);
    }

    function assertEq(address actual, address expected) internal pure {
        require(actual == expected, "address mismatch");
    }

    function assertEq(bool actual, bool expected) internal pure {
        require(actual == expected, "bool mismatch");
    }

    function assertEq(bytes memory actual, bytes memory expected) internal pure {
        require(keccak256(actual) == keccak256(expected), "bytes mismatch");
    }

    function assertEq(string memory actual, string memory expected) internal pure {
        require(keccak256(bytes(actual)) == keccak256(bytes(expected)), "string mismatch");
    }

    function assertLe(uint256 actual, uint256 bound_) internal pure {
        require(actual <= bound_, "expected <=");
    }

    function assertLe(uint256 actual, uint256 bound_, string memory reason) internal pure {
        require(actual <= bound_, reason);
    }

    function assertGe(uint256 actual, uint256 bound_) internal pure {
        require(actual >= bound_, "expected >=");
    }

    function assertGt(uint256 actual, uint256 bound_) internal pure {
        require(actual > bound_, "expected >");
    }

    /// @dev Maps an arbitrary fuzz input into [min, max] without discarding runs. Like forge-std's
    ///      `bound`, the lowest and highest raw inputs land on the edges of the range so the fuzzer's
    ///      favourite values (0, 1, max) reach the boundaries of the constrained domain.
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        require(min <= max, "bound: min > max");
        if (x >= min && x <= max) return x;
        uint256 size = max - min + 1;
        // Full range requested: every input is already inside it.
        if (size == 0) return x;
        if (x <= 3 && size > x) return min + x;
        if (x >= type(uint256).max - 3 && size > type(uint256).max - x) {
            return max - (type(uint256).max - x);
        }
        if (x > max) {
            uint256 diff = x - max;
            uint256 rem = diff % size;
            if (rem == 0) return max;
            return min + rem - 1;
        }
        // x < min
        uint256 diffLow = min - x;
        uint256 remLow = diffLow % size;
        if (remLow == 0) return min;
        return max - remLow + 1;
    }
}
