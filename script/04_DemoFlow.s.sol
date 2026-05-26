// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ILGuardHook} from "../src/ILGuardHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

/// @notice Step 4: Demo flow on X Layer mainnet.
///         Deploys test routers, executes add → swap → remove lifecycle,
///         and outputs events/addresses for demo video recording.
///
///         Prerequisites: Step 1 (Hook deployed), Step 2 (Tokens + Pool), Step 3 (Reserve funded).
///
///         IMPORTANT: The MVP's simplified IL formula cannot detect price-weighted IL
///         after real swaps. The ILCompensated event is demonstrated via forge test
///         (test_integration_directRemove_WithHookData_CompensatesRealLp) using a
///         controlled synthetic withdrawal delta. This demo proves the real PoolManager
///         add/swap/remove lifecycle fires PositionSnapshotRecorded and InsurancePremiumAccrued.
contract DemoFlow is Script {
    using PoolIdLibrary for PoolKey;

    address constant POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;

    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    function run() external {
        string memory rpcUrl = vm.envString("XLAYER_MAINNET_RPC_URL");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address hookAddr = vm.envAddress("ILGUARD_HOOK_ADDRESS");
        address token0Addr = vm.envAddress("MOCK_TOKEN0_ADDRESS");
        address token1Addr = vm.envAddress("MOCK_TOKEN1_ADDRESS");

        console.log("=== Demo Flow ===");
        console.log("Deployer:", deployer);
        console.log("Hook:", hookAddr);

        require(token0Addr < token1Addr, "tokens must be sorted");

        Currency currency0 = Currency.wrap(token0Addr);
        Currency currency1 = Currency.wrap(token1Addr);
        PoolKey memory key = PoolKey(currency0, currency1, POOL_FEE, TICK_SPACING, IHooks(hookAddr));
        PoolId poolId = key.toId();

        vm.createSelectFork(rpcUrl);
        vm.startBroadcast(deployerKey);

        // --- 1. Deploy demo routers ---
        PoolModifyLiquidityTest modifyRouter = new PoolModifyLiquidityTest(IPoolManager(POOL_MANAGER));
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(POOL_MANAGER));

        // Approve routers to spend deployer's tokens
        MockERC20(token0Addr).approve(address(modifyRouter), type(uint256).max);
        MockERC20(token1Addr).approve(address(modifyRouter), type(uint256).max);
        MockERC20(token0Addr).approve(address(swapRouter), type(uint256).max);
        MockERC20(token1Addr).approve(address(swapRouter), type(uint256).max);

        console.log("ModifyRouter:", address(modifyRouter));
        console.log("SwapRouter:", address(swapRouter));

        // --- 2. Add full-range liquidity (LP = deployer via hookData) ---
        console.log("");
        console.log("--- Adding Liquidity (LP = deployer) ---");
        bytes memory hookData = abi.encode(deployer);
        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: 10 ether,
            salt: bytes32(0)
        });
        modifyRouter.modifyLiquidity(key, addParams, hookData);
        console.log("[EVENT] PositionSnapshotRecorded (LP = deployer)");

        // --- 3. Execute swap ---
        console.log("");
        console.log("--- Swapping ---");
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, amountSpecified: -int256(0.1 ether), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        swapRouter.swap(key, swapParams, PoolSwapTest.TestSettings(false, false), new bytes(0));
        console.log("[EVENT] InsurancePremiumAccrued should appear in tx logs");

        // --- 4. Remove liquidity ---
        console.log("");
        console.log("--- Removing Liquidity ---");
        ModifyLiquidityParams memory removeParams = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: -10 ether,
            salt: bytes32(0)
        });
        modifyRouter.modifyLiquidity(key, removeParams, hookData);
        console.log("Remove liquidity completed (MVP: no IL compensation due to additive formula)");

        vm.stopBroadcast();

        // --- Summary ---
        console.log("");
        console.log("=== Demo Complete ===");
        console.log("Events fired on mainnet:");
        console.log("  1. PositionSnapshotRecorded -- add liquidity tx");
        console.log("  2. InsurancePremiumAccrued  -- swap tx");
        console.log("");
        console.log("ILCompensated event is demonstrated via forge test:");
        console.log("  forge test --match-test test_integration_directRemove_WithHookData_CompensatesRealLp -vvv");
        console.log("");
        console.log("PoolKey info:");
        console.log("  PoolId:");
        console.logBytes32(PoolId.unwrap(poolId));
        console.log("  Token0:", token0Addr);
        console.log("  Token1:", token1Addr);
        console.log("  Hook:", hookAddr);
    }
}
