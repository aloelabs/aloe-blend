// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../external/compound/CERC20.sol";
import "../external/compound/CEther.sol";
import "../external/compound/Comptroller.sol";
import "../external/WETH.sol";

library Compound {
    using SafeERC20 for IERC20;

    CEther public constant CETH = CEther(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);

    struct Market {
        address cToken;
        address uToken;
    }

    function initialize(Market storage market, address cToken) internal {
        try CERC20Storage(cToken).underlying() returns (address uToken) {
            market.cToken = cToken;
            market.uToken = uToken;
        } catch {
            market.cToken = cToken;
            delete market.uToken;
        }
    }

    function poke(Market memory market) internal {
        CERC20(market.cToken).accrueInterest();
    }

    function deposit(Market memory market, uint amount) internal {
        if (market.cToken == address(CETH)) {
            WETH.withdraw(amount);
            CETH.mint{ value: amount }();
        } else {
            _approve(market.uToken, address(market.cToken), amount);
            require(CERC20(market.cToken).mint(amount) == 0, "Compound: mint failed");
        }
    }

    function withdraw(Market memory market, uint amount) internal {
        if (market.cToken == address(CETH)) {
            require(CETH.redeemUnderlying(amount) == 0, "Compound: redeem failed");
            WETH.deposit{ value: amount }();
        } else {
            require(CERC20(market.cToken).redeemUnderlying(amount) == 0, "Compound: redeem failed");
        }
    }

    function getBalance(Market memory market) internal view returns (uint256 balance) {
        CERC20 cToken = CERC20(market.cToken);
        return cToken.balanceOf(address(this)) * cToken.exchangeRateStored();
    }

    function _approve(address token, address spender, uint256 amount) private {
        // 200 gas to read uint256
        if (IERC20(token).allowance(address(this), spender) < amount) {
            // 20000 gas to write uint256 if changing from zero to non-zero
            // 5000  gas to write uint256 if changing from non-zero to non-zero
            IERC20(token).safeApprove(spender, type(uint256).max);
        }
    }
}
