// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./AloeBlend.sol";

contract AloeBlendCapped is AloeBlend {
    using SafeERC20 for IERC20;
    using Silo for ISilo;

    uint256 public constant TIMELOCK = 2 days;

    address public immutable MULTISIG;

    uint256 public maxTotalSupply = 0;

    uint24 public governedWidth = 0;

    struct PendingSilos {
        ISilo silo0;
        ISilo silo1;
        uint256 timestamp;
    }

    PendingSilos public pendingSilos;

    constructor(
        IUniswapV3Pool uniPool,
        ISilo silo0,
        ISilo silo1,
        address multisig
    ) AloeBlend(uniPool, silo0, silo1) {
        MULTISIG = multisig;
    }

    modifier restricted() {
        require(msg.sender == MULTISIG, "Not authorized");
        _;
    }

    function getNextPositionWidth() public view override returns (uint24 width, int24 tickTWAP) {
        (width, tickTWAP) = super.getNextPositionWidth();
        if (governedWidth > width) width = governedWidth;
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
        require(totalSupply() <= maxTotalSupply, "Aloe: Vault filled up");
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
            token != TOKEN0 &&
            token != TOKEN1 &&
            silo0.shouldAllowEmergencySweepOf(address(token)) &&
            silo1.shouldAllowEmergencySweepOf(address(token)),
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

    function setGovernedWidth(uint24 _governedWidth) external restricted {
        governedWidth = _governedWidth;
    }

    function setK(uint8 _K) external restricted {
        K = _K;
    }

    function setMaintenanceFee(uint256 _maintenanceFee) external restricted {
        maintenanceFee = _maintenanceFee;
    }

    function setSilos(ISilo _silo0, ISilo _silo1) external restricted {
        pendingSilos = PendingSilos(_silo0, _silo1, block.timestamp);
    }

    function switchToPendingSilos() external restricted {
        require(block.timestamp > pendingSilos.timestamp + TIMELOCK, "TIMELOCK");

        silo0.delegate_poke();
        silo1.delegate_poke();
        silo0.delegate_withdraw(silo0.balanceOf(address(this)));
        silo1.delegate_withdraw(silo1.balanceOf(address(this)));

        silo0 = pendingSilos.silo0;
        silo1 = pendingSilos.silo1;
    }
}
