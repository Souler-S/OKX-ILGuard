# OKX-ILGuard — Hackathon Submission

**Build X Hackathon — Hook Edition**
OKX X Layer × Uniswap × Flap

---

## Project Name

**OKX-ILGuard**

## One-Liner

On-chain impermanent loss compensation for Uniswap V4 liquidity providers on X Layer.

## 60-Second Judge Path

1. [Hook on X Layer Explorer](https://www.okx.com/explorer/xlayer/address/0x043b00Ae5d234e6c34107D60bFb663e7088a8744) — deployed, verified, bound to V4 pool.
2. [8 on-chain transactions](#x-layer-mainnet-proofs) prove full add→swap→remove lifecycle.
3. `forge test -vvv` — 18/18 pass (9 integration tests use real PoolManager).
4. [Demo video](https://x.com/ThreeOclock_CN/status/2059224654519091393) — 2-minute walkthrough.

## Solution

OKX-ILGuard provides automatic impermanent loss compensation for full-range LPs:

1. **Record** LP deposit with `sqrtPriceX96` for price-weighted valuation
2. **Track** insurance premiums from every swap (15 BPS)
3. **Compensate** from pre-funded reserve when IL > 5%

## X Layer Mainnet Proofs

| # | Action | Explorer Link |
|---|---|---|
| 1 | Deploy Hook | [0x563f...b6b59](https://www.okx.com/explorer/xlayer/tx/0x563f67ea15d9382e651a440b03ac8fa1cf52ec52edb7f6727c21dedb17ab6b59) |
| 2 | Deploy Token0 | [0x6639...5411](https://www.okx.com/explorer/xlayer/tx/0x663967aca4a6f199f8050ee0f590001f8688edf34be1fc7d14f2af1615a05411) |
| 3 | Deploy Token1 | [0xafea...c781](https://www.okx.com/explorer/xlayer/tx/0xafea393e249949a88b3c23d79bd5122edc53038cce56f69c43d30bd89260c781) |
| 4 | Initialize Pool | [0xbbc6...2c33](https://www.okx.com/explorer/xlayer/tx/0xbbc6f3fdaf6403951efe25aa2096cc4d9f32037adecfe3264891ff751f1b2c33) |
| 5 | Fund Reserve | [0xb9f9...d30c](https://www.okx.com/explorer/xlayer/tx/0xb9f9362a51dd9f0d61bf9b3b599534f665abfc912ca47f3cd007f96e313dd30c) |
| 6 | Add Liquidity | [0x2977...8739](https://www.okx.com/explorer/xlayer/tx/0x2977b45ab69829f59c72af013f237b3c86f11700e4d052496f5bb90dfebc8739) |
| 7 | Swap (premium) | [0x77cd...70db](https://www.okx.com/explorer/xlayer/tx/0x77cd00e027065a7f9c664330c80cca77054b4c72e2f8a99d9774d26d5f2c70db) |
| 8 | Remove Liquidity | [0x4cfe...bedd](https://www.okx.com/explorer/xlayer/tx/0x4cfe82e524041a6df0011abdaf3a51b75fe7cbe622acbc6d1111420fbe37bedd) |

## On-Chain State

```
Hook:       0x043b00Ae5d234e6c34107D60bFb663e7088a8744
Token0:     0x046EAE536455FE1EE1b78e9c0e3e13d55eDBe921
Token1:     0xFe9049a12EF8e658F56D33734C0B0aEEe80824aF
PoolId:     0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186
PoolManager: 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32
```

## Technical Architecture

| Component | Detail |
|---|---|
| Hook permissions | `0x0740` (afterAddLiquidity, beforeRemoveLiquidity, afterRemoveLiquidity, afterSwap) |
| IL calculation | `_computePositionValue(amount0, amount1, sqrtPriceX96)` — price-weighted |
| Premium rate | 15 BPS of swap output |
| IL threshold | 5% (`compensationThresholdBps = 500`) |
| Contract size | ~6KB runtime |

## Test Coverage

```
18/18 PASSED (CI verified)

Unit (9):                     Integration (9 — real PoolManager):
  Snapshot with price ✓         Pool initialized with hook ✓
  Non-full-range revert ✓       Hook permissions validated ✓
  IL detection + compensation ✓ Full-range add + remove ✓
  Reserve funding ✓             Real swap → premium ✓
  afterSwap hookDelta ✓         Full close: add→swap→remove ✓
  IL with price change ✓        Direct remove + IL compensated ✓
```

## Repository

[https://github.com/Souler-S/OKX-ILGuard](https://github.com/Souler-S/OKX-ILGuard)

## Demo Video

[https://x.com/ThreeOclock_CN/status/2059224654519091393](https://x.com/ThreeOclock_CN/status/2059224654519091393)
