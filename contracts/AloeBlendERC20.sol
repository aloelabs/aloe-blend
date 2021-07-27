// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract AloeBlendERC20 is ERC20Permit {
    constructor() ERC20Permit("Aloe V1") ERC20("Aloe V1", "ALOE-V1") {}
}
