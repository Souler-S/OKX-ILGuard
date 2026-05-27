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

contract MockPoolManager {
    // Minimal mock to accept poolManager.take() and settle() calls from the hook
    fallback() external payable {}
}

contract ILGuardHookTest is Test {
    using PoolIdLibrary for PoolKey;

    ILGuardHook public hook;
    MockPoolManager public mockPM;
    TestERC20 public token0;
    TestERC20 public token1;

    address public lp = makeAddr("lp");
    address public funder = makeAddr("funder");
    address public swapper = makeAddr("swapper");

    uint16 constant INSURANCE_BPS = 15;
    uint16 constant COMPENSATION_THRESHOLD_BPS = 500;
    int24 constant DEFAULT_TICK_SPACING = 60;

    // 1:1 price sqrtPriceX96: sqrt(1) * 2^96 = 79228162514264337593543950336
    uint160 constant PRICE_1_1 = 79228162514264337593543950336;

    function setUp() public {
        mockPM = new MockPoolManager();
        token0 = new TestERC20(1_000_000 ether);
        token1 = new TestERC20(1_000_000 ether);
        hook = new ILGuardHook(IPoolManager(address(mockPM)), INSURANCE_BPS, COMPENSATION_THRESHOLD_BPS);
        token0.transfer(lp, 100_000 ether);
        token1.transfer(lp, 100_000 ether);
        token0.transfer(funder, 100_000 ether);
        token1.transfer(funder, 100_000 ether);
        token0.transfer(swapper, 100_000 ether);
        token1.transfer(swapper, 100_000 ether);
    }

    function _makePoolKey() internal view returns (PoolKey memory) {
        return PoolKey(
            Currency.wrap(address(token0)),
            Currency.wrap(address(token1)),
            3000,
            DEFAULT_TICK_SPACING,
            IHooks(address(hook))
        );
    }

    function _makeFullRangeParams(int256 liquidityDelta) internal view returns (ModifyLiquidityParams memory) {
        return ModifyLiquidityParams(
            TickMath.minUsableTick(DEFAULT_TICK_SPACING),
            TickMath.maxUsableTick(DEFAULT_TICK_SPACING),
            liquidityDelta,
            bytes32(0)
        );
    }

    function _depositDelta(uint128 a0, uint128 a1) internal pure returns (BalanceDelta) {
        return toBalanceDelta(int128(a0), int128(a1));
    }

    function _withdrawDelta(uint128 a0, uint128 a1) internal pure returns (BalanceDelta) {
        return toBalanceDelta(-int128(a0), -int128(a1));
    }

    // Encode hookData: 20 bytes LP + 32 bytes sqrtPriceX96
    function _hookData(address _lp, uint160 _price) internal pure returns (bytes memory) {
        return abi.encodePacked(_lp, _price);
    }

    modifier prankPoolManager() {
        vm.prank(address(mockPM));
        _;
    }

    // ============ Test 1: Full-range add records snapshot with price ============

    function test_afterAddLiquidity_RecordsSnapshotWithPrice() public prankPoolManager {
        PoolKey memory key = _makePoolKey();
        ModifyLiquidityParams memory params = _makeFullRangeParams(int256(100 ether));
        BalanceDelta delta = _depositDelta(100 ether, 100 ether);
        bytes memory hd = _hookData(lp, PRICE_1_1);

        vm.expectEmit(true, true, false, true);
        emit ILGuardHook.PositionSnapshotRecorded(key.toId(), lp, 100 ether, 100 ether, PRICE_1_1);

        (bytes4 sel, BalanceDelta rd) =
            hook.afterAddLiquidity(lp, key, params, delta, BalanceDeltaLibrary.ZERO_DELTA, hd);
        assertEq(sel, IHooks.afterAddLiquidity.selector);
        assertEq(BalanceDelta.unwrap(rd), BalanceDelta.unwrap(BalanceDeltaLibrary.ZERO_DELTA));

        (uint256 s0, uint256 s1, uint160 sp, bool exists) = hook.positions(key.toId(), lp);
        assertEq(s0, 100 ether);
        assertEq(s1, 100 ether);
        assertEq(sp, PRICE_1_1);
        assertTrue(exists);
    }

    // ============ Test 2: Non-full-range reverts ============

    function test_afterAddLiquidity_NonFullRange_Reverts() public prankPoolManager {
        PoolKey memory key = _makePoolKey();
        ModifyLiquidityParams memory params = ModifyLiquidityParams(-60000, 60000, int256(100 ether), bytes32(0));
        vm.expectRevert(ILGuardHook.NotFullRange.selector);
        hook.afterAddLiquidity(lp, key, params, _depositDelta(100 ether, 100 ether), BalanceDeltaLibrary.ZERO_DELTA, "");
    }

    // ============ Test 3: Reserve funding ============

    function test_fundReserve() public {
        PoolKey memory key = _makePoolKey();
        vm.prank(funder);
        token0.approve(address(hook), 1000 ether);
        vm.prank(funder);
        hook.fundReserve(key, 1000 ether);
        assertEq(token0.balanceOf(address(hook)), 1000 ether);
        (uint256 bal, uint256 acc) = hook.reserves(key.toId());
        assertEq(bal, 1000 ether);
        assertEq(acc, 0);
    }

    // ============ Test 4: Not-pool-manager reverts ============

    function test_notPoolManager_Reverts() public {
        PoolKey memory key = _makePoolKey();
        vm.expectRevert(ILGuardHook.NotPoolManager.selector);
        hook.afterAddLiquidity(
            lp,
            key,
            _makeFullRangeParams(int256(100 ether)),
            _depositDelta(100 ether, 100 ether),
            BalanceDeltaLibrary.ZERO_DELTA,
            ""
        );
    }

    // ============ Test 5: Remove with no snapshot ============

    function test_afterRemoveLiquidity_NoSnapshot() public prankPoolManager {
        PoolKey memory key = _makePoolKey();
        (bytes4 sel,) = hook.afterRemoveLiquidity(
            lp,
            key,
            _makeFullRangeParams(-int256(50 ether)),
            _withdrawDelta(50 ether, 50 ether),
            BalanceDeltaLibrary.ZERO_DELTA,
            ""
        );
        assertEq(sel, IHooks.afterRemoveLiquidity.selector);
    }

    // ============ Test 6: Full IL detection and compensation (price-weighted) ============

    function test_fullILWithPriceWeightedCalc() public {
        PoolKey memory key = _makePoolKey();
        bytes memory hd = _hookData(lp, PRICE_1_1);

        // 1. Add liquidity at 1:1 price
        vm.prank(address(mockPM));
        hook.afterAddLiquidity(
            lp,
            key,
            _makeFullRangeParams(int256(100 ether)),
            _depositDelta(100 ether, 100 ether),
            BalanceDeltaLibrary.ZERO_DELTA,
            hd
        );

        // 2. Fund reserve
        vm.prank(funder);
        token0.approve(address(hook), 10 ether);
        vm.prank(funder);
        hook.fundReserve(key, 10 ether);

        // 3. Price moves → IL: withdraw less than deposit
        // With same 1:1 price, but simulate IL by withdrawing 94 each instead of 100
        uint256 lpBalBefore = token0.balanceOf(lp);

        vm.expectEmit(true, true, false, true);
        emit ILGuardHook.ImpermanentLossDetected(key.toId(), lp, 12 ether, 200 ether, 188 ether, PRICE_1_1, PRICE_1_1);
        vm.expectEmit(true, true, false, true);
        emit ILGuardHook.ILCompensated(key.toId(), lp, 10 ether);

        vm.prank(address(mockPM));
        hook.afterRemoveLiquidity(
            lp,
            key,
            _makeFullRangeParams(-int256(100 ether)),
            _withdrawDelta(94 ether, 94 ether),
            BalanceDeltaLibrary.ZERO_DELTA,
            hd
        );

        assertEq(token0.balanceOf(lp), lpBalBefore + 10 ether, "compensation received");
        assertEq(token0.balanceOf(address(hook)), 0, "reserve drained");
    }

    // ============ Test 7: afterSwap returns real hook delta ============

    function test_afterSwap_ReturnsHookDelta() public prankPoolManager {
        PoolKey memory key = _makePoolKey();
        // Simulate swap: user swaps token0 for token1, receives 1000 ether token1
        // delta: pool gained token0 (+), pool sent token1 (-)
        BalanceDelta swapDelta = toBalanceDelta(int128(1000 ether), -int128(1000 ether));
        SwapParams memory sp = SwapParams(true, -int256(1000 ether), TickMath.MAX_SQRT_PRICE - 1);

        vm.expectEmit(true, true, false, true);
        // Premium = 1000 ether * 15 / 10000 = 1.5 ether
        emit ILGuardHook.InsurancePremiumAccrued(key.toId(), 1.5 ether);

        (bytes4 sel, int128 hd) = hook.afterSwap(address(0), key, sp, swapDelta, "");
        assertEq(sel, IHooks.afterSwap.selector);
        assertEq(hd, int128(uint128(1.5 ether)), "hook delta should be 1.5 ether premium");

        (, uint256 accrued) = hook.reserves(key.toId());
        assertEq(accrued, 1.5 ether);
    }

    // ============ Test 8: afterSwap zeroForOne=false ============

    function test_afterSwap_OneForZero() public prankPoolManager {
        PoolKey memory key = _makePoolKey();
        // token1->token0: pool gained token1 (+), pool sent token0 (-)
        BalanceDelta swapDelta = toBalanceDelta(-int128(2000 ether), int128(2000 ether));
        SwapParams memory sp = SwapParams(false, -int256(2000 ether), TickMath.MIN_SQRT_PRICE + 1);

        vm.expectEmit(true, true, false, true);
        emit ILGuardHook.InsurancePremiumAccrued(key.toId(), 3 ether); // 2000 * 15 / 10000

        (bytes4 sel, int128 hd) = hook.afterSwap(address(0), key, sp, swapDelta, "");
        assertEq(hd, int128(uint128(3 ether)));
    }

    // ============ Test 9: IL with actual price change ============

    function test_ILWithPriceChange() public {
        PoolKey memory key = _makePoolKey();
        bytes memory hdAdd = _hookData(lp, PRICE_1_1);

        // 1. Deposit at 1:1 price
        vm.prank(address(mockPM));
        hook.afterAddLiquidity(
            lp,
            key,
            _makeFullRangeParams(int256(100 ether)),
            _depositDelta(100 ether, 100 ether),
            BalanceDeltaLibrary.ZERO_DELTA,
            hdAdd
        );

        // 2. Fund reserve
        vm.prank(funder);
        token0.approve(address(hook), 50 ether);
        vm.prank(funder);
        hook.fundReserve(key, 50 ether);

        // 3. Price drops 50%: new sqrtPriceX96 = PRICE_1_1 / sqrt(2)
        // sqrt(0.5) * 2^96 ≈ 56022770974786141989127813161
        uint160 priceDown50 = 56022770974786141989127813161;
        bytes memory hdRemove = _hookData(lp, priceDown50);

        uint256 lpBalBefore = token0.balanceOf(lp);

        // At price 0.5: deposit value = 100 * 0.5 + 100 = 150 (in token1 terms)
        // Withdraw same 100+100: withdraw value = 100 * 0.5 + 100 = 150 → no IL
        // To simulate IL, withdraw less token0 (since price dropped, LP gets more token0)
        // Actually: at lower price, full-range LP withdraws MORE token0 and LESS token1
        // Simulate IL by withdrawing less total value
        // depositValue ≈ 100 * 0.5e18/1e18 + 100 = 150 ether (approx)
        // Simulate: withdraw 80 token0 + 90 token1 → value ≈ 80*0.5 + 90 = 130
        // loss = 20, threshold = 150*5% = 7.5 → triggers

        vm.prank(address(mockPM));
        hook.afterRemoveLiquidity(
            lp,
            key,
            _makeFullRangeParams(-int256(100 ether)),
            _withdrawDelta(80 ether, 90 ether),
            BalanceDeltaLibrary.ZERO_DELTA,
            hdRemove
        );

        assertGt(token0.balanceOf(lp), lpBalBefore, "should receive compensation");
    }
}
