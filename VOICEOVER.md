# OKX-ILGuard Voiceover

This is a ready-to-record voiceover script for the demo video. Target length: about 2 minutes.

---

Every liquidity provider in DeFi faces the same fear: impermanent loss.

You deposit two tokens into a pool. The price moves. And when you withdraw, you may end up with less value than if you had simply held the assets.

OKX-ILGuard is a Uniswap V4 Hook that turns a pool into an insured liquidity pool on X Layer.

The idea is simple: when an LP adds liquidity, the Hook records a snapshot. When swaps happen, the Hook records insurance premium accounting. When liquidity is removed, the Hook can compare the withdrawal against the original deposit and compensate the LP from an insurance reserve if the loss exceeds the threshold.

This uses Uniswap V4 Hooks exactly where they matter: after add liquidity, after swap, before remove liquidity, and after remove liquidity. Without Hooks, this would require a separate wrapper around the pool. With Hooks, the protection becomes part of the pool lifecycle itself.

Now for the mainnet proof.

The OKX-ILGuard Hook is deployed on X Layer mainnet at this address:

0x043b00Ae5d234e6c34107D60bFb663e7088a8744.

The V4 pool is initialized with this PoolId:

0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186.

We funded the insurance reserve with 10 token0 on-chain.

Then we ran the demo lifecycle on X Layer mainnet.

First, add liquidity. The Hook emitted PositionSnapshotRecorded, with the LP set to the deployer wallet.

Second, swap. The Hook's afterSwap callback fired and emitted InsurancePremiumAccrued. The reserve accounting now shows a positive total premium accrued from the real swap.

Third, remove liquidity. The position snapshot was cleared, proving the afterRemoveLiquidity lifecycle executed through the real PoolManager.

For honesty: this MVP uses a simplified one-to-one additive impermanent loss formula. The real mainnet add, swap, and remove lifecycle is verified. The compensation branch is demonstrated in the Forge test suite with a controlled impermanent-loss delta, where the Hook emits ImpermanentLossDetected and ILCompensated, and transfers token0 from the reserve to the LP.

The immediate upgrade is a sqrtPriceX96-based price-weighted impermanent loss calculation, plus real afterSwapReturnDelta fee collection into the reserve.

All contracts are deployed. The V4 pool is live. The Hook lifecycle is proven on X Layer. Tests pass.

OKX-ILGuard makes X Layer the place where LPs can provide liquidity with protection built into the pool.
