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
        // In Foundry, address(this) devine owner (deployer)
        kkn = new KKNToken(SUPPLY, charity, treasury, rewards);
    }

    function testMetadata() public {
        assertEq(kkn.name(), "KidKoin");
        assertEq(kkn.symbol(), "KKN");
        assertEq(kkn.decimals(), 18);
        assertEq(kkn.totalSupply(), SUPPLY);
    }

    /// Owner este feeExempt în constructor => transferul nu ia taxă.
    function testTransfer_NoFee_WhenOwnerExempt() public {
        uint256 beforeOwner = kkn.balanceOf(address(this));
        kkn.transfer(alice, 1000 ether);

        // Fără taxe: toți cei 1000 merg la alice
        assertEq(kkn.balanceOf(alice), 1000 ether);
        // Wallet-urile de fee rămân 0
        assertEq(kkn.balanceOf(charity), 0);
        assertEq(kkn.balanceOf(treasury), 0);
        assertEq(kkn.balanceOf(rewards), 0);

        // Conservarea sumei (owner + alice + fee wallets = supply)
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

    /// Activează trading și testează taxele pe un cont ne-exempt (bob).
    function testFeesApply_ForNonExempt() public {
        // 1) Enable trading fără fereastră anti-snipe
        kkn.enableTrading(0);

        // 2) Mută tokens la bob (owner e exempt => fără taxă aici)
        kkn.transfer(bob, 1_000 ether);

        // 3) bob -> alice (se vor aplica taxele default: total 2% => 0.8/0.8/0.4)
        vm.startPrank(bob);
        kkn.transfer(alice, 100 ether);
        vm.stopPrank();

        // Fee total = 2% din 100 = 2 ether
        // charity 0.8, treasury 0.8, rewards 0.4; alice primește 98
        assertEq(kkn.balanceOf(alice), 98 ether);
        assertEq(kkn.balanceOf(charity), 0.8 ether);
        assertEq(kkn.balanceOf(treasury), 0.8 ether);
        assertEq(kkn.balanceOf(rewards), 0.4 ether);

        // Conservare supply
        uint256 sum =
            kkn.balanceOf(address(this)) +
            kkn.balanceOf(bob) +
            kkn.balanceOf(alice) +
            kkn.balanceOf(charity) +
            kkn.balanceOf(treasury) +
            kkn.balanceOf(rewards);
        assertEq(sum, SUPPLY);
    }

    // -------- Reverts cu custom errors (.selector) --------

    function testOnlyOwner_setFeeSplit_NotOwner() public {
        // apel dintr-un EOA non-owner
        vm.prank(alice);
        vm.expectRevert(KKNToken.NotOwner.selector);
        kkn.setFeeSplit(200, 80, 80, 40);
    }

    function testSetFeeSplit_Mismatch() public {
        // total 200 dar componentele nu se adună la 200
        vm.expectRevert(KKNToken.FeeSplitMismatch.selector);
        kkn.setFeeSplit(200, 100, 50, 30);
    }

    function testSetFeeSplit_TooHigh() public {
        // total > 400 bps
        vm.expectRevert(KKNToken.TotalFeeTooHigh.selector);
        kkn.setFeeSplit(500, 250, 150, 100);
    }

    function testTradingNotEnabled_ForNonExemptBeforeLaunch() public {
        // Owner poate transfera, însă un non-exempt nu are voie înainte de enableTrading
        kkn.transfer(bob, 10 ether); // owner->bob (ok)
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
        // Setăm limită mică pentru test și pornim trading
        kkn.setLimits(50 ether, type(uint256).max);
        kkn.enableTrading(0);

        // Bob are 1000, dar maxTx = 50 => ar trebui să pice la 100
        kkn.transfer(bob, 1000 ether);
        vm.prank(bob);
        vm.expectRevert(KKNToken.MaxTxExceeded.selector);
        kkn.transfer(alice, 100 ether);

        // Dar la 50 e ok (vor fi și taxe)
        vm.prank(bob);
        kkn.transfer(alice, 50 ether);
        assertGt(kkn.balanceOf(alice), 0);
    }

    function testMaxWalletExceeded() public {
        // Setăm maxWallet = 100 ether, pornim trading (fără anti-snipe)
        kkn.setLimits(type(uint256).max, 100 ether);
        kkn.enableTrading(0);

        // owner -> bob 90 (ok, sub maxWallet)
        kkn.transfer(bob, 90 ether);

        // bob -> alice 50 (alice primește 49 după taxe, dar important e post-recepție)
        vm.prank(bob);
        kkn.transfer(alice, 50 ether);

        // owner -> alice încă 60 => după taxe ~ 58, dar check-ul e pe post-recepție;
        // cum maxWallet e 100, operația ar depăși limita -> revert
        vm.expectRevert(KKNToken.MaxWalletExceeded.selector);
        kkn.transfer(alice, 60 ether);
    }

    function testTransferDelay_OneTxPerBlock() public {
        // trading on, transfer-delay on by default în constructor
        kkn.enableTrading(0);

        // owner -> bob 100
        kkn.transfer(bob, 100 ether);

        // bob face două transferuri în același block
        vm.startPrank(bob);
        kkn.transfer(alice, 10 ether);
        vm.expectRevert(KKNToken.OneTxPerBlock.selector);
        kkn.transfer(alice, 1 ether);
        vm.stopPrank();

        // dacă rulăm în block diferit, reușește
        vm.roll(block.number + 1);
        vm.prank(bob);
        kkn.transfer(alice, 1 ether);
    }

    function testApprove_And_TransferFrom_AllowanceTooLow() public {
        // trading poate fi off; testăm doar allowance
        // fără aprobare, transferFrom trebuie să pice
        vm.expectRevert(KKNToken.AllowanceTooLow.selector);
        kkn.transferFrom(address(this), alice, 1 ether);

        // approve + transferFrom reușesc
        kkn.approve(address(this), 5 ether);
        kkn.transferFrom(address(this), alice, 5 ether);
        assertEq(kkn.balanceOf(alice), 5 ether);
    }
}
