// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ILGuardHook} from "../src/ILGuardHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";

/// @notice Minimal proxy that acts as the "PoolManager" for testing hooks directly.
///         The real PoolManager deployment is heavy; this lets us unit-test hook logic
///         by impersonating the PoolManager address.
contract MockPoolManager {
    // Exists only so we have a real address to pass as IPoolManager and prank as.
}

contract ILGuardHookTest is Test {
    using PoolIdLibrary for PoolKey;

    ILGuardHook public hook;
    MockPoolManager public mockPM;
    TestERC20 public token0;
    TestERC20 public token1;

    address public lp = makeAddr("lp");
    address public funder = makeAddr("funder");

    uint16 constant INSURANCE_BPS = 15; // 0.15%
    uint16 constant COMPENSATION_THRESHOLD_BPS = 500; // 5%

    // Default tick spacing for tests
    int24 constant DEFAULT_TICK_SPACING = 60;

    // Full-range ticks for tickSpacing=60:
    // minUsableTick(60) = floor(-887272 / 60) * 60 = -887280
    // maxUsableTick(60) = floor(887272 / 60) * 60 = 887280

    function setUp() public {
        mockPM = new MockPoolManager();
        token0 = new TestERC20(1_000_000 ether);
        token1 = new TestERC20(1_000_000 ether);

        hook = new ILGuardHook(IPoolManager(address(mockPM)), INSURANCE_BPS, COMPENSATION_THRESHOLD_BPS);

        // Give tokens to LP and funder
        token0.transfer(lp, 100_000 ether);
        token1.transfer(lp, 100_000 ether);
        token0.transfer(funder, 100_000 ether);
        token1.transfer(funder, 100_000 ether);
    }

    // ============ Helper Functions ============

    function _makePoolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000, // 0.3%
            tickSpacing: DEFAULT_TICK_SPACING,
            hooks: IHooks(address(hook))
        });
    }

    function _makeFullRangeParams(int256 liquidityDelta) internal view returns (ModifyLiquidityParams memory) {
        return ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(DEFAULT_TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(DEFAULT_TICK_SPACING),
            liquidityDelta: liquidityDelta,
            salt: bytes32(0)
        });
    }

    function _makeNonFullRangeParams(int256 liquidityDelta) internal pure returns (ModifyLiquidityParams memory) {
        return
            ModifyLiquidityParams({
                tickLower: -60000, tickUpper: 60000, liquidityDelta: liquidityDelta, salt: bytes32(0)
            });
    }

    /// @notice Create a positive BalanceDelta (LP sends tokens to pool = positive from pool's perspective)
    function _depositDelta(uint128 amount0, uint128 amount1) internal pure returns (BalanceDelta) {
        return toBalanceDelta(int128(amount0), int128(amount1));
    }

    /// @notice Create a negative BalanceDelta (LP receives tokens from pool)
    function _withdrawDelta(uint128 amount0, uint128 amount1) internal pure returns (BalanceDelta) {
        return toBalanceDelta(-int128(amount0), -int128(amount1));
    }

    modifier prankPoolManager() {
        vm.prank(address(mockPM));
        _;
    }

    // ============ Test 1: Full-range afterAddLiquidity records snapshot ============

    function test_afterAddLiquidity_FullRange_RecordsSnapshot() public prankPoolManager {
        PoolKey memory key = _makePoolKey();
        ModifyLiquidityParams memory params = _makeFullRangeParams(int256(100 ether));
        BalanceDelta delta = _depositDelta(100 ether, 100 ether);

        // Expect the event
        vm.expectEmit(true, true, false, true);
        emit ILGuardHook.PositionSnapshotRecorded(key.toId(), lp, 100 ether, 100 ether);

        // Call hook directly (impersonating PoolManager)
        (bytes4 selector, BalanceDelta returnedDelta) =
            hook.afterAddLiquidity(lp, key, params, delta, BalanceDeltaLibrary.ZERO_DELTA, "");

        // Verify return
        assertEq(selector, IHooks.afterAddLiquidity.selector, "wrong selector");
        assertEq(
            BalanceDelta.unwrap(returnedDelta), BalanceDelta.unwrap(BalanceDeltaLibrary.ZERO_DELTA), "delta should be 0"
        );

        // Verify snapshot stored
        (uint256 snap0, uint256 snap1, bool exists) = hook.positions(key.toId(), lp);
        assertEq(snap0, 100 ether, "amount0");
        assertEq(snap1, 100 ether, "amount1");
        assertTrue(exists, "should exist");
    }

    // ============ Test 2: Non-full-range afterAddLiquidity reverts ============

    function test_afterAddLiquidity_NonFullRange_Reverts() public prankPoolManager {
        PoolKey memory key = _makePoolKey();
        ModifyLiquidityParams memory params = _makeNonFullRangeParams(int256(100 ether));
        BalanceDelta delta = _depositDelta(100 ether, 100 ether);

        vm.expectRevert(ILGuardHook.NotFullRange.selector);
        hook.afterAddLiquidity(lp, key, params, delta, BalanceDeltaLibrary.ZERO_DELTA, "");
    }

    // ============ Test 3: Reserve pre-funding works ============

    function test_fundReserve() public {
        PoolKey memory key = _makePoolKey();
        uint256 amount = 1000 ether;

        // Funder approves hook to spend tokens
        vm.prank(funder);
        token0.approve(address(hook), amount);

        // Funder calls fundReserve
        vm.prank(funder);
        hook.fundReserve(key, amount);

        // Check hook received tokens
        assertEq(token0.balanceOf(address(hook)), amount, "hook token balance");

        // Check reserve accounting
        (uint256 balance, uint256 accrued) = hook.reserves(key.toId());
        assertEq(balance, amount, "reserve balance");
        assertEq(accrued, 0, "no premiums yet");
    }

    // ============ Test 4: Not-pool-manager reverts ============

    function test_afterAddLiquidity_NotPoolManager_Reverts() public {
        PoolKey memory key = _makePoolKey();
        ModifyLiquidityParams memory params = _makeFullRangeParams(int256(100 ether));
        BalanceDelta delta = _depositDelta(100 ether, 100 ether);

        // NOT pranking as pool manager
        vm.expectRevert(ILGuardHook.NotPoolManager.selector);
        hook.afterAddLiquidity(lp, key, params, delta, BalanceDeltaLibrary.ZERO_DELTA, "");
    }

    // ============ Test 5: afterRemoveLiquidity with no snapshot returns early ============

    function test_afterRemoveLiquidity_NoSnapshot_ReturnsGracefully() public prankPoolManager {
        PoolKey memory key = _makePoolKey();
        ModifyLiquidityParams memory params = _makeFullRangeParams(-int256(50 ether));
        BalanceDelta delta = _withdrawDelta(50 ether, 50 ether);

        // No snapshot was recorded for this LP → should return gracefully
        (bytes4 selector, BalanceDelta returnedDelta) =
            hook.afterRemoveLiquidity(lp, key, params, delta, BalanceDeltaLibrary.ZERO_DELTA, "");

        assertEq(selector, IHooks.afterRemoveLiquidity.selector, "wrong selector");
        assertEq(BalanceDelta.unwrap(returnedDelta), BalanceDelta.unwrap(BalanceDeltaLibrary.ZERO_DELTA));
    }

    // ============ Test 6: Full comp flow (add → fund → remove with IL) ============

    function test_fullILDetectionAndCompensation() public {
        // 1. LP adds full-range liquidity → snapshot recorded
        PoolKey memory key = _makePoolKey();
        ModifyLiquidityParams memory addParams = _makeFullRangeParams(int256(100 ether));
        BalanceDelta depositDelta = _depositDelta(100 ether, 100 ether);

        vm.prank(address(mockPM));
        hook.afterAddLiquidity(lp, key, addParams, depositDelta, BalanceDeltaLibrary.ZERO_DELTA, "");

        // 2. Fund reserve with 10 ether of token0
        uint256 reserveAmount = 10 ether;
        vm.prank(funder);
        token0.approve(address(hook), reserveAmount);
        vm.prank(funder);
        hook.fundReserve(key, reserveAmount);

        // 3. LP removes liquidity → simulate IL (withdraw 94 token0 + 94 token1 vs deposit 100+100)
        //    depositValue = 200, withdrawValue = 188, loss = 12
        //    threshold = 200 * 500 / 10000 = 10 ether → loss(12) > threshold(10) → trigger!
        ModifyLiquidityParams memory removeParams = _makeFullRangeParams(-int256(100 ether));
        BalanceDelta withdrawDelta = _withdrawDelta(94 ether, 94 ether);

        uint256 lpBalanceBefore = token0.balanceOf(lp);

        vm.expectEmit(true, true, false, true);
        emit ILGuardHook.ImpermanentLossDetected(key.toId(), lp, 12 ether, 200 ether, 188 ether);

        vm.expectEmit(true, true, false, true);
        emit ILGuardHook.ILCompensated(key.toId(), lp, 10 ether); // capped to reserve balance

        vm.prank(address(mockPM));
        hook.afterRemoveLiquidity(lp, key, removeParams, withdrawDelta, BalanceDeltaLibrary.ZERO_DELTA, "");

        // Verify reserve decreased
        (uint256 balanceAfter,) = hook.reserves(key.toId());
        assertEq(balanceAfter, 0, "reserve should be drained");

        // Verify LP received compensation (direct ERC20 transfer from hook)
        // LP balance: unchanged during deposit (direct hook call), +10 ether compensation
        assertEq(token0.balanceOf(lp), lpBalanceBefore + 10 ether, "LP should have received compensation");
        // Verify hook balance decreased
        assertEq(token0.balanceOf(address(hook)), 0, "hook reserve should be empty");
    }
}
