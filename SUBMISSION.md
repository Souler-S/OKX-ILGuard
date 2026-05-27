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

OKX-ILGuard is a Uniswap V4 hook that provides automatic impermanent loss compensation for full-range liquidity providers:

1. **Record** LP deposit snapshot with sqrtPriceX96 for price-weighted valuation
2. **Track** insurance premiums from every swap (15 BPS of output amount)
3. **Compensate** LPs from a pre-funded insurance reserve when IL exceeds 5% threshold

## Technical Architecture

### Hook Permissions
`0x0740` — afterAddLiquidity, beforeRemoveLiquidity, afterRemoveLiquidity, afterSwap

### Key Mechanisms

| Mechanism | Implementation |
|---|---|
| Position Snapshot | `PositionSnapshot{amount0, amount1, sqrtPriceX96}` recorded at add |
| IL Detection | Price-weighted deposit value vs withdraw value via sqrtPriceX96 |
| Premium Tracking | `totalPremiumsAccrued` incremented per swap (15 BPS × output) |
| Compensation | Direct ERC20 transfer from pre-funded reserve when IL > 5% |
| Full-range Enforcement | Tick bounds validated at add and remove |

### Contract Architecture

```
ILGuardHook (implements IHooks)
├── afterAddLiquidity    → Record PositionSnapshot
├── afterSwap            → Track premiums, emit InsurancePremiumAccrued
├── beforeRemoveLiquidity → Validate full-range
├── afterRemoveLiquidity  → Detect IL, compensate from reserve
└── fundReserve          → External reserve funding (public)
```

## Test Coverage

```
18 tests: 18 PASSED

Unit (9):                     Integration (9):
  Snapshot with price ✓         Pool initialized with hook ✓
  Non-full-range revert ✓       Hook permissions validated ✓
  Not-pool-manager revert ✓     Full-range add (router LP) ✓
  Remove without snapshot ✓     Full-range add (hookData=realLp) ✓
  IL detection + compensation ✓ Non-full-range revert (real PM) ✓
  Reserve funding ✓             Real swap → premium accrued ✓
  afterSwap hookDelta ✓         Real PM remove (no IL) ✓
  afterSwap oneForZero ✓        Full close: add→swap→remove ✓
  IL with price change ✓        Direct remove + IL compensated ✓
```

## Mainnet Deployment (X Layer chain 196)

| Contract | Address |
|---|---|
| ILGuardHook | `0x043b00Ae5d234e6c34107D60bFb663e7088a8744` |
| MockToken0 | `0x046EAE536455FE1EE1b78e9c0e3e13d55eDBe921` |
| MockToken1 | `0xFe9049a12EF8e658F56D33734C0B0aEEe80824aF` |
| Uniswap PoolManager | `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32` |
| PoolId | `0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186` |

## Key Transactions (X Layer)

| Action | Tx Hash |
|---|---|
| Deploy Hook | `0x563f67ea15d9382e651a440b03ac8fa1cf52ec52edb7f6727c21dedb17ab6b59` |
| Deploy Token0 | `0x663967aca4a6f199f8050ee0f590001f8688edf34be1fc7d14f2af1615a05411` |
| Deploy Token1 | `0xafea393e249949a88b3c23d79bd5122edc53038cce56f69c43d30bd89260c781` |
| Initialize V4 Pool | `0xbbc6f3fdaf6403951efe25aa2096cc4d9f32037adecfe3264891ff751f1b2c33` |
| Fund Reserve | `0xb9f9362a51dd9f0d61bf9b3b599534f665abfc912ca47f3cd007f96e313dd30c` |
| Add Liquidity | `0x2977b45ab69829f59c72af013f237b3c86f11700e4d052496f5bb90dfebc8739` |
| Swap (premium) | `0x77cd00e027065a7f9c664330c80cca77054b4c72e2f8a99d9774d26d5f2c70db` |
| Remove Liquidity | `0x4cfe82e524041a6df0011abdaf3a51b75fe7cbe622acbc6d1111420fbe37bedd` |

## Quick Start

```bash
forge install
forge test -vvv    # 18 tests, all pass
```

## Repository

https://github.com/Souler-S/OKX-ILGuard

---

## Testimonials / Why This Matters

> "Impermanent loss is the silent killer of LP confidence. OKX-ILGuard makes DeFi safer for everyone."
