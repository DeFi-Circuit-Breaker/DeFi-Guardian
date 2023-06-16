// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ICircuitBreaker} from "../interfaces/ICircuitBreaker.sol";

// The ProtectedContract that uses a circuitBreaker for enforcing the circuit breaker
contract ProtectedContract {
    // Use the SafeERC20 library for the IERC20 interface
    using SafeERC20 for IERC20;

    // The circuitBreaker used by this contract
    ICircuitBreaker public circuitBreaker;

    // Initialize the contract with a circuitBreaker
    constructor(address _circuitBreaker) {
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
    }

    // Allows to set a new circuitBreaker
    function setCircuitBreaker(address _circuitBreaker) external {
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
    }

    // Internal function to be used when tokens are deposited
    // Transfers the tokens from sender to recipient and then calls the circuitBreaker's depositHook
    function _depositHook(
        address _token,
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal {
        // Transfer the tokens safely from sender to recipient
        IERC20(_token).safeTransferFrom(_sender, _recipient, _amount);
        // Call the circuitBreaker's depositHook
        circuitBreaker.depositHook(_token, _amount);
    }

    // Internal function to be used when tokens are withdrawn
    // Transfers the tokens to the circuitBreaker and then calls the circuitBreaker's withdrawalHook
    function _withdrawalHook(
        address _token,
        uint256 _amount,
        address _recipient,
        bool _revertOnRateLimit
    ) internal {
        // Transfer the tokens safely to the circuitBreaker
        IERC20(_token).safeTransfer(address(circuitBreaker), _amount);
        // Call the circuitBreaker's withdrawalHook
        circuitBreaker.withdrawalHook(_token, _amount, _recipient, _revertOnRateLimit);
    }
}
