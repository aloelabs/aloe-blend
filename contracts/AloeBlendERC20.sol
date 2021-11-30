// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@rari-capital/solmate/src/tokens/ERC20.sol";

contract AloeBlendERC20 is ERC20 {
    constructor(string memory _name) ERC20(_name, "ALOE-BLEND", 18) {}
}
