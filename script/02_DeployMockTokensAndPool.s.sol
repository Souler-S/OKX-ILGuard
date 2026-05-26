// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SortTokens} from "v4-test-utils/SortTokens.sol";

/// @notice Step 2: Deploy two MockERC20 tokens, sort into currency0/1,
///         and initialize a V4 pool bound to ILGuardHook.
///         Prerequisite: 01_DeployILGuard must have been run and hook address recorded.
contract DeployMockTokensAndPool is Script {
    using PoolIdLibrary for PoolKey;
    using Hooks for IHooks;

    address constant POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;

    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    // sqrtPriceX96 for 1:1 price
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() external {
        string memory rpcUrl = vm.envString("XLAYER_MAINNET_RPC_URL");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address hookAddr = vm.envAddress("ILGUARD_HOOK_ADDRESS");

        // Derive deployer address from private key and verify it matches expected
        address deployer = vm.addr(deployerKey);
        address expectedDeployer = vm.envAddress("DEPLOYER_ADDRESS");
        require(deployer == expectedDeployer, "deployer key/address mismatch");

        console.log("=== Deploy Mock Tokens + Initialize Pool ===");
        console.log("RPC:", rpcUrl);
        console.log("Deployer:", deployer);
        console.log("ILGuardHook:", hookAddr);

        // Verify hook address has correct permissions
        require(uint160(hookAddr) & 0x3FFF == 0x0744, "hook address has wrong permission bits");

        vm.createSelectFork(rpcUrl);
        vm.startBroadcast(deployerKey);

        // 1. Deploy mock ERC20 tokens (18 decimals, 1M initial supply)
        //    Mint to explicit deployer address, NOT msg.sender.
        MockERC20 tokenA = new MockERC20("MockTokenA", "MTKA", 18);
        tokenA.mint(deployer, 1_000_000 ether);
        MockERC20 tokenB = new MockERC20("MockTokenB", "MTKB", 18);
        tokenB.mint(deployer, 1_000_000 ether);

        require(tokenA.balanceOf(deployer) == 1_000_000 ether, "tokenA mint failed");
        require(tokenB.balanceOf(deployer) == 1_000_000 ether, "tokenB mint failed");

        // 2. Sort tokens
        (Currency currency0, Currency currency1) = SortTokens.sort(tokenA, tokenB);

        console.log("Token0:", vm.toString(Currency.unwrap(currency0)));
        console.log("Token1:", vm.toString(Currency.unwrap(currency1)));

        // 3. Create pool key with hook
        PoolKey memory key = PoolKey(currency0, currency1, POOL_FEE, TICK_SPACING, IHooks(hookAddr));
        PoolId poolId = key.toId();

        // 4. Initialize pool
        IPoolManager(POOL_MANAGER).initialize(key, SQRT_PRICE_1_1);

        vm.stopBroadcast();

        console.log("=== Pool Initialized ===");
        console.log("PoolId:");
        console.logBytes32(PoolId.unwrap(poolId));
        console.log("Token0 addr:", vm.toString(Currency.unwrap(currency0)));
        console.log("Token1 addr:", vm.toString(Currency.unwrap(currency1)));
        console.log("Fee:", POOL_FEE);
        console.log("TickSpacing:", TICK_SPACING);
    }
}
