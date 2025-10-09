// SPDX-License-Identifier: MIT
// solhint-disable compiler-version
pragma solidity ^0.8.20;
// solhint-enable compiler-version

/// @title KidKoin (KKN) — BEP-20 with configurable fees + anti-bot/anti-whale guards
/// @notice Educational code (unaudited). Always test on BSC Testnet before mainnet.
/// @custom:dev-run-script deploy.js
contract KKNToken {
    // ---------- Constants ----------
    uint256 private constant BPS_DENOM = 10_000; // 100.00% in basis points

    // ---------- Structs ----------
    struct FeeConfig {
        uint16 total;    // total fee (bps) — e.g., 200 = 2.00%
        uint16 charity;  // share of total
        uint16 treasury; // share of total
        uint16 rewards;  // share of total
    }

    struct Wallets {
        address charity;
        address treasury;
        address rewards;
    }

    struct Guard {
        bool paused;
        bool tradingEnabled;
        bool transferDelayEnabled;               // optional: 1 tx / block / address
        uint64 launchBlock;                      // launch block number
        uint64 antiSnipeBlocks;                  // anti-snipe window in blocks
        mapping(address => uint256) lastTransferBlock;
    }

    struct Limits {
        uint256 maxTxAmount;                     // 0 = off
        uint256 maxWalletAmount;                 // 0 = off
        mapping(address => bool) txLimitExempt;
        mapping(address => bool) maxWalletExempt;
    }

    struct Privileges {
        // Exemptions: no fees, no transfer delay, not restricted by anti-snipe
        mapping(address => bool) feeExempt;
    }

    // ---------- ERC-20 Metadata (private + view getters) ----------
    string private _name;
    string private _symbol;
    uint8  private _decimals;

    // ---------- ERC-20 State / Admin (≤15) ----------
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public owner;

    FeeConfig private _fees;      // private → avoids Remix "infinite gas" on public struct
    Wallets  private _wallets;    // private → same reason
    Guard    private guard;
    Limits   private limits;
    Privileges private priv;

    // ---------- Events ----------
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event Paused();
    event Unpaused();
    event FeeWalletsUpdated(address charity, address treasury, address rewards);
    event FeeSplitUpdated(uint16 totalFeeBps, uint16 charityBps, uint16 treasuryBps, uint16 rewardsBps);
    event FeeExemptSet(address indexed account, bool exempt);
    event TradingEnabled(uint256 launchBlock, uint256 antiSnipeBlocks);
    event TransferDelayToggled(bool enabled);
    event LimitsUpdated(uint256 maxTxAmount, uint256 maxWalletAmount);
    event LimitExemptionsUpdated(address indexed account, bool txLimitExempt, bool maxWalletExempt);

    // ---------- Modifiers ----------
    modifier onlyOwner() { require(msg.sender == owner, "KKN: not owner"); _; }

    // ---------- Metadata Getters (view) ----------
    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public view returns (uint8) { return _decimals; }

    // ---------- Explicit getters (avoid public struct pitfalls) ----------
    function getFees() external view returns (uint16 total, uint16 charity, uint16 treasury, uint16 rewards) {
        FeeConfig memory f = _fees;
        return (f.total, f.charity, f.treasury, f.rewards);
    }
    function charityWallet() external view returns (address) { return _wallets.charity; }
    function treasuryWallet() external view returns (address) { return _wallets.treasury; }
    function rewardsWallet() external view returns (address) { return _wallets.rewards; }

    // ---------- Constructor ----------
    // solhint-disable-next-line func-visibility
    constructor(
        uint256 initialSupply_,                   // e.g., 1_000_000_000e18
        address charity_,
        address treasury_,
        address rewards_
    ) {
        require(charity_  != address(0) && treasury_ != address(0) && rewards_ != address(0), "KKN: zero addr");

        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);

        // ERC-20 metadata
        _name = "KidKoin";
        _symbol = "KKN";
        _decimals = 18;

        // Default wallets & fees (2% total → 0.8/0.8/0.4)
        _wallets = Wallets({ charity: charity_, treasury: treasury_, rewards: rewards_ });
        _fees = FeeConfig({ total: 200, charity: 80, treasury: 80, rewards: 40 });

        // Default exemptions (fees/delay/anti-snipe/limits)
        priv.feeExempt[owner] = true;
        priv.feeExempt[charity_] = true;
        priv.feeExempt[treasury_] = true;
        priv.feeExempt[rewards_] = true;

        // Transfer delay enabled by default
        guard.transferDelayEnabled = true;

        // Mint initial supply to deployer and set default limits: 2% per tx / wallet
        totalSupply = initialSupply_;
        balanceOf[msg.sender] = initialSupply_;
        emit Transfer(address(0), msg.sender, initialSupply_);

        limits.maxTxAmount     = (totalSupply * 200) / BPS_DENOM; // 2%
        limits.maxWalletAmount = (totalSupply * 200) / BPS_DENOM; // 2%

        // Limit exemptions
        limits.txLimitExempt[owner] = true;
        limits.txLimitExempt[charity_] = true;
        limits.txLimitExempt[treasury_] = true;
        limits.txLimitExempt[rewards_] = true;

        limits.maxWalletExempt[owner] = true;
        limits.maxWalletExempt[charity_] = true;
        limits.maxWalletExempt[treasury_] = true;
        limits.maxWalletExempt[rewards_] = true;
        limits.maxWalletExempt[address(0)] = true;
    }

    // ---------- Ownership & Pause ----------
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "KKN: zero owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        // grant standard exemptions to new owner
        priv.feeExempt[newOwner] = true;
        limits.txLimitExempt[newOwner] = true;
        limits.maxWalletExempt[newOwner] = true;
    }

    function pause() external onlyOwner { 
        guard.paused = true; 
        emit Paused(); 
    }

    function unpause() external onlyOwner { 
        guard.paused = false; 
        emit Unpaused(); 
    }

    // ---------- Trading control ----------
    /// @dev Enables trading and sets the anti-snipe window (number of blocks after launch).
    function enableTrading(uint256 antiSnipeBlocks_) external onlyOwner {
        require(!guard.tradingEnabled, "KKN: already enabled");
        guard.tradingEnabled = true;
        guard.launchBlock = uint64(block.number);
        guard.antiSnipeBlocks = uint64(antiSnipeBlocks_);
        emit TradingEnabled(block.number, antiSnipeBlocks_);
    }

    function setTransferDelayEnabled(bool enabled) external onlyOwner {
        guard.transferDelayEnabled = enabled;
        emit TransferDelayToggled(enabled);
    }

    // ---------- Fees ----------
    /// @dev Hard-cap 4% (400 bps). The sum of the split must equal the total.
    function setFeeSplit(uint16 totalBps, uint16 charityBps, uint16 treasuryBps, uint16 rewardsBps) external onlyOwner {
        require(totalBps <= 400, "KKN: total fee too high");
        require(uint256(charityBps) + treasuryBps + rewardsBps == totalBps, "KKN: split mismatch");
        _fees = FeeConfig({ total: totalBps, charity: charityBps, treasury: treasuryBps, rewards: rewardsBps });
        emit FeeSplitUpdated(totalBps, charityBps, treasuryBps, rewardsBps);
    }

    function setFeeWallets(address charity, address treasury, address rewards) external onlyOwner {
        require(charity != address(0) && treasury != address(0) && rewards != address(0), "KKN: zero addr");
        _wallets = Wallets({ charity: charity, treasury: treasury, rewards: rewards });

        // standard exemptions
        priv.feeExempt[charity]  = true;
        priv.feeExempt[treasury] = true;
        priv.feeExempt[rewards]  = true;

        limits.txLimitExempt[charity]  = true;
        limits.txLimitExempt[treasury] = true;
        limits.txLimitExempt[rewards]  = true;

        limits.maxWalletExempt[charity]  = true;
        limits.maxWalletExempt[treasury] = true;
        limits.maxWalletExempt[rewards]  = true;

        emit FeeWalletsUpdated(charity, treasury, rewards);
    }

    function setFeeExempt(address account, bool exempt) external onlyOwner {
        priv.feeExempt[account] = exempt;
        emit FeeExemptSet(account, exempt);
    }

    // ---------- Anti-whale limits ----------
    /// @dev Set to 0 to disable the corresponding limit.
    function setLimits(uint256 maxTxAmount, uint256 maxWalletAmount) external onlyOwner {
        limits.maxTxAmount = maxTxAmount;
        limits.maxWalletAmount = maxWalletAmount;
        emit LimitsUpdated(maxTxAmount, maxWalletAmount);
    }

    function setLimitExemptions(address account, bool txLimitExempt, bool maxWalletExempt) external onlyOwner {
        limits.txLimitExempt[account] = txLimitExempt;
        limits.maxWalletExempt[account] = maxWalletExempt;
        emit LimitExemptionsUpdated(account, txLimitExempt, maxWalletExempt);
    }

    // ---------- ERC-20 ----------
    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "KKN: allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, value);
        return true;
    }

    // ---------- Transfer + fees + guards ----------
    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "KKN: to zero");

        // Allow all if paused=false or owner is sender
        require(!guard.paused || msg.sender == owner, "KKN: paused");

        // ---------- Trading enable / anti-snipe ----------
        // Skip anti-snipe checks for known router contracts and smart contracts
        bool fromIsContract;
        bool toIsContract;
        assembly {
            fromIsContract := gt(extcodesize(from), 0)
            toIsContract   := gt(extcodesize(to), 0)
        }

        // Before trading is enabled, only owner/exempt can transfer
        if (!guard.tradingEnabled) {
            require(
                priv.feeExempt[from] || priv.feeExempt[to] || from == owner,
                "KKN: trading not enabled"
            );
        } else {
            // During anti-snipe window: only exempt addresses may transfer (skip for DEX/router contracts)
            if (
                !fromIsContract && !toIsContract &&
                block.number <= uint256(guard.launchBlock) + uint256(guard.antiSnipeBlocks)
            ) {
                require(
                    priv.feeExempt[from] || priv.feeExempt[to],
                    "KKN: anti-snipe window"
                );
            }
        }

        // ---------- Transfer delay (optional) ----------
        if (
            guard.transferDelayEnabled &&
            !(priv.feeExempt[from] || priv.feeExempt[to]) &&
            !fromIsContract && !toIsContract
        ) {
            require(guard.lastTransferBlock[from] < block.number, "KKN: only 1 tx per block");
            guard.lastTransferBlock[from] = block.number;
        }

        // ---------- Balances and limits ----------
        uint256 fromBal = balanceOf[from];
        require(fromBal >= value, "KKN: balance");

        if (limits.maxTxAmount > 0 && !(limits.txLimitExempt[from] || limits.txLimitExempt[to])) {
            require(value <= limits.maxTxAmount, "KKN: > maxTx");
        }

        // ---------- Fee logic ----------
        bool takeFee = !(priv.feeExempt[from] || priv.feeExempt[to]);
        uint256 feeTotal = 0;
        if (takeFee && _fees.total > 0) {
            feeTotal = (value * _fees.total) / BPS_DENOM;
        }

        uint256 sendAmount = value - feeTotal;

        // ---------- Max wallet (after-fee check) ----------
        if (limits.maxWalletAmount > 0 && !limits.maxWalletExempt[to]) {
            require(balanceOf[to] + sendAmount <= limits.maxWalletAmount, "KKN: > maxWallet");
        }

        // ---------- Move balances ----------
        unchecked {
            balanceOf[from] = fromBal - value;
            balanceOf[to] += sendAmount;
        }
        emit Transfer(from, to, sendAmount);

        // ---------- Fee distribution ----------
        if (feeTotal != 0) {
            _distributeFees(from, feeTotal);
        }
    }


    // ---------- Fee distribution (separated to resolve "stack too deep") ----------
    function _distributeFees(address from, uint256 feeTotal) private {
        uint16 t = _fees.total;

        // Split by shares; remainder goes to rewards to preserve sum
        uint256 feeCharity  = (feeTotal * _fees.charity)  / t;
        uint256 feeTreasury = (feeTotal * _fees.treasury) / t;
        uint256 feeRewards  = feeTotal - feeCharity - feeTreasury;

        address charityAddr  = _wallets.charity;
        address treasuryAddr = _wallets.treasury;
        address rewardsAddr  = _wallets.rewards;

        if (feeCharity != 0) {
            balanceOf[charityAddr] += feeCharity;
            emit Transfer(from, charityAddr, feeCharity);
        }
        if (feeTreasury != 0) {
            balanceOf[treasuryAddr] += feeTreasury;
            emit Transfer(from, treasuryAddr, feeTreasury);
        }
        if (feeRewards != 0) {
            balanceOf[rewardsAddr] += feeRewards;
            emit Transfer(from, rewardsAddr, feeRewards);
        }
    }
}
