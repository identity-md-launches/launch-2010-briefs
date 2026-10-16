// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Briefs (BRIEFS)
/// @notice A fixed-supply, 18-decimal ERC-20, minted once to its deployer.
/// @dev During the custom-token launch, msg.sender is the launch factory.
///      There are no external mint, burn, administrative, or upgrade functions.
contract BriefsToken is ERC20 {
    /// @notice One billion BRIEFS, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Briefs", "BRIEFS") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
