# OKX-ILGuard — 2-Minute Demo Video Script

**Target length**: 2 minutes (120 seconds)
**Style**: Screen capture + voiceover

---

## 0:00–0:15 — Problem Hook

*Visual: Show a Uniswap V4 pool interface, highlight "Impermanent Loss" warning text.*

"Every liquidity provider in DeFi faces the same fear: impermanent loss. You deposit tokens, the price moves, and you end up with less value than if you'd just held. There's no built-in protection in any DEX — until now."

---

## 0:15–0:40 — Product Introduction

*Visual: Show ILGuard Hook contract on X Layer block explorer. Highlight key addresses.*

"OKX-ILGuard is a Uniswap V4 Hook that gives LPs impermanent loss protection — directly on X Layer. Deployed and verified today. Let me show you how it works."

*Visual: Show architecture diagram (4 lifecycle hooks).*

"The Hook inserts logic at three critical moments: when you add liquidity, it takes a snapshot. Every swap accrues insurance premium accounting. And when you remove liquidity, it checks if you've lost value — and pays you back from the reserve."

---

## 0:40–1:20 — Mainnet Proof

*Visual: Terminal running `cast call` to verify on-chain state.*

"Let me prove this is real. Here's the Hook on X Layer mainnet at this address. Here's the V4 pool it's bound to, with this PoolId."

*Visual: Show add liquidity tx on block explorer. Highlight `PositionSnapshotRecorded` event.*

"I added full-range liquidity through a real Uniswap V4 PoolManager. The Hook recorded my snapshot — you can see the `PositionSnapshotRecorded` event on-chain."

*Visual: Show swap tx. Highlight `InsurancePremiumAccrued` event.*

"Then I executed a real swap through Uniswap's swap router. The Hook's `afterSwap` fired and recorded the theoretical insurance premium. Event confirmed on-chain."

*Visual: Show `cast call` for reserve balance.*

"The insurance reserve holds 10 ether of token0 — funded and verified on-chain."

---

## 1:20–1:50 — Honest MVP + Demo of Compensation

*Visual: Forge test terminal output showing `ImpermanentLossDetected` + `ILCompensated`.*

"The Hook uses sqrtPriceX96-based price-weighted valuation to detect impermanent loss. When the withdrawal value falls below the deposit value by more than 5%, it automatically compensates the LP from the pre-funded reserve. Let me show you the test proving this works."

*Visual: Show test passing with green checkmarks.*

"Run this yourself: `forge test --match-test test_integration_directRemove_WithHookData_CompensatesRealLp`"

---

## 1:50–2:00 — Closing

*Visual: X Layer logo + OKX-ILGuard title + GitHub URL.*

"The immediate upgrade is a sqrtPriceX96-based price-weighted IL calculation — the infrastructure is already in place. OKX-ILGuard makes X Layer the chain where LPs can provide liquidity with protection built in."

"All contracts are deployed. All tests pass. Code is open source. OKX-ILGuard — impermanent loss protection for Uniswap V4 on X Layer."

---

## Screen Recording Checklist

- [ ] Block explorer: Hook address `0x043b00...8744` with code visible
- [ ] Block explorer: PoolManager address with Hook bound
- [ ] Block explorer: add liquidity tx showing `PositionSnapshotRecorded` event
- [ ] Block explorer: swap tx showing `InsurancePremiumAccrued` event
- [ ] Terminal: `cast call` showing reserve balance = 10 ether
- [ ] Terminal: `forge test` output showing `ILCompensated` test passing
- [ ] GitHub repo shown with README visible
