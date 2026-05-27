// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";

/// @title ILGuardHook - Uniswap V4 Hook for Impermanent Loss Protection
/// @notice A Uniswap V4 hook that provides automatic impermanent loss compensation
///         for full-range liquidity providers using a pre-funded insurance reserve.
/// @dev Final version: sqrtPriceX96-based price-weighted IL calculation,
///      premium tracking via swap fees.
contract ILGuardHook is IHooks {
    using PoolIdLibrary for PoolKey;
    using Hooks for IHooks;
    using BalanceDeltaLibrary for BalanceDelta;

    error NotFullRange();
    error InsufficientReserve();
    error NotPoolManager();
    error HookNotImplemented();

    event PositionSnapshotRecorded(
        PoolId indexed poolId, address indexed lp, uint256 amount0, uint256 amount1, uint160 sqrtPriceX96
    );
    event InsurancePremiumAccrued(PoolId indexed poolId, uint256 amount);
    event ImpermanentLossDetected(
        PoolId indexed poolId,
        address indexed lp,
        uint256 lossAmount,
        uint256 depositValue,
        uint256 withdrawValue,
        uint160 depositPrice,
        uint160 currentPrice
    );
    event ILCompensated(PoolId indexed poolId, address indexed lp, uint256 compensationAmount);

    IPoolManager public immutable poolManager;

    struct PositionSnapshot {
        uint256 amount0;
        uint256 amount1;
        uint160 sqrtPriceX96;
        bool exists;
    }

    struct InsuranceReserve {
        uint256 balance;
        uint256 totalPremiumsAccrued;
    }

    mapping(PoolId => mapping(address => PositionSnapshot)) public positions;
    mapping(PoolId => InsuranceReserve) public reserves;

    uint16 public immutable insuranceBps;
    uint16 public immutable compensationThresholdBps;
    uint160 public constant HOOK_PERMISSIONS = 0x0744;

    constructor(IPoolManager _poolManager, uint16 _insuranceBps, uint16 _compensationThresholdBps) {
        poolManager = _poolManager;
        insuranceBps = _insuranceBps;
        compensationThresholdBps = _compensationThresholdBps;
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    function _resolveLp(address sender, bytes calldata hookData) internal pure returns (address lp) {
        uint256 len = hookData.length;
        if (len == 20) {
            assembly ("memory-safe") { lp := shr(96, calldataload(hookData.offset)) }
        } else if (len == 32) {
            assembly ("memory-safe") { lp := calldataload(hookData.offset) }
        } else if (len >= 64) {
            // abi.encode: address is left-padded in first 32 bytes
            assembly ("memory-safe") { lp := shr(96, calldataload(hookData.offset)) }
        } else if (len >= 40) {
            // abi.encodePacked: 20 bytes address at offset 0
            assembly ("memory-safe") { lp := shr(96, calldataload(hookData.offset)) }
        } else {
            lp = sender;
        }
    }

    function _extractSqrtPriceX96(bytes calldata hookData) internal pure returns (uint160 sqrtPriceX96) {
        uint256 len = hookData.length;
        // abi.encode(address, uint160): 32 + 32 = 64 bytes. Value at bytes 32-63, left-padded.
        // abi.encodePacked(address, uint160): 20 + 20 = 40 bytes. Value at bytes 20-39.
        if (len >= 64) {
            // abi.encode: uint160 is at bytes 32-63 (32 bytes, left-padded)
            assembly ("memory-safe") { sqrtPriceX96 := shr(96, calldataload(add(hookData.offset, 32))) }
        } else if (len >= 40) {
            // abi.encodePacked: uint160 is at bytes 20-39 (20 bytes)
            assembly ("memory-safe") { sqrtPriceX96 := shr(96, calldataload(add(hookData.offset, 20))) }
        }
    }

    function _priceFromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 px192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        return (px192 * 1e18) >> 192;
    }

    function _computePositionValue(uint256 amount0, uint256 amount1, uint160 sqrtPriceX96)
        internal
        pure
        returns (uint256)
    {
        if (sqrtPriceX96 == 0) return amount0 + amount1;
        uint256 price = _priceFromSqrtPriceX96(sqrtPriceX96);
        return (amount0 * price) / 1e18 + amount1;
    }

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (
            params.tickLower != TickMath.minUsableTick(key.tickSpacing)
                || params.tickUpper != TickMath.maxUsableTick(key.tickSpacing)
        ) revert NotFullRange();

        PoolId poolId = key.toId();
        address lp = _resolveLp(sender, hookData);
        int128 a0 = delta.amount0();
        int128 a1 = delta.amount1();
        uint256 amount0 = a0 < 0 ? uint256(int256(0) - int256(a0)) : uint256(int256(a0));
        uint256 amount1 = a1 < 0 ? uint256(int256(0) - int256(a1)) : uint256(int256(a1));
        uint160 depositPrice = _extractSqrtPriceX96(hookData);

        positions[poolId][lp] = PositionSnapshot(amount0, amount1, depositPrice, true);
        emit PositionSnapshotRecorded(poolId, lp, amount0, amount1, depositPrice);
        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4) {
        if (
            params.tickLower != TickMath.minUsableTick(key.tickSpacing)
                || params.tickUpper != TickMath.maxUsableTick(key.tickSpacing)
        ) revert NotFullRange();
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        address lp = _resolveLp(sender, hookData);
        PositionSnapshot memory snapshot = positions[poolId][lp];
        if (!snapshot.exists) return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);

        int128 a0 = delta.amount0();
        int128 a1 = delta.amount1();
        uint256 w0 = a0 < 0 ? uint256(int256(0) - int256(a0)) : uint256(int256(a0));
        uint256 w1 = a1 < 0 ? uint256(int256(0) - int256(a1)) : uint256(int256(a1));
        uint160 currentPrice = _extractSqrtPriceX96(hookData);

        uint256 depositValue = _computePositionValue(snapshot.amount0, snapshot.amount1, snapshot.sqrtPriceX96);
        uint256 withdrawValue = _computePositionValue(w0, w1, currentPrice);

        if (withdrawValue < depositValue) {
            uint256 loss = depositValue - withdrawValue;
            uint256 threshold = (depositValue * compensationThresholdBps) / 10000;
            emit ImpermanentLossDetected(
                poolId, lp, loss, depositValue, withdrawValue, snapshot.sqrtPriceX96, currentPrice
            );

            if (loss > threshold) {
                InsuranceReserve storage reserve = reserves[poolId];
                uint256 compensation = loss > reserve.balance ? reserve.balance : loss;
                if (compensation > 0) {
                    reserve.balance -= compensation;
                    require(
                        IERC20Minimal(Currency.unwrap(key.currency0)).transfer(lp, compensation),
                        "ILGuard: transfer failed"
                    );
                    emit ILCompensated(poolId, lp, compensation);
                }
            }
        }

        delete positions[poolId][lp];
        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // Premium is based on the absolute output amount of the swap.
        // For zeroForOne: output is token1, for oneForZero: output is token0.
        uint256 abs0;
        uint256 abs1;
        unchecked {
            abs0 = amount0 < 0 ? uint256(int256(-amount0)) : uint256(int256(amount0));
            abs1 = amount1 < 0 ? uint256(int256(-amount1)) : uint256(int256(amount1));
        }

        // Premium is charged on the output side
        bool zeroForOne = params.zeroForOne;
        uint256 outputAmount = zeroForOne ? abs1 : abs0;
        Currency outputCurrency = zeroForOne ? key.currency1 : key.currency0;
        int128 hookDelta;
        unchecked {
            hookDelta = int128(int256((outputAmount * insuranceBps) / 10000));
        }

        if (hookDelta > 0) {
            // Take premium tokens from PoolManager into this hook contract.
            // This creates a negative delta (-hookDelta) that cancels with the
            // positive hookDelta returned below → no CurrencyNotSettled.
            poolManager.take(outputCurrency, address(this), uint256(int256(hookDelta)));

            reserves[poolId].balance += uint256(int256(hookDelta));
            reserves[poolId].totalPremiumsAccrued += uint256(int256(hookDelta));
            emit InsurancePremiumAccrued(poolId, uint256(int256(hookDelta)));
        }

        return (IHooks.afterSwap.selector, hookDelta);
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function fundReserve(PoolKey calldata key, uint256 amount) external {
        require(
            IERC20Minimal(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), amount),
            "ILGuard: transferFrom failed"
        );
        reserves[key.toId()].balance += amount;
    }
}
