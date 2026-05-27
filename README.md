# OKX-ILGuard — Impermanent Loss Protection Hook for Uniswap V4

[![CI](https://github.com/Souler-S/OKX-ILGuard/actions/workflows/test.yml/badge.svg)](https://github.com/Souler-S/OKX-ILGuard/actions/workflows/test.yml)

[English](#english) | [中文](#中文)

> **One-liner / 一句话**: Uniswap V4 hook that charges a 15 BPS insurance premium on every swap and automatically compensates LPs for impermanent loss. Deployed on X Layer mainnet.
> Built for the [OKX X Layer Build X Hackathon — Hook Edition](https://web3.okx.com/zh-hans/xlayer/build-x-hackathon/hook).

---

## English

### ⚡ 60-Second Judge Path

1. **Check the on-chain hook**: [ILGuardHook on X Layer Explorer](https://www.okx.com/explorer/xlayer/address/0x043b00Ae5d234e6c34107D60bFb663e7088a8744) — deployed, verified, bound to a live V4 pool.
2. **Verify the lifecycle**: 8 on-chain transactions prove add→swap→remove loop (see [X Layer Mainnet Proofs](#x-layer-mainnet-proofs)).
3. **Run the tests**: `forge test -vvv` — 18/18 pass. 9 integration tests exercise the real PoolManager.
4. **See the demo**: [2-minute walkthrough on X](https://x.com/ThreeOclock_CN/status/2059224654519091393).

### What It Does

OKX-ILGuard is a Uniswap V4 hook that:

- **Records** LP positions at entry with `sqrtPriceX96` for price-weighted valuation.
- **Tracks** insurance premiums from every swap (15 BPS of output amount).
- **Compensates** LPs from a pre-funded reserve when impermanent loss exceeds 5% at withdrawal.

### Quick Start

```bash
# 1. Clone & install dependencies
git clone https://github.com/Souler-S/OKX-ILGuard.git
cd OKX-ILGuard
forge install

# 2. Build
forge build --sizes

# 3. Run all 18 tests (9 unit + 9 integration, CI verified)
forge test -vvv

# 4. Run integration tests only (real PoolManager lifecycle)
forge test --match-contract ILGuardHookIntegrationTest -vvv

# 5. Check formatting
forge fmt --check

# 6. Verify contract size (must be < 24KB for deployment)
forge build --sizes | grep ILGuard
# Expected: | ILGuardHook | ~6,000 | ... | < 24,000 |
```

### X Layer Mainnet Proofs

All 8 transactions executed on X Layer mainnet (chain 196). Every link opens the OKX Explorer.

| # | Action | Tx Hash / Explorer Link | What It Proves |
|---|---|---|---|
| 1 | Deploy Hook | [`0x563f...b6b59`](https://www.okx.com/explorer/xlayer/tx/0x563f67ea15d9382e651a440b03ac8fa1cf52ec52edb7f6727c21dedb17ab6b59) | Hook bytecode on-chain, permission bits 0x0744 |
| 2 | Deploy Token0 | [`0x6639...5411`](https://www.okx.com/explorer/xlayer/tx/0x663967aca4a6f199f8050ee0f590001f8688edf34be1fc7d14f2af1615a05411) | MockERC20 token0 deployed |
| 3 | Deploy Token1 | [`0xafea...c781`](https://www.okx.com/explorer/xlayer/tx/0xafea393e249949a88b3c23d79bd5122edc53038cce56f69c43d30bd89260c781) | MockERC20 token1 deployed |
| 4 | Initialize Pool | [`0xbbc6...2c33`](https://www.okx.com/explorer/xlayer/tx/0xbbc6f3fdaf6403951efe25aa2096cc4d9f32037adecfe3264891ff751f1b2c33) | V4 pool created, bound to ILGuardHook |
| 5 | Fund Reserve | [`0xb9f9...d30c`](https://www.okx.com/explorer/xlayer/tx/0xb9f9362a51dd9f0d61bf9b3b599534f665abfc912ca47f3cd007f96e313dd30c) | 10 ether transferred to insurance reserve |
| 6 | Add Liquidity | [`0x2977...8739`](https://www.okx.com/explorer/xlayer/tx/0x2977b45ab69829f59c72af013f237b3c86f11700e4d052496f5bb90dfebc8739) | `PositionSnapshotRecorded` event emitted |
| 7 | Swap | [`0x77cd...70db`](https://www.okx.com/explorer/xlayer/tx/0x77cd00e027065a7f9c664330c80cca77054b4c72e2f8a99d9774d26d5f2c70db) | `InsurancePremiumAccrued` event emitted |
| 8 | Remove Liquidity | [`0x4cfe...bedd`](https://www.okx.com/explorer/xlayer/tx/0x4cfe82e524041a6df0011abdaf3a51b75fe7cbe622acbc6d1111420fbe37bedd) | Full close: snapshot cleared, lifecycle complete |

### On-Chain State (Post-DemoFlow)

Verified on X Layer mainnet — you can check these yourself:

```
Hook:       0x043b00Ae5d234e6c34107D60bFb663e7088a8744
Token0:     0x046EAE536455FE1EE1b78e9c0e3e13d55eDBe921
Token1:     0xFe9049a12EF8e658F56D33734C0B0aEEe80824aF
PoolId:     0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186
PoolManager: 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32 (official Uniswap V4)

positions(poolId, deployer):  (0, 0, 0, false)  ← snapshot cleared after remove
reserves(poolId).balance:     > 10 ether        ← funded + swap premiums collected
reserves(poolId).premiums:    > 0               ← swap fee tracked
```

### Features

| Feature | Implementation |
|---|---|
| sqrtPriceX96 IL calc | Price-weighted deposit/withdraw value via `_computePositionValue` |
| Real premium collection | `afterSwap` uses `afterSwapReturnDelta` + `poolManager.take()` — 15 BPS premium settled per-swap, tokens flow into reserve. No separate router needed. |
| Full-range enforcement | Tick bounds validated at add and remove |
| IL threshold | Compensation when loss > 5% (`compensationThresholdBps = 500`) |
| Token0 compensation | Direct ERC20 transfer from pre-funded insurance reserve |

### Gas & Contract Size

| Metric | Value |
|---|---|
| Runtime size | 6,301 bytes (margin: 18,275 / 24,576) |
| Deployment cost | ~1,262,000 gas |
| `afterAddLiquidity` | 25K–96K gas (25K gas no snapshot, 96K gas with snapshot) |
| `afterRemoveLiquidity` | 33K–55K gas (33K gas no snapshot, 55K gas with IL check) |
| `afterSwap` (premium collect) | ~72K gas |
| `fundReserve` | ~79K gas |

> Gas measured via `forge test --gas-report` with via-ir enabled. All hook callbacks stay well within Uniswap V4's 300K gas limit per hook.


### How Premium Collection Works (afterSwapReturnDelta)

The hook uses Uniswap V4's native fee-settlement mechanism:

1. **`afterSwap` returns a positive `hookDelta`** (15 BPS × output amount) — this tells the PoolManager the hook is owed tokens.
2. **`poolManager.take()` withdraws the premium** from the PoolManager's settlement buffer into the hook contract. The `take()` creates a negative delta that cancels the positive `hookDelta`.
3. **`afterSwapReturnDelta` permission bit (bit 2)** enables this settlement flow. Without it, the PoolManager wouldn't record the hook's delta claim.

No separate swap router. No extra transactions. Premium collection is atomic with every swap.

### Hook Lifecycle

| Hook | Behavior |
|---|---|
| `afterAddLiquidity` | Records `PositionSnapshot(amount0, amount1, sqrtPriceX96)`. Rejects non-full-range. |
| `afterSwap` | Computes premium (15 BPS × output), calls `poolManager.take()` to collect tokens directly into reserve. Emits `InsurancePremiumAccrued`. |
| `beforeRemoveLiquidity` | Validates full-range tick bounds. |
| `afterRemoveLiquidity` | Compares `_computePositionValue(deposit)` vs `_computePositionValue(withdraw)`. Compensates if IL > 5%. |

### Contract Architecture

```
ILGuardHook (6,072 bytes runtime)
├── afterAddLiquidity    → record PositionSnapshot with sqrtPriceX96
├── afterSwap            → collect premiums via take(), emit InsurancePremiumAccrued
├── beforeRemoveLiquidity → validate full-range
├── afterRemoveLiquidity  → sqrtPriceX96 IL detection + compensate from reserve
└── fundReserve          → external: anyone can fund the insurance pool
```

### Test Coverage

```
18 tests: 18 PASSED — CI verified

Unit (9):                     Integration (9):
  Snapshot with price ✓         Pool initialized with hook (real PM) ✓
  Non-full-range revert ✓       Hook permissions validated ✓
  Not-pool-manager revert ✓     Full-range add (router LP) ✓
  Remove without snapshot ✓     Full-range add (hookData=realLp) ✓
  IL detection + compensation ✓ Non-full-range revert (real PM) ✓
  Reserve funding ✓             Real swap → InsurancePremiumAccrued ✓
  afterSwap hookDelta ✓         Real PM remove (no IL) ✓
  afterSwap oneForZero ✓        Full close: add→swap→remove ✓
  IL with price change ✓        Direct remove + IL compensated ✓
```

### File Structure

```
okx-ilguard/
├── src/ILGuardHook.sol                 # Hook contract (~6KB, final version)
├── test/
│   ├── ILGuardHook.t.sol               # 9 unit tests
│   └── ILGuardHook.integration.t.sol   # 9 integration tests (real PoolManager)
├── script/
│   ├── 01_DeployILGuard.s.sol          # CREATE2 HookMiner + deploy
│   ├── 02_DeployMockTokensAndPool.s.sol # Deploy tokens + init V4 pool
│   ├── 03_FundReserve.s.sol            # Fund insurance reserve
│   └── 04_DemoFlow.s.sol              # add → swap → remove demo
├── .github/workflows/test.yml          # CI: build + fmt + test
├── foundry.toml
└── README.md
```

---

## 中文

### ⚡ 评委 60 秒路径

1. **查看链上 Hook**：[X Layer 浏览器](https://www.okx.com/explorer/xlayer/address/0x043b00Ae5d234e6c34107D60bFb663e7088a8744) — 已部署、已验证、已绑定 V4 池。
2. **验证生命周期**：8 笔链上交易完成 add→swap→remove 闭环（见 [X Layer 主网证明](#x-layer-主网证明)）。
3. **跑测试**：`forge test -vvv` — 18/18 通过，9 个集成测试使用真实 PoolManager。
4. **看演示**：[2 分钟视频](https://x.com/ThreeOclock_CN/status/2059224654519091393)。

### 核心功能

- **记录** LP 入场头寸，使用 `sqrtPriceX96` 进行价格加权估值。
- **跟踪** 每次 swap 的保费（输出量的 15 BPS）。
- **补偿** LP：当无常损失 > 5%，从预充值储备金自动转账。

### 快速开始

```bash
git clone https://github.com/Souler-S/OKX-ILGuard.git
cd OKX-ILGuard
forge install
forge build --sizes
forge test -vvv                          # 18 个测试
forge test --match-contract ILGuardHookIntegrationTest -vvv  # 集成测试
forge fmt --check
```

### X Layer 主网证明

8 笔交易全部在 X Layer 主网 (chain 196) 执行。每笔交易附 OKX 浏览器链接。

| # | 操作 | 交易哈希 | 证明内容 |
|---|---|---|---|
| 1 | 部署 Hook | [`0x563f...b6b59`](https://www.okx.com/explorer/xlayer/tx/0x563f67ea15d9382e651a440b03ac8fa1cf52ec52edb7f6727c21dedb17ab6b59) | Hook 字节码上链，权限位 0x0744 |
| 2 | 部署 Token0 | [`0x6639...5411`](https://www.okx.com/explorer/xlayer/tx/0x663967aca4a6f199f8050ee0f590001f8688edf34be1fc7d14f2af1615a05411) | MockERC20 代币0 |
| 3 | 部署 Token1 | [`0xafea...c781`](https://www.okx.com/explorer/xlayer/tx/0xafea393e249949a88b3c23d79bd5122edc53038cce56f69c43d30bd89260c781) | MockERC20 代币1 |
| 4 | 初始化池 | [`0xbbc6...2c33`](https://www.okx.com/explorer/xlayer/tx/0xbbc6f3fdaf6403951efe25aa2096cc4d9f32037adecfe3264891ff751f1b2c33) | V4 池创建，绑定 ILGuardHook |
| 5 | 充值储备金 | [`0xb9f9...d30c`](https://www.okx.com/explorer/xlayer/tx/0xb9f9362a51dd9f0d61bf9b3b599534f665abfc912ca47f3cd007f96e313dd30c) | 10 ether 转入保险储备金 |
| 6 | 添加流动性 | [`0x2977...8739`](https://www.okx.com/explorer/xlayer/tx/0x2977b45ab69829f59c72af013f237b3c86f11700e4d052496f5bb90dfebc8739) | `PositionSnapshotRecorded` 事件 |
| 7 | Swap | [`0x77cd...70db`](https://www.okx.com/explorer/xlayer/tx/0x77cd00e027065a7f9c664330c80cca77054b4c72e2f8a99d9774d26d5f2c70db) | `InsurancePremiumAccrued` 事件 |
| 8 | 移除流动性 | [`0x4cfe...bedd`](https://www.okx.com/explorer/xlayer/tx/0x4cfe82e524041a6df0011abdaf3a51b75fe7cbe622acbc6d1111420fbe37bedd) | 完整闭环，快照已清除 |

### 链上状态（DemoFlow 后）

```
Hook 地址:   0x043b00Ae5d234e6c34107D60bFb663e7088a8744
Token0:     0x046EAE536455FE1EE1b78e9c0e3e13d55eDBe921
Token1:     0xFe9049a12EF8e658F56D33734C0B0aEEe80824aF
PoolId:     0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186
PoolManager: 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32 (Uniswap V4 官方)

positions(poolId, deployer):  (0, 0, 0, false)  ← 移除后快照清除
reserves(poolId).balance:     10 ether          ← 准备金就绪
reserves(poolId).premiums:    > 0               ← swap 保费已记录
```

### 保费收集机制 (afterSwapReturnDelta)

Hook 利用 Uniswap V4 的原生费用结算机制：

1. **`afterSwap` 返回正 `hookDelta`**（输出量的 15 BPS）— 告知 PoolManager hook 应收代币。
2. **`poolManager.take()` 提取保费** 从 PoolManager 结算缓冲区转入 hook 合约。`take()` 产生负 delta 与正 `hookDelta` 抵消。
3. **`afterSwapReturnDelta` 权限位 (bit 2)** 启用此结算流程。

无需独立 swap router，无需额外交易。保费收集与每次 swap 原子执行。

### 特性 / 测试覆盖 / 文件结构

见上方 English 章节对应表格。

---

## License

MIT
