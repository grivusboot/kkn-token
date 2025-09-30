# KidKoin (KKN) — BEP-20 Token

**Status:** educational / unaudited. Test on BSC Testnet first.

## Summary
- **Fees (hard-cap):** up to 4% total (bps: 400). Default: 2% split 0.8/0.8/0.4 (charity/treasury/rewards).
- **Guards:** trading gate, anti-snipe window, 1 tx/block (optional), max tx & max wallet (configurable).
- **No mint/burn**, no external calls in transfer; balances conserved.

## Governance & Risks
- Owner can **pause** (owner bypass), set **exemptions/limits**, change **fee wallets**.
- Plan: after stabilization we will **{timelock/renounce ownership}**.
- This is a **centralization risk**. Users should understand these controls before buying.

## Deployment
- **Compiler:** Solidity `0.8.20`
- **Optimizer:** enabled, runs 200 (example)
- **Constructor args:** `initialSupply, charity, treasury, rewards`
- **Chain:** BSC (testnet/mainnet)
- **Deployer:** `0x...`
- **Token address:** `0x...` (after deployment)
- **Block:** `#...`

## Verification
1. Verify on BscScan with:
   - Solidity `0.8.20`, optimizer settings identical
   - Paste `KKNToken.sol` and constructor args
2. Optionally submit to **Sourcify**.

## Build & Test (Foundry)
```bash
forge build
forge test -vv
