# OKX-ILGuard — Submission Checklist

## Code & Tests

- [x] `forge build` passes (0 errors)
- [x] `forge test -vvv` passes (**18/18 tests**: 9 unit + 9 integration)
- [x] `forge fmt --check` passes (CI verified)
- [x] GitHub CI green: [![CI](https://github.com/Souler-S/OKX-ILGuard/actions/workflows/test.yml/badge.svg)](https://github.com/Souler-S/OKX-ILGuard/actions/workflows/test.yml)
- [x] No `.secrets/` files committed
- [x] No `cache/` files committed
- [x] No `broadcast/**/dry-run/` files committed
- [x] All Solidity files formatted (`forge fmt`)

## Mainnet Deployment (X Layer chain 196)

- [x] ILGuardHook deployed: `0x043b00Ae5d234e6c34107D60bFb663e7088a8744`
- [x] MockToken0 deployed: `0x046EAE536455FE1EE1b78e9c0e3e13d55eDBe921`
- [x] MockToken1 deployed: `0xFe9049a12EF8e658F56D33734C0B0aEEe80824aF`
- [x] V4 Pool initialized: `0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186`
- [x] Insurance reserve funded (10 ether)
- [x] DemoFlow lifecycle executed: add → swap → remove
- [x] `PositionSnapshotRecorded` event confirmed on-chain
- [x] `InsurancePremiumAccrued` event confirmed on-chain

## Documentation

- [x] `README.md` — bilingual (中文/English), final version features, addresses, tx hashes, PoolId
- [x] `SUBMISSION.md` — hackathon submission with all addresses, tx hashes, PoolId
- [x] `DEMO_SCRIPT.md` — 2-minute video script
- [x] `TWEET_DRAFTS.md` — 3 tweet drafts
- [x] `LICENSE` — MIT

## GitHub Project

- [x] Repository: `https://github.com/Souler-S/OKX-ILGuard`
- [x] Description: "Uniswap V4 Hook for automatic impermanent loss compensation on X Layer"
- [x] Topics: `uniswap`, `uniswap-v4`, `v4-hook`, `impermanent-loss`, `defi`, `solidity`, `foundry`, `x-layer`, `okx`, `hackathon`
- [x] License: MIT
- [x] Language: Solidity
- [x] CI badge in README

## Google Form Submission

- [x] Project name: OKX-ILGuard
- [x] Hook address: `0x043b00Ae5d234e6c34107D60bFb663e7088a8744`
- [x] PoolId: `0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186`
- [x] Token addresses: `0x046E...`, `0xFe90...`
- [x] GitHub URL: `https://github.com/Souler-S/OKX-ILGuard`
- [x] Demo video: `https://x.com/ThreeOclock_CN/status/2059224654519091393`

## Submission Materials

- [x] GitHub repository public
- [x] All mainnet addresses in README and SUBMISSION.md
- [x] All tx hashes in README and SUBMISSION.md
- [x] Demo video link in docs
- [x] Google Form submitted before deadline (2026-05-28 23:59 UTC)

## Pre-Submission Final Check

```bash
forge test -q           # 18/18 PASSED ✅
forge fmt --check       # passes ✅
git status --short      # no .secrets, no cache ✅
find src test script -name '*.sol' | wc -l    # 7 source files
```
