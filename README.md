# OKX-ILGuard — Impermanent Loss Protection Hook for Uniswap V4

[English](#english) | [中文](#中文)

> **One-liner / 一句话**: OKX-ILGuard provides LP impermanent loss protection for Uniswap V4 pools on X Layer.
> Built for the [OKX X Layer Build X Hackathon — Hook Edition](https://web3.okx.com/zh-hans/xlayer/build-x-hackathon/hook).

---

## English

## What It Does

OKX-ILGuard is a Uniswap V4 hook that automatically compensates liquidity providers for impermanent loss. When an LP withdraws liquidity and has lost value compared to their deposit, the hook transfers compensation from a pre-funded insurance reserve directly to the LP.

## MVP Scope

- **Full-range liquidity only** — non-full-range positions are rejected.
- **18-decimal mock token pair** — fixed `MockERC20` tokens with 1:1 initial price.
- **Pre-funded insurance reserve** — funded via `fundReserve()`, not yet from real swap fee deductions.
- **Theoretical premium accounting** — `afterSwap` emits `InsurancePremiumAccrued` event tracking what *would* be collected. Real `afterSwapReturnDelta` fee collection is deferred.
- **Compensation in token0** — paid from reserve via direct ERC20 transfer.
- **Simplified IL calculation** — assumes 1:1 initial price (`depositValue = amount0 + amount1`). Production would use sqrtPriceX96-based computation.

## Hook Lifecycle

| Hook | Purpose |
|---|---|
| `afterAddLiquidity` | Record LP position snapshot (token amounts at entry). Rejects non-full-range. |
| `afterSwap` | Track theoretical insurance premium. Emit `InsurancePremiumAccrued`. |
| `beforeRemoveLiquidity` | Validate full-range position. |
| `afterRemoveLiquidity` | Detect impermanent loss. Compensate LP from reserve if IL exceeds 5% threshold. |

## File Structure

```
okx-ilguard/
├── src/
│   └── ILGuardHook.sol                   # Main hook contract (implements IHooks)
├── test/
│   ├── ILGuardHook.t.sol                 # 6 unit tests
│   └── ILGuardHook.integration.t.sol     # 9 integration tests
├── script/
│   ├── 01_DeployILGuard.s.sol            # CREATE2 HookMiner + deploy Hook
│   ├── 02_DeployMockTokensAndPool.s.sol  # Deploy tokens + initialize V4 pool
│   ├── 03_FundReserve.s.sol              # Fund insurance reserve
│   └── 04_DemoFlow.s.sol                 # Mainnet demo: add → swap → remove
├── SUBMISSION.md                         # Hackathon submission document
├── DEMO_SCRIPT.md                        # 2-minute video script
├── TWEET_DRAFTS.md                       # X/Twitter drafts (pending post)
├── CHECKLIST.md                          # Pre-submission checklist
├── foundry.toml
└── README.md
```

## Quick Start

```bash
# Install dependencies
forge install

# Run all tests
forge test -vvv

# Run integration tests only
forge test --match-contract ILGuardHookIntegrationTest -vvv
```

## Mainnet Deployment (X Layer chain 196)

### Core Contracts

| Contract | Address |
|---|---|
| ILGuardHook | `0x043b00Ae5d234e6c34107D60bFb663e7088a8744` |
| MockToken0 | `0x046EAE536455FE1EE1b78e9c0e3e13d55eDBe921` |
| MockToken1 | `0xFe9049a12EF8e658F56D33734C0B0aEEe80824aF` |
| PoolId | `0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186` |
| Uniswap PoolManager | `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32` (official) |
| Hook permission bits | `0x0744` |

### Key Transactions

| Action | Tx Hash |
|---|---|
| Deploy Hook | `0x563f67ea15d9382e651a440b03ac8fa1cf52ec52edb7f6727c21dedb17ab6b59` |
| Deploy Token0 | `0x663967aca4a6f199f8050ee0f590001f8688edf34be1fc7d14f2af1615a05411` |
| Deploy Token1 | `0xafea393e249949a88b3c23d79bd5122edc53038cce56f69c43d30bd89260c781` |
| Initialize V4 Pool | `0xbbc6f3fdaf6403951efe25aa2096cc4d9f32037adecfe3264891ff751f1b2c33` |
| Fund Reserve | `0xb9f9362a51dd9f0d61bf9b3b599534f665abfc912ca47f3cd007f96e313dd30c` |
| Add Liquidity → `PositionSnapshotRecorded` | `0x2977b45ab69829f59c72af013f237b3c86f11700e4d052496f5bb90dfebc8739` |
| Swap → `InsurancePremiumAccrued` | `0x77cd00e027065a7f9c664330c80cca77054b4c72e2f8a99d9774d26d5f2c70db` |
| Remove Liquidity | `0x4cfe82e524041a6df0011abdaf3a51b75fe7cbe622acbc6d1111420fbe37bedd` |

### On-Chain State (post-DemoFlow)

```
positions(poolId, deployer):  (0, 0, false)
reserves(poolId).balance:     10000000000000000000 (10 ether)
reserves(poolId).premiums:    148073705159559 (> 0)
```

## MVP Honesty

**Real on X Layer mainnet:**
- Hook deployed and bound to V4 pool
- Full-range add liquidity lifecycle via real PoolManager
- Swap lifecycle via real PoolSwapTest, triggering `afterSwap` / `InsurancePremiumAccrued`
- Remove liquidity lifecycle completing full add→swap→remove loop
- Insurance reserve funded on-chain with 10 ether

**Demonstrated in forge tests:**
- `ImpermanentLossDetected` — IL calculation logic
- `ILCompensated` — LP receives token0 compensation from reserve

**MVP limitation:**
The simplified additive IL formula (`depositValue = amount0 + amount1`) assumes a 1:1 price ratio. After a real swap changes the pool price, this formula does not capture the price-weighted value change. The IL compensation path is fully implemented and tested via controlled synthetic delta (`test_integration_directRemove_WithHookData_CompensatesRealLp`). Upgrading to sqrtPriceX96-based calculation is the immediate post-MVP priority.

## Demo Flow

1. Deploy 2 mock ERC20 tokens (18 decimals).
2. Deploy ILGuardHook to X Layer mainnet (CREATE2-mined address).
3. Initialize V4 pool at 1:1 price, bound to ILGuardHook.
4. Add full-range liquidity → snapshot recorded (real PoolManager).
5. Fund insurance reserve with token0.
6. Execute swaps → theoretical premiums accrue (`InsurancePremiumAccrued` events, real PoolSwapTest).
7. Demonstrate IL compensation: remove liquidity with a controlled synthetic withdraw delta → `ImpermanentLossDetected` + `ILCompensated` events fire, LP receives token0 from reserve.

> In the MVP, the real PoolManager lifecycle (add → swap → remove) is fully exercised and verified. The IL compensation branch is demonstrated with a controlled synthetic withdrawal delta because the simplified 1:1 additive IL formula does not capture price-weighted impermanent loss after real swaps. A sqrtPriceX96-based IL calculation is the first post-MVP upgrade.

## Known Limitations

1. **Simplified IL formula** — additive model (amount0 + amount1) assumes 1:1 price. Accurate sqrtPriceX96-based calculation is a post-MVP upgrade. This means **real PoolManager swap → remove does NOT trigger IL compensation in the MVP**; compensation is proven via controlled synthetic delta.
2. **Pre-funded reserve** — insurance pool must be manually funded. Real `afterSwapReturnDelta` fee collection is deferred.
3. **Full-range only** — the MVP rejects non-full-range positions. Broader tick range support planned.
4. **Token0 compensation only** — compensation is paid in token0. Multi-currency support planned.
5. **Mainnet deployment completed** — X Layer chain 196. Deployment scripts in `script/` are reproducible.

## Test Coverage

```
15 tests: 15 PASSED

Unit tests (6):
  - Full-range add liquidity records snapshot
  - Non-full-range add liquidity reverts
  - Not-pool-manager reverts
  - Remove liquidity without snapshot returns gracefully
  - Full IL detection + compensation (synthetic delta)
  - Reserve pre-funding

Integration tests (9):
  - Pool initialized with hook (real PoolManager)
  - Hook address permissions validated
  - Full-range add via real PoolManager (fallback LP = router)
  - Full-range add with hookData=realLp
  - Non-full-range add revert via real PoolManager
  - Real swap triggers afterSwap + InsurancePremiumAccrued
  - Real PoolManager remove liquidity (add → remove no-IL)
  - Full close loop: add → swap → remove (real PM, no compensation: MVP formula limitation)
  - Direct remove with IL compensation (hookData=realLp, synthetic delta)
```

---

## 中文

OKX-ILGuard 是一个 Uniswap V4 Hook，为 X Layer 上的流动性提供者自动补偿无常损失。当 LP 提取流动性且相比存入时发生价值损失，Hook 从预充值的保险储备金中直接向 LP 转账补偿。

### MVP 范围

- **仅支持全范围流动性** — 非全范围头寸会被拒绝。
- **18 位小数 Mock 代币对** — 固定 `MockERC20` 代币，1:1 初始价格。
- **预充值保险储备金** — 通过 `fundReserve()` 充值，暂未从真实 swap 费中扣除。
- **理论保费会计** — `afterSwap` 发出 `InsurancePremiumAccrued` 事件，记录应收取的保费。真实 `afterSwapReturnDelta` 扣费已推迟。
- **token0 补偿** — 从储备金通过直接 ERC20 转账支付补偿。
- **简化 IL 计算** — 假设 1:1 初始价格（`depositValue = amount0 + amount1`）。生产版本将使用 sqrtPriceX96 计算。

### Hook 生命周期

| Hook | 作用 |
|---|---|
| `afterAddLiquidity` | 记录 LP 头寸快照（入场时的代币数量）。拒绝非全范围。 |
| `afterSwap` | 跟踪理论保费。发出 `InsurancePremiumAccrued` 事件。 |
| `beforeRemoveLiquidity` | 验证全范围头寸。 |
| `afterRemoveLiquidity` | 检测无常损失。如果 IL 超过 5% 阈值，从储备金中补偿 LP。 |

### 快速开始

```bash
forge install
forge test -vvv
forge test --match-contract ILGuardHookIntegrationTest -vvv
```

### 主网部署（X Layer chain 196）

核心合约和关键交易见上方 English 章节表格。

### MVP 诚实声明

**X Layer 主网已验证：**
- Hook 已部署并绑定到 V4 池
- 全范围添加流动性生命周期（真实 PoolManager）
- Swap 生命周期（真实 PoolSwapTest），触发 `afterSwap` / `InsurancePremiumAccrued`
- 移除流动性生命周期，完成 add→swap→remove 完整闭环
- 保险储备金已在链上充值 10 ether

**Forge 测试验证：**
- `ImpermanentLossDetected` — IL 计算逻辑
- `ILCompensated` — LP 从储备金收到 token0 补偿

**MVP 限制：**
当前简化 IL 公式（`depositValue = amount0 + amount1`）假设 1:1 价格比。真实 swap 改变池价格后，该加法公式无法捕捉价格加权的价值变化。IL 补偿路径已完整实现并通过受控 synthetic delta 测试（`test_integration_directRemove_WithHookData_CompensatesRealLp`）。升级到 sqrtPriceX96 价格加权计算是 MVP 后最优先事项。

### 测试覆盖

```
15 个测试：全部通过
```

### 未来升级路线

1. **sqrtPriceX96 IL 计算** — 价格加权，适用于任意价格比
2. **真实 afterSwapReturnDelta 扣费** — swap 费自动流入储备金
3. **多币种补偿** — 支持任一代币支付补偿
4. **集中流动性支持** — 扩展到非全范围
5. **精算储备金模型** — 多池风险共担

---

## License

MIT
