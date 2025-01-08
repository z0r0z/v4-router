// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {
    PathKey, PoolKey, Currency, BalanceDelta, IV4SwapRouter
} from "./interfaces/IV4SwapRouter.sol";
import {IPoolManager, BaseData, BaseSwapRouter} from "./base/BaseSwapRouter.sol";

/// @title Uniswap V4 Swap Router
contract V4SwapRouter is IV4SwapRouter, BaseSwapRouter {
    constructor(IPoolManager manager) payable BaseSwapRouter(manager) {}

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
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: false,
                    isExactOutput: true,
                    amount: amountOut,
                    amountLimit: amountInMax
                }),
                startCurrency,
                path
            )
        );
    }

    /// @inheritdoc IV4SwapRouter
    function swap(
        int256 amountSpecified,
        uint256 amountTolerance,
        Currency startCurrency,
        PathKey[] calldata path,
        address to,
        uint256 deadline
    ) public payable virtual override checkDeadline(deadline) returns (BalanceDelta) {
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: false,
                    isExactOutput: amountSpecified > 0,
                    amount: amountSpecified > 0 ? uint256(amountSpecified) : uint256(-amountSpecified),
                    amountLimit: amountTolerance
                }),
                startCurrency,
                path
            )
        );
    }

    /// @inheritdoc IV4SwapRouter
    function swap(bytes calldata data, uint256 deadline)
        public
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
    ) public payable virtual override checkDeadline(deadline) returns (BalanceDelta) {
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: true,
                    isExactOutput: false,
                    amount: amountIn,
                    amountLimit: amountOutMin
                }),
                zeroForOne,
                poolKey,
                hookData
            )
        );
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
    ) public payable virtual override checkDeadline(deadline) returns (BalanceDelta) {
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: true,
                    isExactOutput: true,
                    amount: amountOut,
                    amountLimit: amountInMax
                }),
                zeroForOne,
                poolKey,
                hookData
            )
        );
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
    ) public payable virtual override checkDeadline(deadline) returns (BalanceDelta) {
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
