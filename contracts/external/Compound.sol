// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libraries/FullMath.sol";

import "./compound/CERC20.sol";
import "./compound/CEther.sol";
import "./WETH.sol";

library Compound {
    using SafeERC20 for IERC20;

    CEther public constant CETH = CEther(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);

    struct Market {
        address cToken;
        address uToken;
    }

    function initialize(Market storage market, address cToken) internal {
        if (cToken == address(CETH)) {
            market.cToken = cToken;
            delete market.uToken;
        } else {
            market.cToken = cToken;
            market.uToken = CERC20Storage(cToken).underlying();
        }
    }

    function poke(Market memory market) internal {
        CERC20(market.cToken).accrueInterest();
    }

    function deposit(Market memory market, uint256 amount) internal {
        if (amount == 0) return;
        if (market.cToken == address(CETH)) {
            WETH.withdraw(amount);
            CETH.mint{value: amount}();
        } else {
            _approve(market.uToken, address(market.cToken), amount);
            require(CERC20(market.cToken).mint(amount) == 0, "Compound: mint failed");
        }
    }

    function withdraw(Market memory market, uint256 amount) internal {
        if (amount == 0) return;
        uint256 cAmount = 1 + FullMath.mulDiv(amount, 1e18, CERC20(market.cToken).exchangeRateStored());

        if (market.cToken == address(CETH)) {
            require(CETH.redeem(cAmount) == 0, "Compound: redeem ETH failed");
            WETH.deposit{value: amount}();
        } else {
            require(CERC20(market.cToken).redeem(cAmount) == 0, "Compound: redeem failed");
        }
    }

    function getBalance(Market memory market) internal view returns (uint256 balance) {
        CERC20 cToken = CERC20(market.cToken);
        return FullMath.mulDiv(cToken.balanceOf(address(this)), cToken.exchangeRateStored(), 1e18);
    }

    function _approve(
        address token,
        address spender,
        uint256 amount
    ) private {
        // 200 gas to read uint256
        if (IERC20(token).allowance(address(this), spender) < amount) {
            // 20000 gas to write uint256 if changing from zero to non-zero
            // 5000  gas to write uint256 if changing from non-zero to non-zero
            IERC20(token).safeApprove(spender, type(uint256).max);
        }
    }
}
