// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {
    PathKey, PoolKey, Currency, BalanceDelta, IV4SwapRouter
} from "./interfaces/IV4SwapRouter.sol";
import {LibZip} from "@solady/src/utils/LibZip.sol";
import {ISignatureTransfer} from "@permit2/interfaces/ISignatureTransfer.sol";
import {IPoolManager, BaseData, BaseSwapRouter, SwapFlags} from "./base/BaseSwapRouter.sol";

/// @title Uniswap V4 Swap Router
contract V4SwapRouter is IV4SwapRouter, BaseSwapRouter {
    constructor(IPoolManager manager, ISignatureTransfer _permit2)
        payable
        BaseSwapRouter(manager, _permit2)
    {}

    /// -----------------------

    /// @inheritdoc IV4SwapRouter
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Currency startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    )
        public
        payable
        virtual
        override(IV4SwapRouter)
        checkDeadline(deadline)
        returns (BalanceDelta)
    {
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    amount: amountIn,
                    amountLimit: amountOutMin,
                    payer: msg.sender,
                    receiver: receiver,
                    flags: 0
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
        address receiver,
        uint256 deadline
    )
        public
        payable
        virtual
        override(IV4SwapRouter)
        checkDeadline(deadline)
        returns (BalanceDelta)
    {
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    amount: amountOut,
                    amountLimit: amountInMax,
                    payer: msg.sender,
                    receiver: receiver,
                    flags: SwapFlags.EXACT_OUTPUT
                }),
                startCurrency,
                path
            )
        );
    }

    /// @inheritdoc IV4SwapRouter
    function swap(
        int256 amountSpecified,
        uint256 amountLimit,
        Currency startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    )
        public
        payable
        virtual
        override(IV4SwapRouter)
        checkDeadline(deadline)
        returns (BalanceDelta)
    {
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    amount: amountSpecified > 0 ? uint256(amountSpecified) : uint256(-amountSpecified),
                    amountLimit: amountLimit,
                    payer: msg.sender,
                    receiver: receiver,
                    flags: amountSpecified > 0 ? SwapFlags.EXACT_OUTPUT : 0
                }),
                startCurrency,
                path
            )
        );
    }

    /// -----------------------

    /// @inheritdoc IV4SwapRouter
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    )
        public
        payable
        virtual
        override(IV4SwapRouter)
        checkDeadline(deadline)
        returns (BalanceDelta)
    {
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    amount: amountIn,
                    amountLimit: amountOutMin,
                    payer: msg.sender,
                    receiver: receiver,
                    flags: SwapFlags.SINGLE_SWAP
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
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    )
        public
        payable
        virtual
        override(IV4SwapRouter)
        checkDeadline(deadline)
        returns (BalanceDelta)
    {
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    amount: amountOut,
                    amountLimit: amountInMax,
                    payer: msg.sender,
                    receiver: receiver,
                    flags: SwapFlags.SINGLE_SWAP | SwapFlags.EXACT_OUTPUT
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
        uint256 amountLimit,
        bool zeroForOne,
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    )
        public
        payable
        virtual
        override(IV4SwapRouter)
        checkDeadline(deadline)
        returns (BalanceDelta)
    {
        return _unlockAndDecode(
            abi.encode(
                BaseData({
                    amount: amountSpecified > 0 ? uint256(amountSpecified) : uint256(-amountSpecified),
                    amountLimit: amountLimit,
                    payer: msg.sender,
                    receiver: receiver,
                    flags: SwapFlags.SINGLE_SWAP | (amountSpecified > 0 ? SwapFlags.EXACT_OUTPUT : 0)
                }),
                zeroForOne,
                poolKey,
                hookData
            )
        );
    }

    /// -----------------------

    /// @inheritdoc IV4SwapRouter
    function swap(bytes calldata data, uint256 deadline)
        public
        payable
        virtual
        override(IV4SwapRouter)
        checkDeadline(deadline)
        returns (BalanceDelta)
    {
        return _unlockAndDecode(data);
    }

    /// -----------------------

    /// @inheritdoc IV4SwapRouter
    fallback() external payable virtual {
        LibZip.cdFallback();
    }
}
