// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

enum EffectState {
    Pending,
    Settled,
    Paused
}

/**
 * @author philogy <https://github.com/philogy>
 * @dev TODO: Add events
 */
interface IDelayedSettler {
    function deferERC20Transfer(address token, address recipient, uint256 inAmount)
        external
        returns (bytes32 newEffectID);

    function executeERC20Transfer(address token, uint256 inAmount, uint56 effectNonce, uint40 startedAt) external;

    function deferNativeTransfer(address recipient) external payable returns (bytes32 newEffectID);

    function executeNativeTransfer(uint256 amount, uint56 effectNonce, uint40 startedAt) external;

    function deferCall(address target, bytes calldata payload, uint256 beneficiaryOffset, address beneficiary)
        external
        payable
        returns (bytes32 newEffectID);

    function executeCall(
        address target,
        bytes calldata payload,
        uint256 beneficiaryOffset,
        uint256 nativeAmount,
        uint56 effectNonce,
        uint40 startedAt
    ) external payable returns (bytes32 newEffectID);

    function executionDelay() external view returns (uint256 delay);

    function paused() external view returns (bool);

    function getBeneficiary(bytes32 effectID) external view returns (address beneficiary);

    function getEffectState(bytes32 effectID) external view returns (EffectState state);
}
