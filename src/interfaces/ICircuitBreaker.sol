// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {LiqChangeNode} from "../static/Structs.sol";

interface ICircuitBreaker {
    /**
     *
     * State changing functions *
     *
     */

    function onTokenInflow(address _token, uint256 _amount) external;

    function onTokenOutflow(address _token, uint256 _amount, address _recipient, bool _revertOnRateLimit) external;

    function onTokenInflowNative(uint256 _amount) external;

    function onTokenOutflowNative(address _recipient, bool _revertOnRateLimit) external payable;

    function claimLockedFunds(address _token, address _recipient) external;

    function overrideExpiredRateLimit() external;

    function registerToken(address _token, uint256 _metricThreshold, uint256 _minAmountToLimit) external;

    function updateTokenParams(address _token, uint256 _metricThreshold, uint256 _minAmountToLimit) external;

    function overrideRateLimit() external;

    function addProtectedContracts(address[] calldata _ProtectedContracts) external;

    function removeProtectedContracts(address[] calldata _ProtectedContracts) external;

    function startGracePeriod(uint256 _gracePeriodEndTimestamp) external;

    function releaseLockedFunds(address _token, address[] calldata _recipients) external;

    function withdrawHackerFunds(address _token, address _hacker, address _recipient) external;

    function setAdmin(address _admin) external;

    /**
     *
     * Read-only functions *
     *
     */

    function lockedFunds(address recipient, address token) external view returns (uint256 amount);

    function isProtectedContract(address account) external view returns (bool protectionActive);

    function admin() external view returns (address);

    function isRateLimited() external view returns (bool);

    function rateLimitCooldownPeriod() external view returns (uint256);

    function lastRateLimitTimestamp() external view returns (uint256);

    function gracePeriodEndTimestamp() external view returns (uint256);

    function isRateLimitBreeched(address _token) external view returns (bool);

    function isInGracePeriod() external view returns (bool);
}
