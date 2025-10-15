# Changelog

## [v2.0.0] – 2025-10-15  
### Changed  
- Migrated from string `require("KKN: …")` to `custom errors` (`revert ErrorName()`)  
- No changes in tokenomics, fees, or logic  
- Updated test suite to expect `.selector` reverts  
- Cleaned up redundancy in error messages  

### Fixed  
- Tests adapted to bypass anti-snipe in first block (using `vm.roll`)  
- Removed unnecessary zero-address exemptions where relevant 

## v0.1.0 — Initial release
- Add KKNToken.sol (fees capped at 4%, anti-snipe, transfer delay, limits)
- MIT license, README, Foundry config
