# OKX-ILGuard Demo Recording Steps

Goal: record a 2-minute screen video and use `OKX-ILGuard-voiceover.aiff` as the narration track.

## Assets

- Voiceover text: `VOICEOVER.md`
- Voiceover audio: `OKX-ILGuard-voiceover.aiff`
- Script: `DEMO_SCRIPT.md`
- GitHub repo: `https://github.com/Souler-S/OKX-ILGuard`

## Suggested Screen Flow

1. Open GitHub repo:
   `https://github.com/Souler-S/OKX-ILGuard`
   - Show README title and one-liner.
   - Show mainnet deployment table.

2. Show Hook address on X Layer explorer:
   `0x043b00Ae5d234e6c34107D60bFb663e7088a8744`
   - Show contract code exists.

3. Show mainnet transactions:
   - Add liquidity / `PositionSnapshotRecorded`:
     `0x2977b45ab69829f59c72af013f237b3c86f11700e4d052496f5bb90dfebc8739`
   - Swap / `InsurancePremiumAccrued`:
     `0x77cd00e027065a7f9c664330c80cca77054b4c72e2f8a99d9774d26d5f2c70db`

4. Show terminal verification:

```bash
cd /Users/MacBook/Documents/Codex/2026-05-25/hi/okx-ilguard
source /Users/MacBook/Documents/Codex/2026-05-25/hi/.secrets/okx-hackathon.env

cast call "$ILGUARD_HOOK_ADDRESS" \
  "reserves(bytes32)(uint256,uint256)" \
  0x6f91ddd9bcd951400001e39c4d33eef23fb90c80d62a9bb3c967367e95432186 \
  --rpc-url "$XLAYER_MAINNET_RPC_URL"
```

Expected output:

```text
10000000000000000000
148073705159559
```

5. Show compensation branch test:

```bash
forge test --match-test test_integration_directRemove_WithHookData_CompensatesRealLp -vvv
```

6. End on README / Submission section.

## Editing

- Put `OKX-ILGuard-voiceover.aiff` under the screen recording as the audio track.
- Trim video to about 2 minutes.
- Export as MP4.
- Upload to YouTube, Loom, Google Drive, or any public video host.
- After upload, replace `[Demo video link]` in `TWEET_DRAFTS.md` and `VIDEO_URL_TO_BE_ADDED` in `SUBMISSION.md`.
