// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.19;

import {IDelayedSettler, EffectState} from "../interfaces/IDelayedSettler.sol";

enum EffectType {
    ERC20,
    Native,
    Call
}

/// @author philogy <https://github.com/philogy>
abstract contract DelayedSettlementModule is IDelayedSettler {
    enum LockState {
        Uninitialized,
        Unlocked,
        Locked
    }

    mapping(bytes32 => address) private $ownedEffects;

    uint56 private $effectNonce;
    LockState private $lock;
    bool private $paused;

    function paused() external view virtual returns (bool) {
        return $paused;
    }
}
