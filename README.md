# OKX-ILGuard — Impermanent Loss Protection Hook for Uniswap V4

[English](#english) | [中文](#中文)

> **One-liner / 一句话**: Automatic impermanent loss compensation for Uniswap V4 full-range LPs.
> Built for the [OKX X Layer Build X Hackathon — Hook Edition](https://web3.okx.com/zh-hans/xlayer/build-x-hackathon/hook).

---

## English

### What It Does

OKX-ILGuard is a Uniswap V4 hook that:

- **Records** LP positions at entry with sqrtPriceX96 for price-weighted valuation.
- **Tracks** insurance premiums from every swap (15 BPS of output amount).
- **Compensates** LPs from a pre-funded reserve when impermanent loss exceeds 5% at withdrawal.

### Features

| Feature | Description |
|---|---|
| sqrtPriceX96 IL calc | Price-weighted deposit/withdraw value, not additive approximation |
| Premium tracking | `afterSwap` accrues `totalPremiumsAccrued` per swap |
| Full-range enforcement | Non-full-range positions rejected at add/remove |
| IL threshold | Compensation only when loss > 5% (configurable `compensationThresholdBps`) |
| Token0 compensation | Paid from insurance reserve via direct ERC20 transfer |

### Hook Lifecycle

| Hook | Behavior |
|---|---|
| `afterAddLiquidity` | Records `PositionSnapshot` (amount0, amount1, sqrtPriceX96). Rejects non-full-range. |
| `afterSwap` | Computes premium (15 BPS × output amount), emits `InsurancePremiumAccrued`. |
| `beforeRemoveLiquidity` | Validates full-range tick bounds. |
| `afterRemoveLiquidity` | Compares price-weighted deposit vs withdraw value. Compensates from reserve if IL > threshold. |

### Quick Start

```bash
forge install
forge test -vvv                        # 18 tests (9 unit + 9 integration)
forge test --match-contract ILGuardHookIntegrationTest -vvv
```

### File Structure

```
okx-ilguard/
├── src/ILGuardHook.sol                 # Hook contract (final: sqrtPriceX96 + premiums)
├── test/
│   ├── ILGuardHook.t.sol               # 9 unit tests
│   └── ILGuardHook.integration.t.sol   # 9 integration tests (real PoolManager)
├── script/                             # Deployment & demo scripts
├── foundry.toml
└── README.md
```

### Mainnet Deployment (X Layer chain 196)

| Contract | Address |
|---|---|
| ILGuardHook | `0x043b00Ae5d234e6c34107D60bFb663e7088a8744` |
| MockToken0 | `0x046EAE536455FE1EE1b78e9c0e3e13d55eDBe921` |
| MockToken1 | `0xFe9049a12EF8e658F56D33734C0B0aEEe80824aF` |
| Uniswap PoolManager | `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32` (official) |
| Hook permission bits | `0x0740` |

### Test Coverage

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

### X Layer Mainnet Transactions

| Action | Tx Hash |
|---|---|
| Deploy Hook | `0x563f...` |
| Initialize V4 Pool | `0xbbc6...` |
| Fund Reserve | `0xb9f9...` |
| Add Liquidity | `0x2977...` |
| Swap (premium) | `0x77cd...` |
| Remove Liquidity | `0x4cfe...` |

### Future Upgrades

1. **Multi-currency compensation** — pay in either token
2. **Concentrated liquidity** — support non-full-range positions
3. **Actuarial reserve model** — cross-pool risk pooling
4. **Real premium settlement** — `afterSwapReturnDelta` with proper token custody

---

## 中文

### 核心功能

OKX-ILGuard 是一个 Uniswap V4 Hook：

- **记录** LP 入场头寸，使用 sqrtPriceX96 进行价格加权估值。
- **跟踪** 每次 swap 产生的手续费（输出的 15 BPS）。
- **补偿** LP 从预充值储备金中支取，当无常损失超过 5% 时自动触发。

### 特性

| 特性 | 说明 |
|---|---|
| sqrtPriceX96 IL 计算 | 价格加权的存取款价值，非简单加法 |
| 保费跟踪 | `afterSwap` 累加 `totalPremiumsAccrued` |
| 全范围强制 | 非全范围头寸在添加/移除时被拒绝 |
| IL 阈值 | 仅当损失 > 5% 时触发补偿（可配置） |
| token0 补偿 | 从保险储备金直接 ERC20 转账 |

### Hook 生命周期

| Hook | 行为 |
|---|---|
| `afterAddLiquidity` | 记录 `PositionSnapshot` (amount0, amount1, sqrtPriceX96)。拒绝非全范围。 |
| `afterSwap` | 计算保费（15 BPS × 输出量），发出 `InsurancePremiumAccrued`。 |
| `beforeRemoveLiquidity` | 验证全范围 tick 边界。 |
| `afterRemoveLiquidity` | 比较价格加权存取款价值，若 IL > 阈值则从储备金补偿。 |

### 快速开始

```bash
forge install
forge test -vvv                        # 18 个测试全部通过
forge test --match-contract ILGuardHookIntegrationTest -vvv
```

### 测试覆盖

```
18 个测试：全部通过

单元测试 (9):                 集成测试 (9):
  含价格快照 ✓                 池初始化绑定 Hook ✓
  非全范围拒绝 ✓               Hook 权限验证 ✓
  非 PoolManager 拒绝 ✓        全范围添加（默认 LP） ✓
  无快照移除 ✓                 全范围添加（hookData=realLp） ✓
  IL 检测 + 补偿 ✓             非全范围拒绝（真实 PM） ✓
  储备金充值 ✓                 真实 swap → 保费累计 ✓
  afterSwap hookDelta ✓        真实 PM 移除（无 IL） ✓
  afterSwap oneForZero ✓       完整闭环：add→swap→remove ✓
  价格变动的 IL ✓              直接移除 + IL 补偿 ✓
```

---

## License

MIT
