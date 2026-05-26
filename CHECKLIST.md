# OKX-ILGuard — Submission Checklist

## Code & Tests

- [x] `forge build` passes (0 errors)
- [x] `forge test -vvv` passes (15/15 tests)
- [x] No `.secrets/` files committed
- [x] No `cache/` files committed
- [x] No `broadcast/**/dry-run/` files committed
- [x] All Solidity files formatted (`forge fmt`)

## Mainnet Deployment

- [x] ILGuardHook deployed: `0x043b00Ae5d234e6c34107D60bFb663e7088a8744`
- [x] MockToken0 deployed: `0x046EAE536455FE1EE1b78e9c0e3e13d55eDBe921`
- [x] MockToken1 deployed: `0xFe9049a12EF8e658F56D33734C0B0aEEe80824aF`
- [x] V4 Pool initialized: `0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186`
- [x] Insurance reserve funded (10 ether)
- [x] DemoFlow lifecycle executed: add → swap → remove
- [x] `PositionSnapshotRecorded` event confirmed on-chain
- [x] `InsurancePremiumAccrued` event confirmed on-chain
- [x] Hook code verified on-chain (not 0x)
- [x] Token codes verified on-chain (not 0x)

## Documentation

- [x] `README.md` — project overview + mainnet deployment + MVP honesty
- [x] `SUBMISSION.md` — hackathon submission document
- [x] `DEMO_SCRIPT.md` — 2-minute video script
- [x] `TWEET_DRAFTS.md` — 3 tweet drafts with required tags
- [x] `CHECKLIST.md` — this file

## Submission Materials

- [x] GitHub repository public: `https://github.com/Souler-S/OKX-ILGuard`
- [ ] All mainnet addresses in README and SUBMISSION.md
- [ ] All tx hashes in README and SUBMISSION.md
- [ ] Demo video recorded (use `DEMO_SCRIPT.md`)
- [ ] Demo video uploaded (YouTube or equivalent)
- [ ] Demo video link in TWEET_DRAFTS.md and SUBMISSION.md
- [ ] Independent X/Twitter account created
- [ ] X/Twitter account bio/profile updated for hackathon
- [ ] Tweet 1 posted with `@XLayerOfficial @Uniswap @flapdotsh`
- [ ] Tweet 2 posted (thread opener)
- [ ] Tweet 3 posted (honest MVP + roadmap)
- [ ] Consistent posting during event period
- [ ] Google Form submitted before deadline (2026-05-28 23:59 UTC)
- [ ] Google Form includes:
  - [ ] Project name: OKX-ILGuard
  - [ ] Hook address: `0x043b00Ae5d234e6c34107D60bFb663e7088a8744`
  - [ ] Pool address/PoolId
  - [ ] Token addresses
  - [ ] GitHub URL
  - [ ] Demo video URL

## Pre-Submission Final Check

```bash
forge test -q          # must be 15/15
git status --short     # no .secrets, no cache, no dry-run
find . -name '*.sol' -not -path './lib/*' | wc -l  # should be 5 (src + script)
```
