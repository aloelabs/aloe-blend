// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./AloeBlend.sol";

contract AloeBlendCapped is AloeBlend {
    using SafeERC20 for IERC20;

    address public immutable MULTISIG;
    uint256 public maxTotalSupply = 100000000000000000000;

    constructor(
        IUniswapV3Pool uniPool,
        address cToken0,
        address cToken1,
        address multisig
    ) AloeBlend(uniPool, cToken0, cToken1) {
        MULTISIG = multisig;
    }

    modifier restricted() {
        require(msg.sender == MULTISIG, "Not authorized");
        _;
    }

    function deposit(
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 amount0Min,
        uint256 amount1Min
    )
        public
        override
        lock
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        (shares, amount0, amount1) = super.deposit(amount0Max, amount1Max, amount0Min, amount1Min);
        require(totalSupply() <= maxTotalSupply, "Aloe: Vault already full");
    }

    /**
     * @notice Removes tokens accidentally sent to this vault.
     */
    function sweep(
        IERC20 token,
        uint256 amount,
        address to
    ) external restricted {
        require(
            token != TOKEN0 && token != TOKEN1 && address(token) != silo0.cToken && address(token) != silo1.cToken,
            "Not sweepable"
        );
        token.safeTransfer(to, amount);
    }

    /**
     * @notice Used to change deposit cap for a guarded launch or to ensure
     * vault doesn't grow too large relative to the UNI_POOL. Cap is on total
     * supply rather than amounts of TOKEN0 and TOKEN1 as those amounts
     * fluctuate naturally over time.
     */
    function setMaxTotalSupply(uint256 _maxTotalSupply) external restricted {
        maxTotalSupply = _maxTotalSupply;
    }

    function setK(uint8 _K) external restricted {
        K = _K;
    }

    function setMaintenanceFee(uint256 _maintenanceFee) external restricted {
        maintenanceFee = _maintenanceFee;
    }
}
