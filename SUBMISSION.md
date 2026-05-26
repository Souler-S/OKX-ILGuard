# OKX-ILGuard — Impermanent Loss Protection for Uniswap V4 on X Layer

**Build X Hackathon — Hook Edition**
OKX X Layer × Uniswap × Flap

---

## Project Name

**OKX-ILGuard**

## One-Liner

On-chain impermanent loss compensation for Uniswap V4 liquidity providers on X Layer.

## Problem

Impermanent loss (IL) is the #1 reason liquidity providers leave decentralized exchanges. Every LP who adds liquidity knows: if the price moves, you may end up with less value than if you had just held the tokens. There is no built-in protection mechanism in any Uniswap version — until V4 Hooks.

## Solution

OKX-ILGuard is a Uniswap V4 Hook that automatically compensates LPs for impermanent loss. When an LP withdraws liquidity, the Hook compares the current withdrawal value against the original deposit snapshot. If the LP has lost more than a configurable threshold (5% in MVP), the Hook transfers compensation directly from a pre-funded insurance reserve.

## Why Uniswap V4 Hooks Are Necessary

Impermanent loss compensation requires logic at **three pool lifecycle points**:

1. **afterAddLiquidity** — snapshot LP entry amounts and price
2. **afterSwap** — accrue insurance premium (theoretical tracking in MVP)
3. **afterRemoveLiquidity** — compute IL, compare against threshold, pay compensation

Without V4 Hooks, this would require a separate middleware contract wrapping every pool interaction — expensive, fragile, and not enforceable. The Hook architecture makes IL protection a native property of the pool itself.

## X Layer Value

- **Attract and retain LPs**: "On X Layer, you don't lose to impermanent loss" is a powerful narrative for a growing L2.
- **CEX-to-DeFi bridge**: OKX's 50M+ CEX users can enter DeFi through protected pools, lowering the psychological barrier.
- **Composable infrastructure**: OKX-ILGuard positions and reserve state are on-chain and readable by other protocols — lending protocols could use protected LP positions as collateral, yield aggregators could route through protected pools.

## Mainnet Deployment (X Layer chain 196)

### Core Contracts

| Contract | Address |
|---|---|
| ILGuardHook | `0x043b00Ae5d234e6c34107D60bFb663e7088a8744` |
| MockToken0 | `0x046EAE536455FE1EE1b78e9c0e3e13d55eDBe921` |
| MockToken1 | `0xFe9049a12EF8e658F56D33734C0B0aEEe80824aF` |
| PoolId | `0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186` |
| Uniswap PoolManager | `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32` (official) |

### Deployment & Demo Transactions

| Action | Tx Hash |
|---|---|
| Deploy Hook | `0x563f67ea15d9382e651a440b03ac8fa1cf52ec52edb7f6727c21dedb17ab6b59` |
| Deploy Token0 | `0x663967aca4a6f199f8050ee0f590001f8688edf34be1fc7d14f2af1615a05411` |
| Deploy Token1 | `0xafea393e249949a88b3c23d79bd5122edc53038cce56f69c43d30bd89260c781` |
| Initialize V4 Pool | `0xbbc6f3fdaf6403951efe25aa2096cc4d9f32037adecfe3264891ff751f1b2c33` |
| Fund Reserve (10 ether) | `0xb9f9362a51dd9f0d61bf9b3b599534f665abfc912ca47f3cd007f96e313dd30c` |
| Add Liquidity → `PositionSnapshotRecorded` | `0x2977b45ab69829f59c72af013f237b3c86f11700e4d052496f5bb90dfebc8739` |
| Swap → `InsurancePremiumAccrued` | `0x77cd00e027065a7f9c664330c80cca77054b4c72e2f8a99d9774d26d5f2c70db` |
| Remove Liquidity | `0x4cfe82e524041a6df0011abdaf3a51b75fe7cbe622acbc6d1111420fbe37bedd` |

### On-Chain Verification (post-DemoFlow)

```
positions(poolId, deployer):  (0, 0, false)        — cleared after remove
reserves(poolId):
  balance:                   10000000000000000000   — 10 ether reserve intact
  totalPremiumsAccrued:      148073705159559        — insurance premium from real swap
```

## What's Real vs MVP Limitation

### Verified on X Layer Mainnet (real PoolManager lifecycle)

- Hook deployed and bound to V4 pool
- Full-range add liquidity triggers `PositionSnapshotRecorded`
- Swap through PoolSwapTest triggers `afterSwap` → `InsurancePremiumAccrued`
- Remove liquidity completes full lifecycle
- Insurance reserve funded on-chain with 10 ether of token0

### Demonstrated via Forge Tests (controlled synthetic delta)

- `ImpermanentLossDetected` — IL calculation logic verified
- `ILCompensated` — LP receives token0 from reserve when IL exceeds 5% threshold

### MVP Limitation

The current simplified IL formula (`depositValue = amount0 + amount1`) assumes a 1:1 price ratio. After a real swap changes the pool price, this additive formula does not capture the price-weighted value change. The IL compensation path is fully implemented and tested with controlled delta values; upgrading to a sqrtPriceX96-based price-weighted calculation is the immediate post-MVP priority.

## How to Run Tests

```bash
git clone GITHUB_REPO_URL
cd okx-ilguard
forge install
forge test -vvv
# Expected: 15 tests, 15 passed
```

```bash
# Demonstrate IL compensation:
forge test --match-test test_integration_directRemove_WithHookData_CompensatesRealLp -vvv
```

## Demo Script

See `DEMO_SCRIPT.md` for the 2-minute video script.

## Future Upgrade Path

1. **sqrtPriceX96 IL calculation** — price-weighted, accurate for any price ratio
2. **Real afterSwapReturnDelta fee collection** — swap fees automatically flow into reserve
3. **Multi-currency compensation** — pay compensation in either token
4. **Concentrated liquidity support** — extend beyond full-range
5. **Actuarial reserve model** — multi-pool risk pooling

## License

MIT
