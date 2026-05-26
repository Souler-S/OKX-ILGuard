# OKX-ILGuard Short Voiceover

Every liquidity provider in DeFi faces the same fear: impermanent loss.

You add two tokens to a pool. The price moves. And when you withdraw, you may have less value than if you simply held.

OKX-ILGuard is a Uniswap V4 Hook that turns a pool into an insured liquidity pool on X Layer.

The Hook works across the pool lifecycle.

After add liquidity, it records the LP snapshot.

After swap, it records insurance premium accounting.

Before remove liquidity, it enforces the MVP full-range position rule.

After remove liquidity, it can detect loss and pay compensation from the reserve.

This is exactly why V4 Hooks matter. Without Hooks, this would require a fragile wrapper around every pool interaction. With Hooks, protection becomes native to the pool.

Now the mainnet proof.

The OKX-ILGuard Hook is deployed on X Layer at:

0x043b00Ae5d234e6c34107D60bFb663e7088a8744.

The V4 PoolId is:

0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186.

The reserve is funded on-chain with 10 token0.

In the demo transaction, add liquidity emitted PositionSnapshotRecorded with the LP set to the deployer wallet.

Then a real swap triggered afterSwap and emitted InsurancePremiumAccrued.

Then remove liquidity completed the full add, swap, remove lifecycle and cleared the position snapshot.

For honesty: the MVP uses a simplified one-to-one additive impermanent loss formula. The mainnet lifecycle is real. The compensation branch is demonstrated in Forge tests with a controlled IL delta, where the Hook emits ImpermanentLossDetected and ILCompensated, and transfers token0 from the reserve to the LP.

The next upgrade is a sqrtPriceX96 price-weighted IL formula, plus real afterSwapReturnDelta fee collection into the reserve.

All contracts are deployed. The pool is live. Tests pass.

OKX-ILGuard makes X Layer the place where LPs can provide liquidity with protection built into the pool.
