// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KKNToken} from "../contracts/KKNToken.sol";

contract KKNTokenTest is Test {
    KKNToken kkn;
    address charity = address(0x1001);
    address treasury = address(0x1002);
    address rewards = address(0x1003);

    function setUp() public {
        kkn = new KKNToken(1_000_000_000 ether, charity, treasury, rewards);
    }

    function testMetadata() public {
        assertEq(kkn.name(), "KidKoin");
        assertEq(kkn.symbol(), "KKN");
        assertEq(kkn.decimals(), 18);
    }

    function testTransferWithFee() public {
        // send from owner to someone and ensure balances conserve (no reverts)
        address alice = address(0xABCD);
        uint256 beforeOwner = kkn.balanceOf(address(this));
        kkn.transfer(alice, 1000 ether);
        assertGt(kkn.balanceOf(alice), 0);
        assertEq(kkn.totalSupply(), 1_000_000_000 ether);
        assertEq(beforeOwner, kkn.balanceOf(address(this)) + kkn.balanceOf(alice) 
            + kkn.balanceOf(charity) + kkn.balanceOf(treasury) + kkn.balanceOf(rewards));
    }
}
