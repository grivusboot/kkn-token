// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KKNToken} from "../contracts/KKNToken.sol";

contract KKNTokenTest is Test {
    KKNToken kkn;
    address charity  = address(0x1001);
    address treasury = address(0x1002);
    address rewards  = address(0x1003);

    address alice = address(0xABCD);
    address bob   = address(0xB0B);

    uint256 constant SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        // In Foundry, address(this) becomes the deployer (owner)
        kkn = new KKNToken(SUPPLY, charity, treasury, rewards);
    }

    /// Verify ERC-20 metadata and total supply
    function testMetadata() public view {
        assertEq(kkn.name(), "KidKoin");
        assertEq(kkn.symbol(), "KKN");
        assertEq(kkn.decimals(), 18);
        assertEq(kkn.totalSupply(), SUPPLY);
    }

    /// Owner is feeExempt by default (constructor) → no fee should apply
    function testTransfer_NoFee_WhenOwnerExempt() public {
        uint256 beforeOwner = kkn.balanceOf(address(this));
        kkn.transfer(alice, 1000 ether);

        // No fees: full amount goes to Alice
        assertEq(kkn.balanceOf(alice), 1000 ether);
        // Fee wallets remain empty
        assertEq(kkn.balanceOf(charity), 0);
        assertEq(kkn.balanceOf(treasury), 0);
        assertEq(kkn.balanceOf(rewards), 0);

        // Total supply must remain constant (sum of all balances)
        assertEq(
            kkn.balanceOf(address(this)) +
            kkn.balanceOf(alice) +
            kkn.balanceOf(charity) +
            kkn.balanceOf(treasury) +
            kkn.balanceOf(rewards),
            SUPPLY
        );
        assertEq(beforeOwner, kkn.balanceOf(address(this)) + 1000 ether);
    }

    /// Enable trading and test default fees for a non-exempt account (Bob)
    function testFeesApply_ForNonExempt() public {
        // 1) Enable trading with no anti-snipe window
        kkn.enableTrading(0);
        vm.roll(block.number + 1); // move to next block (past anti-snipe)

        // 2) Transfer tokens to Bob (owner is exempt → no fee here)
        kkn.transfer(bob, 1_000 ether);

        // 3) Bob → Alice (fee applies: 2% total → 0.8/0.8/0.4)
        vm.startPrank(bob);
        kkn.transfer(alice, 100 ether);
        vm.stopPrank();

        // Fee total = 2% of 100 = 2 ether
        // charity 0.8, treasury 0.8, rewards 0.4 → Alice receives 98
        assertEq(kkn.balanceOf(alice), 98 ether);
        assertEq(kkn.balanceOf(charity), 0.8 ether);
        assertEq(kkn.balanceOf(treasury), 0.8 ether);
        assertEq(kkn.balanceOf(rewards), 0.4 ether);

        // Total supply must remain unchanged
        uint256 sum =
            kkn.balanceOf(address(this)) +
            kkn.balanceOf(bob) +
            kkn.balanceOf(alice) +
            kkn.balanceOf(charity) +
            kkn.balanceOf(treasury) +
            kkn.balanceOf(rewards);
        assertEq(sum, SUPPLY);
    }

    // ----------- Revert tests using custom errors (.selector) -----------

    function testOnlyOwner_setFeeSplit_NotOwner() public {
        // Call from a non-owner EOA should revert
        vm.prank(alice);
        vm.expectRevert(KKNToken.NotOwner.selector);
        kkn.setFeeSplit(200, 80, 80, 40);
    }

    function testSetFeeSplit_Mismatch() public {
        // total 200 but parts do not add up to 200 → revert
        vm.expectRevert(KKNToken.FeeSplitMismatch.selector);
        kkn.setFeeSplit(200, 100, 50, 30);
    }

    function testSetFeeSplit_TooHigh() public {
        // total > 400 bps → revert
        vm.expectRevert(KKNToken.TotalFeeTooHigh.selector);
        kkn.setFeeSplit(500, 250, 150, 100);
    }

    function testTradingNotEnabled_ForNonExemptBeforeLaunch() public {
        // Owner can transfer before trading is enabled
        // Non-exempt users cannot → should revert
        kkn.transfer(bob, 10 ether); // owner → bob (ok)
        vm.prank(bob);
        vm.expectRevert(KKNToken.TradingNotEnabled.selector);
        kkn.transfer(alice, 1 ether);
    }

    function testEnableTrading_AlreadyEnabled() public {
        kkn.enableTrading(0);
        vm.expectRevert(KKNToken.AlreadyEnabled.selector);
        kkn.enableTrading(0);
    }

    function testMaxTxExceeded() public {
        // Set small limit and enable trading
        kkn.setLimits(50 ether, type(uint256).max);
        kkn.enableTrading(0);
        vm.roll(block.number + 1);

        // Bob has 1000, but maxTx = 50 → 100 should revert
        kkn.transfer(bob, 1000 ether);
        vm.prank(bob);
        vm.expectRevert(KKNToken.MaxTxExceeded.selector);
        kkn.transfer(alice, 100 ether);

        // 50 should pass (fee applies)
        vm.prank(bob);
        kkn.transfer(alice, 50 ether);
        assertGt(kkn.balanceOf(alice), 0);
    }

    function testMaxWalletExceeded() public {
        // Set maxWallet = 100 ether and enable trading (no anti-snipe)
        kkn.setLimits(type(uint256).max, 100 ether);
        kkn.enableTrading(0);
        vm.roll(block.number + 1);

        // owner → bob 90 (ok, under maxWallet)
        kkn.transfer(bob, 90 ether);

        // bob → alice 50 (ok, but adds up close to limit)
        vm.prank(bob);
        kkn.transfer(alice, 50 ether);

        // owner → alice another 60 → should exceed limit and revert
        vm.expectRevert(KKNToken.MaxWalletExceeded.selector);
        kkn.transfer(alice, 60 ether);
    }

    function testTransferDelay_OneTxPerBlock() public {
        // Trading enabled, transfer delay ON by default (constructor)
        kkn.enableTrading(0);
        vm.roll(block.number + 1);

        // owner → bob 100
        kkn.transfer(bob, 100 ether);

        // Bob performs two transfers in the same block → second should revert
        vm.startPrank(bob);
        kkn.transfer(alice, 10 ether);
        vm.expectRevert(KKNToken.OneTxPerBlock.selector);
        kkn.transfer(alice, 1 ether);
        vm.stopPrank();

        // Next block → should succeed
        vm.roll(block.number + 1);
        vm.prank(bob);
        kkn.transfer(alice, 1 ether);
    }

    function testApprove_And_TransferFrom_AllowanceTooLow() public {
        // Trading may be off; test allowance logic only
        // Without approval, transferFrom must revert
        vm.expectRevert(KKNToken.AllowanceTooLow.selector);
        kkn.transferFrom(address(this), alice, 1 ether);

        // Approve + transferFrom must succeed
        kkn.approve(address(this), 5 ether);
        kkn.transferFrom(address(this), alice, 5 ether);
        assertEq(kkn.balanceOf(alice), 5 ether);
    }
}
