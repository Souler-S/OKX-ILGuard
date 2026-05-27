// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ILGuardHook} from "../src/ILGuardHook.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {Constants} from "v4-test-utils/Constants.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SortTokens} from "v4-test-utils/SortTokens.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

/// @title ILGuardHook Integration Test — Real PoolManager + CREATE2 HookMiner
contract ILGuardHookIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;
    using Hooks for IHooks;
    using StateLibrary for IPoolManager;

    // Hook permission bits for ILGuardHook:
    // afterAddLiquidity (1<<10) | beforeRemoveLiquidity (1<<9) | afterRemoveLiquidity (1<<8)
    // | afterSwap (1<<6) | afterSwapReturnDelta (1<<2)
    uint160 constant HOOK_PERMISSIONS = 0x0744;

    uint16 constant INSURANCE_BPS = 15;
    uint16 constant COMPENSATION_THRESHOLD_BPS = 500;

    // Pool params
    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;
    uint160 constant SQRT_PRICE_1_1 = Constants.SQRT_PRICE_1_1;

    IPoolManager internal manager;
    PoolModifyLiquidityTest internal modifyLiquidityRouter;
    PoolSwapTest internal swapRouter;
    ILGuardHook internal hook;
    MockERC20 internal token0;
    MockERC20 internal token1;
    Currency internal currency0;
    Currency internal currency1;
    PoolKey internal key;
    PoolId internal poolId;

    bytes internal constant ZERO_BYTES = new bytes(0);

    address internal realLp;

    // ============ Setup ============

    function setUp() public {
        realLp = makeAddr("realLp");
        // 1. Deploy PoolManager (this contract is feeController)
        manager = new PoolManager(address(this));

        // 2. Deploy test routers
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        swapRouter = new PoolSwapTest(manager);

        // 3. Deploy and sort tokens (using solmate MockERC20 to match V4 test pattern)
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        (currency0, currency1) = SortTokens.sort(token0, token1);

        // Unwrap to get the sorted addresses
        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        // 4. Mine hook address with CREATE2 and deploy
        _deployHookWithMinedAddress();

        // 5. Verify the deployed hook address has correct permission bits
        assertTrue(
            uint160(address(hook)) & 0x3FFF == HOOK_PERMISSIONS, "hook address bits must EXACTLY match permissions"
        );

        // 6. Initialize pool with hook
        key = PoolKey(currency0, currency1, POOL_FEE, TICK_SPACING, IHooks(address(hook)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // 7. Mint tokens to this test contract (acting as LP) and approve router
        token0.mint(address(this), 1_000_000 ether);
        token1.mint(address(this), 1_000_000 ether);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
    }

    // ============ HookMiner ============

    function _deployHookWithMinedAddress() internal {
        bytes memory creationCode = type(ILGuardHook).creationCode;
        bytes memory constructorArgs =
            abi.encode(IPoolManager(address(manager)), INSURANCE_BPS, COMPENSATION_THRESHOLD_BPS);
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 bytecodeHash = keccak256(bytecode);

        uint256 salt = 0;
        address hookAddr;
        uint256 count;
        while (count < 100_000) {
            hookAddr = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), bytecodeHash))))
            );

            if (uint160(hookAddr) & 0x3FFF == HOOK_PERMISSIONS) {
                console.log("HookMiner: found salt after", count + 1, "attempts");
                console.log("Hook address:", hookAddr);
                break;
            }
            unchecked {
                salt++;
                count++;
            }
        }
        require(uint160(hookAddr) & 0x3FFF == HOOK_PERMISSIONS, "HookMiner: failed to find valid salt in 100k");

        // Deploy via CREATE2 from this test contract
        hook = new ILGuardHook{salt: bytes32(salt)}(
            IPoolManager(address(manager)), INSURANCE_BPS, COMPENSATION_THRESHOLD_BPS
        );

        require(address(hook) == hookAddr, "HookMiner: deployed address mismatch");
    }

    // ============ Integration Test: Pool init + Hook binding ============

    function test_integration_poolInitializedWithHook() public view {
        // Pool should exist and have the hook bound
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);
        assertEq(sqrtPriceX96, SQRT_PRICE_1_1, "pool not initialized correctly");
        assertEq(address(key.hooks), address(hook), "hook not bound to pool");
    }

    // ============ Test: Full-range add (fallback: empty hookData → sender = router as LP) ============

    function test_integration_fullRangeAddLiquidity_SnapshotRecorded() public {
        int256 liquidityDelta = 10 ether;
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: liquidityDelta,
            salt: bytes32(0)
        });

        // Empty hookData → _resolveLp falls back to sender (router)
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        (uint256 snap0, uint256 snap1, uint160 snapPrice, bool exists) = hook.positions(poolId, address(modifyLiquidityRouter));
        assertTrue(exists, "snapshot should exist after add liquidity");
        assertGt(snap0, 0, "amount0 should be > 0");
        assertGt(snap1, 0, "amount1 should be > 0");
    }

    // ============ Test: Full-range add with hookData=realLp → snapshot stored under realLp ============

    function test_integration_addLiquidity_WithHookData_RecordsRealLp() public {
        int256 liquidityDelta = 10 ether;
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: liquidityDelta,
            salt: bytes32(0)
        });

        bytes memory hookData = abi.encode(realLp);
        modifyLiquidityRouter.modifyLiquidity(key, params, hookData);

        // Snapshot should be under realLp, NOT under router
        (uint256 snap0, uint256 snap1, uint160 _p, bool exists) = hook.positions(poolId, realLp);
        assertTrue(exists, "snapshot should exist under realLp");
        assertGt(snap0, 0, "amount0 > 0");
        assertGt(snap1, 0, "amount1 > 0");

        // Router should NOT have a snapshot
        (,,, bool routerExists) = hook.positions(poolId, address(modifyLiquidityRouter));
        assertFalse(routerExists, "router should NOT have snapshot");
    }

    // ============ Test: Non-full-range add liquidity REVERTS ============

    function test_integration_nonFullRangeAddLiquidity_Reverts() public {
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -60000, tickUpper: 60000, liquidityDelta: 10 ether, salt: bytes32(0)});
        vm.expectRevert();
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);
    }

    // ============ Test: IL compensation via direct hook call with hookData=realLp ============

    function test_integration_directRemove_WithHookData_CompensatesRealLp() public {
        // 1. Add liquidity via PoolManager with hookData=realLp
        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: 10 ether,
            salt: bytes32(0)
        });
        modifyLiquidityRouter.modifyLiquidity(key, addParams, abi.encode(realLp));

        // 2. Read snapshot for realLp
        (uint256 snap0, uint256 snap1, uint160 _p, bool exists) = hook.positions(poolId, realLp);
        require(exists, "snapshot must exist for realLp");

        // 3. Fund reserve
        uint256 reserveAmount = 10 ether;
        token0.mint(address(this), reserveAmount);
        token0.approve(address(hook), reserveAmount);
        hook.fundReserve(key, reserveAmount);

        // 4. Simulate IL: withdraw 80% of deposit value
        uint256 depositValue = snap0 + snap1;
        uint256 lossAmount = depositValue / 10;
        uint256 withdrawValueSimulated = depositValue - lossAmount;
        uint256 ratio0 = (snap0 * 1e18) / depositValue;
        uint256 w0 = (withdrawValueSimulated * ratio0) / 1e18;
        uint256 w1 = withdrawValueSimulated - w0;

        ModifyLiquidityParams memory removeParams = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: -int256(100 ether),
            salt: bytes32(0)
        });

        BalanceDelta withdrawDelta = toBalanceDelta(-int128(int256(w0)), -int128(int256(w1)));

        // realLp doesn't have tokens yet — mint some so we can check compensation
        token0.mint(realLp, 100 ether);
        uint256 lpBalanceBefore = token0.balanceOf(realLp);

        uint256 expectedCompensation = lossAmount > reserveAmount ? reserveAmount : lossAmount;

        vm.expectEmit(true, true, false, true);
        emit ILGuardHook.ImpermanentLossDetected(poolId, realLp, lossAmount, depositValue, withdrawValueSimulated, uint160(0), uint160(0));
        vm.expectEmit(true, true, false, true);
        emit ILGuardHook.ILCompensated(poolId, realLp, expectedCompensation);

        // Call afterRemoveLiquidity with hookData=realLp, prank as PoolManager
        vm.prank(address(manager));
        hook.afterRemoveLiquidity(
            address(modifyLiquidityRouter),
            key,
            removeParams,
            withdrawDelta,
            BalanceDeltaLibrary.ZERO_DELTA,
            abi.encode(realLp)
        );

        // Verify compensation went to realLp, NOT router
        assertEq(token0.balanceOf(realLp), lpBalanceBefore + expectedCompensation, "realLp compensated");
        (uint256 balanceAfter,) = hook.reserves(poolId);
        assertEq(balanceAfter, reserveAmount - expectedCompensation, "reserve drained");
    }

    // ============ Test: Real PoolManager remove liquidity attempt ============

    function test_integration_realPoolManagerRemove_TriggersAfterRemove() public {
        // 1. Add full-range liquidity through real PoolManager
        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: 10 ether,
            salt: bytes32(0)
        });
        modifyLiquidityRouter.modifyLiquidity(key, addParams, ZERO_BYTES);

        // 2. Verify snapshot exists (proves add side worked)
        (uint256 snap0, uint256 snap1, uint160 snapPrice, bool exists) = hook.positions(poolId, address(modifyLiquidityRouter));
        require(exists && snap0 > 0 && snap1 > 0, "add must record snapshot");

        // 3. Remove liquidity through real PoolManager (same amounts, no IL scenario)
        ModifyLiquidityParams memory removeParams = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: -10 ether, // full withdrawal
            salt: bytes32(0)
        });

        // This calls through: PoolModifyLiquidityTest → PoolManager.unlock → modifyLiquidity
        // → hook.beforeRemoveLiquidity → pool state mutation → hook.afterRemoveLiquidity
        modifyLiquidityRouter.modifyLiquidity(key, removeParams, ZERO_BYTES);

        // 4. After real remove, snapshot should be cleared
        (,,, bool existsAfter) = hook.positions(poolId, address(modifyLiquidityRouter));
        assertFalse(existsAfter, "snapshot cleared after real PM remove");
    }

    // ============ Test: Real swap through PoolSwapTest triggers afterSwap ============

    function test_integration_realSwap_TriggersAfterSwapAndPremiumAccrued() public {
        // 1. Add full-range liquidity first (so pool has tokens to swap)
        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: 10 ether,
            salt: bytes32(0)
        });
        modifyLiquidityRouter.modifyLiquidity(key, addParams, ZERO_BYTES);

        // 2. Read current sqrtPrice before swap
        (uint160 sqrtPriceBefore,,,) = manager.getSlot0(poolId);

        // 3. Execute a real swap: 0.1 ether token0 → token1 (exact input)
        uint256 swapAmount = 0.1 ether;
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, // token0 → token1
            amountSpecified: -int256(swapAmount), // negative = exact input
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (, uint256 premiumsBefore) = hook.reserves(poolId);

        swapRouter.swap(key, swapParams, PoolSwapTest.TestSettings(false, false), ZERO_BYTES);

        // 4. Verify afterSwap was triggered: totalPremiumsAccrued increased
        (, uint256 totalPremiums) = hook.reserves(poolId);
        assertGt(totalPremiums, premiumsBefore, "totalPremiumsAccrued should increase after swap");

        // 5. Verify price changed
        (uint160 sqrtPriceAfter,,,) = manager.getSlot0(poolId);
        assertTrue(sqrtPriceAfter != sqrtPriceBefore, "sqrtPrice should change after swap");
    }

    // ============ Test: Full close loop — add → swap → remove (no IL compensation in MVP) ============
    // The real PoolManager lifecycle (add → swap → remove) is fully exercised,
    // but the MVP's simplified 1:1 additive IL formula (amount0+amount1) does NOT detect
    // price-weighted impermanent loss after swaps. IL compensation is separately verified
    // via test_integration_directRemove_WithHookData_CompensatesRealLp using synthetic delta.

    function test_integration_fullCloseLoop_AddSwapRemove_NoCompensationDueToMvpFormula() public {
        // 1. Add full-range liquidity
        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: 10 ether,
            salt: bytes32(0)
        });
        modifyLiquidityRouter.modifyLiquidity(key, addParams, ZERO_BYTES);

        // 2. Read deposit snapshot
        (uint256 snap0, uint256 snap1, uint160 snapPrice, bool snapExists) = hook.positions(poolId, address(modifyLiquidityRouter));
        uint256 depositValue = snap0 + snap1;

        // 3. Fund insurance reserve
        uint256 reserveAmount = 10 ether;
        token0.mint(address(this), reserveAmount);
        token0.approve(address(hook), reserveAmount);
        hook.fundReserve(key, reserveAmount);

        (uint256 reserveBefore,) = hook.reserves(poolId);
        assertEq(reserveBefore, reserveAmount, "reserve should be funded");

        // 4. Execute a real swap to move price (creates IL for full-range LP, but MVP formula can't detect)
        uint256 swapAmount = 1 ether;
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, amountSpecified: -int256(swapAmount), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        swapRouter.swap(key, swapParams, PoolSwapTest.TestSettings(false, false), ZERO_BYTES);

        // 5. Verify afterSwap recorded theoretical premiums
        (, uint256 premiumsAfterSwap) = hook.reserves(poolId);
        assertGt(premiumsAfterSwap, 0, "premiums should be accrued after real swap");

        // 6. Remove liquidity through real PoolManager
        ModifyLiquidityParams memory removeParams = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: -10 ether,
            salt: bytes32(0)
        });
        modifyLiquidityRouter.modifyLiquidity(key, removeParams, ZERO_BYTES);

        // 7. Snapshot cleared (proves afterRemoveLiquidity executed)
        (,,, bool existsAfter) = hook.positions(poolId, address(modifyLiquidityRouter));
        assertFalse(existsAfter, "snapshot should be cleared after remove");

        // 8. Reserve unchanged — proves no compensation occurred (MVP formula limitation)
        (uint256 reserveAfter,) = hook.reserves(poolId);
        assertEq(reserveAfter, reserveBefore, "reserve should NOT change (no IL detected by MVP formula)");

        console.log("Deposit value (snap0+snap1):", depositValue);
        console.log("Reserve unchanged:", reserveBefore, "->", reserveAfter);
        console.log("Premiums accrued:", premiumsAfterSwap);
    }

    // ============ Integration Test: Hook address permission validation ============

    function test_integration_hookAddressHasCorrectPermissions() public view {
        // Verify each required permission bit is set
        assertTrue(uint160(address(hook)) & (1 << 10) != 0, "afterAddLiquidity bit missing");
        assertTrue(uint160(address(hook)) & (1 << 9) != 0, "beforeRemoveLiquidity bit missing");
        assertTrue(uint160(address(hook)) & (1 << 8) != 0, "afterRemoveLiquidity bit missing");
        assertTrue(uint160(address(hook)) & (1 << 6) != 0, "afterSwap bit missing");
        assertTrue(uint160(address(hook)) & (1 << 2) != 0, "afterSwapReturnDelta bit missing");

        // Verify that PoolManager's validation passes (isValidHookAddress)
        assertTrue(
            Hooks.isValidHookAddress(IHooks(address(hook)), POOL_FEE), "PoolManager would reject this hook address"
        );
    }
}
