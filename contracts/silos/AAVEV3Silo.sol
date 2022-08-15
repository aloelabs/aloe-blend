// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "contracts/libraries/FullMath.sol";
import "contracts/interfaces/ISilo.sol";

interface IPoolAddressesProvider {
    function getPool() external view returns (IPool);

    function getPoolDataProvider() external view returns (IPoolDataProvider);
}

interface IPoolDataProvider {
    function getReserveTokensAddresses(address asset)
        external
        view
        returns (
            address aToken,
            address stableDebtToken,
            address variableDebtToken
        );
}

interface IPool {
    /**
     * @notice Supplies an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User supplies 100 USDC and gets in return 100 aUSDC
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     **/
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @notice Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @param to The address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     **/
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

contract AAVEV3Silo is ISilo {
    /// @inheritdoc ISilo
    string public name;

    IPoolAddressesProvider public immutable poolAddressesProvider;

    address public immutable uToken;

    constructor(IPoolAddressesProvider _poolAddressesProvider, address _uToken) {
        poolAddressesProvider = _poolAddressesProvider;
        uToken = _uToken;

        IPoolDataProvider poolDataProvider = poolAddressesProvider.getPoolDataProvider();
        (address aToken, , ) = poolDataProvider.getReserveTokensAddresses(uToken);
        require(aToken != address(0), "Unsupported by AAVE");

        name = string(abi.encodePacked("AAVE ", IERC20Metadata(uToken).symbol(), " Silo"));
    }

    /// @inheritdoc ISilo
    function poke() external override {}

    /// @inheritdoc ISilo
    function deposit(uint256 amount) external override {
        if (amount == 0) return;
        IPool pool = poolAddressesProvider.getPool();
        _approve(uToken, address(pool), amount);
        pool.supply(uToken, amount, address(this), 0);
    }

    /// @inheritdoc ISilo
    function withdraw(uint256 amount) external override {
        if (amount == 0) return;
        IPool pool = poolAddressesProvider.getPool();
        require(pool.withdraw(uToken, amount, address(this)) == amount, "Failed to withdraw all, remov");
    }

    /// @inheritdoc ISilo
    function balanceOf(address account) external view override returns (uint256 balance) {
        IPoolDataProvider poolDataProvider = poolAddressesProvider.getPoolDataProvider();
        (address aToken, , ) = poolDataProvider.getReserveTokensAddresses(uToken);
        return IERC20(aToken).balanceOf(account);
    }

    /// @inheritdoc ISilo
    function shouldAllowRemovalOf(address token) external view override returns (bool shouldAllow) {
        IPoolDataProvider poolDataProvider = poolAddressesProvider.getPoolDataProvider();
        (address aToken, , ) = poolDataProvider.getReserveTokensAddresses(uToken);
        shouldAllow = token != aToken;
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
            IERC20(token).approve(spender, type(uint256).max);
        }
    }
}
