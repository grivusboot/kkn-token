# KidKoin (KKN) — BEP-20 Token

![CI](https://github.com/grivusboot/kkn-token/actions/workflows/ci.yml/badge.svg)
![Slither](https://github.com/grivusboot/kkn-token/actions/workflows/slither.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)


**Status:** educational / unaudited. Test thoroughly on **BSC Testnet** before any mainnet deployment.  

---

## 📖 Summary
- **Fees (hard-cap):** up to 4% total (bps: 400).  
  Default: 2% split → **0.8% charity / 0.8% treasury / 0.4% rewards**.  
- **Guards & protections:**  
  - Trading gate (must enable before transfers)  
  - Anti-snipe window (only exempt addresses can trade during launch window)  
  - Transfer delay: 1 tx / block / address (optional)  
  - Max transaction & max wallet limits (configurable, default 2%)  
- **No mint/burn**, no external calls inside `_transfer`; balances are conserved.

---

## ⚠️ Governance & Risks
- **Owner privileges:**  
  - Can **pause** transfers (owner bypass remains active).  
  - Can set/change **exemptions, limits, fee wallets**.  
- **Planned governance:**  
  After stabilization, ownership will be transitioned to **timelock** or **renounced**.  
- **Centralization risk:**  
  Users must be aware that contract control is centralized until ownership is renounced or locked.

---

## 🚀 Deployment
- **Compiler:** Solidity `0.8.20`

## 🔍 Static Analysis (Slither)

Run locally:
```bash
# 1) Install slither (requires Python 3)
python3 -m pip install --upgrade pip
pip install slither-analyzer

# 2) (Optional) Pin solc to 0.8.20 if needed
# pip install solc-select
# solc-select install 0.8.20
# solc-select use 0.8.20

# 3) Run
slither . --config-file slither.config.json
- **Optimizer:** enabled, runs = `200`  
- **Constructor args:**  
  ```solidity
  initialSupply, charityAddress, treasuryAddress, rewardsAddress
