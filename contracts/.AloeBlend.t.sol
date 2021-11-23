// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "ds-test/test.sol";

import "./AloeBlend.sol";

contract AloeBlendTest is DSTest {
    AloeBlend blend;

    // function setUp() public {
    //     blend = new AloeBlend();
    // }

    // function test_withdraw(uint96 amount) public {
    //     payable(address(blend)).transfer(amount);
    //     uint preBalance = address(this).balance;
    //     blend.withdraw(42);
    //     uint postBalance = address(this).balance;
    //     assertEq(preBalance + amount, postBalance);
    // }

    // function testFail_withdraw_wrong_pass() public {
    //     payable(address(blend)).transfer(1 ether);
    //     uint preBalance = address(this).balance;
    //     blend.withdraw(1);
    //     uint postBalance = address(this).balance;
    //     assertEq(preBalance + 1 ether, postBalance);
    // }

    // receive() external payable {}
}
