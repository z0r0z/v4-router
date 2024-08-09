// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseHook} from "./BaseHook.sol";

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {IPoolManager} from "@v4/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@v4/src/types/PoolId.sol";
import {
    toBeforeSwapDelta,
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@v4/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@v4/src/types/Currency.sol";
import {SafeCast} from "@v4/src/libraries/SafeCast.sol";

contract SenderHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    mapping(address user => bool allowed) public allowedUsers;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        bytes calldata hookData
    ) external view override returns (bytes4, BeforeSwapDelta, uint24) {
        // --- Read the user's address --- //
        address user = abi.decode(hookData, (address));
        require(allowedUsers[user], "MsgSenderHookData: User not allowed");
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // Helper function for demonstration
    function setAllowedUser(address user, bool allowed) external {
        allowedUsers[user] = allowed;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
