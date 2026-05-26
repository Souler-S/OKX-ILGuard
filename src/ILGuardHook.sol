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
/// @dev MVP version: full-range only, simplified IL calculation assuming 1:1 initial price,
///      pre-funded reserve model (afterSwap hook fee is tracked but settles deferred).
contract ILGuardHook is IHooks {
    using PoolIdLibrary for PoolKey;
    using Hooks for IHooks;
    using BalanceDeltaLibrary for BalanceDelta;

    // ============ Errors ============

    error NotFullRange();
    error InsufficientReserve();
    error NotPoolManager();
    error HookNotImplemented();

    // ============ Events ============

    event PositionSnapshotRecorded(PoolId indexed poolId, address indexed lp, uint256 amount0, uint256 amount1);
    event InsurancePremiumAccrued(PoolId indexed poolId, uint256 amount);
    event ImpermanentLossDetected(
        PoolId indexed poolId, address indexed lp, uint256 lossAmount, uint256 depositValue, uint256 withdrawValue
    );
    event ILCompensated(PoolId indexed poolId, address indexed lp, uint256 compensationAmount);

    // ============ State ============

    IPoolManager public immutable poolManager;

    struct PositionSnapshot {
        uint256 amount0;
        uint256 amount1;
        bool exists;
    }

    struct InsuranceReserve {
        uint256 balance;
        uint256 totalPremiumsAccrued;
    }

    mapping(PoolId => mapping(address => PositionSnapshot)) public positions;
    mapping(PoolId => InsuranceReserve) public reserves;

    /// @notice Insurance premium in basis points (e.g., 15 = 0.15%)
    uint16 public immutable insuranceBps;
    /// @notice IL compensation threshold in basis points (e.g., 500 = 5%)
    uint16 public immutable compensationThresholdBps;

    /// @notice Hook address permission bits:
    ///   afterAddLiquidity (bit 10) | beforeRemoveLiquidity (bit 9) |
    ///   afterRemoveLiquidity (bit 8) | afterSwap (bit 6) | afterSwapReturnDelta (bit 2)
    uint160 public constant HOOK_PERMISSIONS = 0x0744;

    // ============ Constructor ============

    constructor(IPoolManager _poolManager, uint16 _insuranceBps, uint16 _compensationThresholdBps) {
        poolManager = _poolManager;
        insuranceBps = _insuranceBps;
        compensationThresholdBps = _compensationThresholdBps;
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    /// @dev Resolve real LP from hookData.
    ///      - 20 bytes: raw address (e.g., abi.encodePacked(lp))
    ///      - 32 bytes: ABI-encoded address (e.g., abi.encode(lp))
    ///      - otherwise: fallback to sender (router/PositionManager compatibility)
    function _resolveLp(address sender, bytes calldata hookData) internal pure returns (address lp) {
        uint256 len = hookData.length;
        if (len == 20) {
            // Raw address: 20 bytes → upper 160 bits of calldataload
            assembly ("memory-safe") {
                lp := shr(96, calldataload(hookData.offset))
            }
        } else if (len == 32) {
            // abi.encode(address): address in lower 160 bits of 32-byte word
            assembly ("memory-safe") {
                lp := calldataload(hookData.offset)
            }
        } else {
            lp = sender;
        }
    }

    // ============ Liquidity Hooks ============

    /// @notice Record LP position snapshot when liquidity is added.
    ///         Only full-range positions are accepted.
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta, /* feesAccrued */
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        // Reject non-full-range positions
        if (
            params.tickLower != TickMath.minUsableTick(key.tickSpacing)
                || params.tickUpper != TickMath.maxUsableTick(key.tickSpacing)
        ) {
            revert NotFullRange();
        }

        address lp = _resolveLp(sender, hookData);

        // For add liquidity, delta amounts are NEGATIVE (LP owes tokens to PoolManager).
        // Convert through int256 to safely take absolute value.
        int128 da0 = delta.amount0();
        int128 da1 = delta.amount1();
        uint256 amount0 = da0 < 0 ? uint256(int256(0) - int256(da0)) : uint256(int256(da0));
        uint256 amount1 = da1 < 0 ? uint256(int256(0) - int256(da1)) : uint256(int256(da1));

        positions[key.toId()][lp] = PositionSnapshot({amount0: amount0, amount1: amount1, exists: true});

        emit PositionSnapshotRecorded(key.toId(), lp, amount0, amount1);

        // Return selector and unmodified delta (no hook delta adjustment)
        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /// @notice Pre-remove check: verify full-range. IL is computed in afterRemoveLiquidity.
    function beforeRemoveLiquidity(
        address, /* sender */
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata /* hookData */
    )
        external
        override
        onlyPoolManager
        returns (bytes4)
    {
        if (
            params.tickLower != TickMath.minUsableTick(key.tickSpacing)
                || params.tickUpper != TickMath.maxUsableTick(key.tickSpacing)
        ) {
            revert NotFullRange();
        }

        // IL detection and compensation happen in afterRemoveLiquidity
        // where we have access to the actual withdrawal delta.
        return IHooks.beforeRemoveLiquidity.selector;
    }

    /// @notice Post-remove: detect IL and compensate LP from reserve.
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta, /* feesAccrued */
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        address lp = _resolveLp(sender, hookData);
        PositionSnapshot memory snapshot = positions[poolId][lp];

        if (!snapshot.exists) {
            return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }

        // delta amounts are negative during removal (LP receives tokens).
        // Go through int256 to avoid int128 overflow on negation of type(int128).min.
        int128 a0 = delta.amount0();
        int128 a1 = delta.amount1();
        uint256 withdrawAmount0 = a0 < 0 ? uint256(int256(0) - int256(a0)) : uint256(int256(a0));
        uint256 withdrawAmount1 = a1 < 0 ? uint256(int256(0) - int256(a1)) : uint256(int256(a1));

        // MVP simplified IL calculation:
        // Assumes 1:1 initial price for demo MockERC20 tokens.
        // depositValue ≈ depositAmount0 + depositAmount1
        // withdrawValue ≈ withdrawAmount0 + withdrawAmount1
        //
        // In production, this would use sqrtPriceX96-based computation:
        //   depositValue = amount0 + amount1 / price
        //   withdrawValue = withdrawAmount0 + withdrawAmount1 / price
        uint256 depositValue = snapshot.amount0 + snapshot.amount1;
        uint256 withdrawValue = withdrawAmount0 + withdrawAmount1;

        if (withdrawValue < depositValue) {
            uint256 loss = depositValue - withdrawValue;
            uint256 threshold = (depositValue * compensationThresholdBps) / 10000;

            emit ImpermanentLossDetected(poolId, lp, loss, depositValue, withdrawValue);

            if (loss > threshold) {
                InsuranceReserve storage reserve = reserves[poolId];
                uint256 compensation = loss > reserve.balance ? reserve.balance : loss;
                if (compensation > 0) {
                    reserve.balance -= compensation;
                    // Direct ERC20 transfer from hook reserve to LP (MVP).
                    // The hook holds pre-funded tokens from fundReserve().
                    require(
                        IERC20Minimal(Currency.unwrap(key.currency0)).transfer(lp, compensation),
                        "ILGuard: transfer failed"
                    );
                    emit ILCompensated(poolId, lp, compensation);
                }
            }
        }

        // Clear snapshot after withdrawal
        delete positions[poolId][lp];

        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    // ============ Swap Hooks ============

    /// @notice Track theoretical insurance premium.
    ///         MVP: emit event only. Real hook fee via afterSwapReturnDelta can be enabled later.
    function afterSwap(
        address, /* sender */
        PoolKey calldata key,
        SwapParams calldata, /* params */
        BalanceDelta delta,
        bytes calldata /* hookData */
    )
        external
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();

        // Calculate theoretical premium based on swap output
        // The swap output amounts are in delta (user receives these)
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();
        uint256 outputAmount = uint256(int256(amount0 > 0 ? amount0 : amount1 > 0 ? amount1 : int128(0)));
        uint256 premium = (outputAmount * insuranceBps) / 10000;

        if (premium > 0) {
            reserves[poolId].totalPremiumsAccrued += premium;
            emit InsurancePremiumAccrued(poolId, premium);
        }

        // Return 0 delta (no real hook fee in MVP — uses pre-funded reserve)
        return (IHooks.afterSwap.selector, 0);
    }

    // ============ Unused Hooks (required by IHooks interface, never called) ============

    function beforeInitialize(address, PoolKey calldata, uint160) external override returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external override returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    // ============ Admin Functions ============

    /// @notice Fund the insurance reserve for a pool.
    ///         Caller must first approve token transfer to this contract via IERC20.approve().
    function fundReserve(PoolKey calldata key, uint256 amount) external {
        require(
            IERC20Minimal(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), amount),
            "ILGuard: transferFrom failed"
        );
        reserves[key.toId()].balance += amount;
    }
}
