// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @author philogy <https://github.com/philogy>
interface ITokenGiver {
    function getTokens(address token, uint256 amount) external;

    function delayedSettlementModule() external view returns (address);
}
