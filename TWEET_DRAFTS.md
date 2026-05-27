# OKX-ILGuard — Tweet Drafts

**IMPORTANT: Do NOT post these until CEO approves final GitHub repo and demo video links.**
**Tweet 1 has been posted with the demo video attached.**

---

## Tweet 1: Launch / Submission Tweet

*Must include `@XLayerOfficial @Uniswap @flapdotsh`*

```
Submitted to the @XLayerOfficial Build X Hackathon — Hook Edition.

OKX-ILGuard: on-chain impermanent loss protection for Uniswap V4 pools on X Layer.

Built as a V4 Hook. Deployed. Verified.

Hook: 0x043b00Ae5d234e6c34107D60bFb663e7088a8744
Pool: 0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186

Mainnet: add/swap/remove lifecycle + reserve accounting.
Tests: IL detection + compensation branch.

@Uniswap @flapdotsh

https://github.com/Souler-S/OKX-ILGuard
https://x.com/ThreeOclock_CN/status/2059224654519091393?s=20
```

---

## Tweet 2: Technical Thread Opener

*Can be posted as a thread with additional tweets below.*

```
Why OKX-ILGuard needs Uniswap V4 Hooks (and can't be done in V3):

Impermanent loss compensation requires code at 3 pool lifecycle points that no earlier Uniswap version exposes:

1. afterAddLiquidity — record LP entry amounts
2. afterSwap — accrue insurance premium
3. afterRemoveLiquidity — compute IL, pay from reserve

Without Hooks, you'd need a separate middleware contract wrapping every interaction — fragile and unenforceable. With Hooks, IL protection is native to the pool itself.

All three are live on X Layer mainnet right now.

@XLayerOfficial @Uniswap @flapdotsh
```

---

## Tweet 3: Honest MVP + Roadmap

```
What OKX-ILGuard does on mainnet today:

PositionSnapshotRecorded on add liquidity
InsurancePremiumAccrued on swap
Full add→swap→remove lifecycle verified
Reserve funded with 10 ether on-chain

What's next:
sqrtPriceX96 price-weighted IL (infrastructure ready)
Real swap fee collection into reserve
Multi-currency compensation

The MVP is deployed and testable. The roadmap is clear.

@XLayerOfficial @Uniswap @flapdotsh
```

---

## Posting Notes

- All three tweets must tag `@XLayerOfficial @Uniswap @flapdotsh`
- Tweet 1 posted: https://x.com/ThreeOclock_CN/status/2059224654519091393?s=20
- Tweet 2 can be a thread of 3-4 tweets if desired
- Tweet 3 should go after the submission deadline, showing continued engagement
- Do not claim real compensation has occurred on mainnet — be honest about MVP limitations
