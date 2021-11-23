// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract AloeBlendERC20 is ERC20Permit {
    constructor(string memory name) ERC20Permit(name) ERC20(name, "ALOE-BLEND") {}
}
