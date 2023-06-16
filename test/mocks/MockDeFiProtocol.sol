// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ICircuitBreaker} from "../../src/interfaces/ICircuitBreaker.sol";
import {ProtectedContract} from "../../src/core/ProtectedContract.sol";

contract MockDeFiProtocol is ProtectedContract {
    using SafeERC20 for IERC20;

    constructor(address _circuitBreaker) ProtectedContract(_circuitBreaker) {}

    /*
     * @notice Use _depositHook to safe transfer tokens and record inflow to circuit-breaker
     * @param _token Token to deposit
     * @param _amount Amount to deposit
     */
    function deposit(address _token, uint256 _amount) external {
        _depositHook(_token, msg.sender, address(this), _amount);

        // Your logic here
    }

    /*
     * @notice Withdrawal hook for circuit breaker to safe transfer tokens and enforcement
     * @param _token Token to withdraw
     * @param _amount Amount to withdraw
     * @param _recipient Recipient of withdrawal
     * @param _revertOnRateLimit Revert if rate limit is reached
     */
    function withdrawal(address _token, uint256 _amount) external {
        //  Your logic here

        _withdrawalHook(_token, _amount, msg.sender, false);
    }

    // Used to compare gas usage with and without circuitBreaker
    function depositNoCircuitBreaker(address _token, uint256 _amount) external {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }
}
