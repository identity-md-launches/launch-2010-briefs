// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BriefsToken} from "../src/BriefsToken.sol";
import {TestBase} from "./helpers/TestBase.sol";

/// @dev Test-only contract actor. It models token custody, not a pool or a distributor implementation.
contract TokenActor {
    function send(BriefsToken token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

/// @dev Test-only deployer: verifies that an immediate contract caller receives the supply.
contract FactoryFixture is TokenActor {
    function deploy() external returns (BriefsToken) {
        return new BriefsToken();
    }

    function deployDeterministically(bytes32 salt) external returns (BriefsToken) {
        return new BriefsToken{salt: salt}();
    }

    function invoke(BriefsToken token, bytes calldata data) external returns (bool success) {
        (success,) = address(token).call(data);
    }
}

contract BriefsLaunchTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    FactoryFixture internal factory;
    BriefsToken internal token;

    function setUp() public {
        factory = new FactoryFixture();
        token = factory.deploy();
    }

    function test_ContractDeployerReceivesEntireSupply() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_Create2DeploymentNeedsNoArgumentsOrExternalConfiguration() public {
        bytes32 salt = keccak256("Briefs local deployment test");
        bytes32 codeHash = keccak256(type(BriefsToken).creationCode);
        // CREATE2 uses the low 160 bits of the hash by specification.
        // forge-lint: disable-next-line(unsafe-typecast)
        address predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, codeHash))))
        );
        BriefsToken deployed = factory.deployDeterministically(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_LaunchAllocationsAndSubsequentTokenFlowsDeliverExactAmounts() public {
        TokenActor distributor = new TokenActor();
        TokenActor poolCustodian = new TokenActor();
        TokenActor requester = new TokenActor();
        TokenActor claimant = new TokenActor();
        TokenActor trader = new TokenActor();

        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY / 2;
        uint256 requesterShare = SUPPLY - swarmShare - poolShare;
        assertTrue(factory.send(token, address(distributor), swarmShare));
        assertTrue(factory.send(token, address(poolCustodian), poolShare));
        assertTrue(factory.send(token, address(requester), requesterShare));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(address(distributor)), swarmShare);
        assertEq(token.balanceOf(address(poolCustodian)), poolShare);
        assertEq(token.balanceOf(address(requester)), requesterShare);

        assertTrue(distributor.send(token, address(claimant), swarmShare));
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(token.balanceOf(address(claimant)), swarmShare);

        // Model only the BRIEFS leg of a buy/sell. Real AMM settlement is the protected harness's job.
        assertTrue(poolCustodian.send(token, address(trader), 123 ether));
        assertEq(token.balanceOf(address(trader)), 123 ether);
        assertEq(token.balanceOf(address(poolCustodian)), poolShare - 123 ether);
        assertTrue(trader.send(token, address(poolCustodian), 123 ether));
        assertEq(token.balanceOf(address(trader)), 0);
        assertEq(token.balanceOf(address(poolCustodian)), poolShare);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(
            token.balanceOf(address(claimant)) + token.balanceOf(address(poolCustodian))
                + token.balanceOf(address(requester)),
            SUPPLY
        );
    }

    function test_NoMintUpgradeBurnOrHolderControlFromFactoryOrStranger() public {
        TokenActor holder = new TokenActor();
        TokenActor receiver = new TokenActor();
        uint256 held = 1_000 ether;
        factory.send(token, address(holder), held);

        bytes[] memory attempts = new bytes[](24);
        attempts[0] = abi.encodeWithSignature("mint(address,uint256)", address(this), 1 ether);
        attempts[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        attempts[2] = abi.encodeWithSignature("mint()");
        attempts[3] = abi.encodeWithSignature("issue(uint256)", 1 ether);
        attempts[4] = abi.encodeWithSignature("setOwner(address)", address(this));
        attempts[5] = abi.encodeWithSignature("transferOwnership(address)", address(this));
        attempts[6] = abi.encodeWithSignature("upgradeTo(address)", address(this));
        attempts[7] = abi.encodeWithSignature("initialize(address)", address(this));
        attempts[8] = abi.encodeWithSignature("setMinter(address)", address(this));
        attempts[9] = abi.encodeWithSignature("pause()");
        attempts[10] = abi.encodeWithSignature("unpause()");
        attempts[11] = abi.encodeWithSignature("blacklist(address)", address(holder));
        attempts[12] = abi.encodeWithSignature("blocklist(address)", address(holder));
        attempts[13] = abi.encodeWithSignature("freeze(address)", address(holder));
        attempts[14] = abi.encodeWithSignature("freezeAccount(address)", address(holder));
        attempts[15] = abi.encodeWithSignature("setBlacklist(address,bool)", address(holder), true);
        attempts[16] = abi.encodeWithSignature("setBlocked(address,bool)", address(holder), true);
        attempts[17] = abi.encodeWithSignature("lock(address)", address(holder));
        attempts[18] = abi.encodeWithSignature("disableTransfers()");
        attempts[19] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        attempts[20] = abi.encodeWithSignature("burnFrom(address,uint256)", address(holder), held);
        attempts[21] = abi.encodeWithSignature("seize(address)", address(holder));
        attempts[22] = abi.encodeWithSignature("burn(uint256)", held);
        attempts[23] = abi.encodeWithSignature("owner()");

        for (uint256 i; i < attempts.length; ++i) {
            assertFalse(factory.invoke(token, attempts[i]));
            (bool strangerSucceeded,) = address(token).call(attempts[i]);
            assertFalse(strangerSucceeded);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(address(holder)), held);
            assertEq(token.balanceOf(address(this)), 0);
            assertEq(token.balanceOf(address(factory)), SUPPLY - held);
        }
        assertFalse(
            factory.invoke(
                token, abi.encodeCall(token.transferFrom, (address(holder), address(factory), uint256(1)))
            )
        );
        assertTrue(holder.send(token, address(receiver), held));
        assertEq(token.balanceOf(address(holder)), 0);
        assertEq(token.balanceOf(address(receiver)), held);
    }

    function test_RuntimeFitsDeploymentLimitAndHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertTrue(runtime.length > 0 && runtime.length <= 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }
}
