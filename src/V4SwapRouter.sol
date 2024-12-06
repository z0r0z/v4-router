// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol"; // TODO: remove

import {IPoolManager} from "@v4/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {BalanceDelta} from "@v4/src/types/BalanceDelta.sol";
import {Currency} from "@v4/src/types/Currency.sol";

import {BaseSwapRouter, BaseData} from "./base/BaseSwapRouter.sol";
import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";
import {PathKey} from "./libraries/PathKey.sol";
import {IV4SwapRouter} from "./interfaces/IV4SwapRouter.sol";

/// @title Uniswap V4 Swap Router
contract V4SwapRouter is IV4SwapRouter, BaseSwapRouter {
    constructor(IPoolManager manager) BaseSwapRouter(manager) {}

    /// @inheritdoc IV4SwapRouter
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Currency startCurrency,
        PathKey[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override checkDeadline(deadline) returns (BalanceDelta) {
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: false,
                    isExactOutput: false,
                    amount: amountIn,
                    amountLimit: amountOutMin
                }),
                startCurrency,
                path
            )
        );
    }

    /// @inheritdoc IV4SwapRouter
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        Currency startCurrency,
        PathKey[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override checkDeadline(deadline) returns (BalanceDelta) {
        return _unlockAndDecode(abi.encode());
    }

    /// @inheritdoc IV4SwapRouter
    function swap(
        int256 amountSpecified,
        uint256 amountTolerance,
        Currency startCurrency,
        PathKey[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override checkDeadline(deadline) returns (BalanceDelta) {
        return _unlockAndDecode(abi.encode());
    }

    /// @inheritdoc IV4SwapRouter
    function swap(bytes calldata data, uint256 deadline)
        external
        payable
        virtual
        override
        checkDeadline(deadline)
        returns (BalanceDelta)
    {
        return _unlockAndDecode(data);
    }

    /// -----------------------

    /// @inheritdoc IV4SwapRouter
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        PoolKey memory poolKey,
        bytes calldata hookData,
        address to,
        uint256 deadline
    ) external payable virtual override checkDeadline(deadline) returns (BalanceDelta) {
        return _unlockAndDecode(abi.encode());
    }

    /// @inheritdoc IV4SwapRouter
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        bool zeroForOne,
        PoolKey memory poolKey,
        bytes calldata hookData,
        address to,
        uint256 deadline
    ) external payable virtual override checkDeadline(deadline) returns (BalanceDelta) {
        return _unlockAndDecode(abi.encode());
    }

    /// @inheritdoc IV4SwapRouter
    function swap(
        int256 amountSpecified,
        uint256 amountTolerance,
        bool zeroForOne,
        PoolKey memory poolKey,
        bytes calldata hookData,
        address to,
        uint256 deadline
    ) external payable virtual override checkDeadline(deadline) returns (BalanceDelta) {
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: true,
                    isExactOutput: amountSpecified > 0,
                    amount: amountSpecified > 0 ? uint256(amountSpecified) : uint256(-amountSpecified),
                    amountLimit: amountTolerance
                }),
                zeroForOne,
                poolKey,
                hookData
            )
        );
    }
}
