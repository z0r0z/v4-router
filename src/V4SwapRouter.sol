// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {
    PathKey, PoolKey, Currency, BalanceDelta, IV4SwapRouter
} from "./interfaces/IV4SwapRouter.sol";
import {LibZip} from "@solady/src/utils/LibZip.sol";
import {IPoolManager, BaseData, BaseSwapRouter} from "./base/BaseSwapRouter.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

/// @title Uniswap V4 Swap Router
/// @custom:dislaimer
/// This community router code provided herein is offered on an “as-is” basis and has not been audited for security, reliability, or compliance with any specific standards or regulations.
/// It may contain bugs, errors, or vulnerabilities that could lead to unintended consequences.
/// By utilizing this community router, you acknowledge and agree that:
///
/// - Assumption of Risk: You assume all responsibility and risks associated with its use.
/// - No Warranty: The authors and distributors of this code, namely, z0r0z and the Uniswap Foundation, disclaim all warranties, express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, and non-infringement.
/// - Limitation of Liability: In no event shall the authors or distributors be held liable for any damages or losses, including but not limited to direct, indirect, incidental, or consequential damages arising out of or in connection with the use or inability to use the code.
/// - Recommendation: Users are strongly encouraged to review, test, and, if necessary, audit the community router independently before deploying in any environment.
///
/// By proceeding to utilize this community router, you indicate your understanding and acceptance of this disclaimer.
contract V4SwapRouter is IV4SwapRouter, BaseSwapRouter {
    constructor(IPoolManager manager, ISignatureTransfer _permit2)
        payable
        BaseSwapRouter(manager, _permit2)
    {}

    /// @inheritdoc IV4SwapRouter
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Currency startCurrency,
        PathKey[] calldata path,
        address to,
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
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: false,
                    isExactOutput: false,
                    amount: amountIn,
                    amountLimit: amountOutMin,
                    settleWithPermit2: false
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
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: false,
                    isExactOutput: true,
                    amount: amountOut,
                    amountLimit: amountInMax,
                    settleWithPermit2: false
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
        address to,
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
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: false,
                    isExactOutput: amountSpecified > 0,
                    amount: amountSpecified > 0 ? uint256(amountSpecified) : uint256(-amountSpecified),
                    amountLimit: amountLimit,
                    settleWithPermit2: false
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
        override(IV4SwapRouter)
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
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address to,
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
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: true,
                    isExactOutput: false,
                    amount: amountIn,
                    amountLimit: amountOutMin,
                    settleWithPermit2: false
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
        address to,
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
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: true,
                    isExactOutput: true,
                    amount: amountOut,
                    amountLimit: amountInMax,
                    settleWithPermit2: false
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
        address to,
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
                    payer: msg.sender,
                    to: to,
                    isSingleSwap: true,
                    isExactOutput: amountSpecified > 0,
                    amount: amountSpecified > 0 ? uint256(amountSpecified) : uint256(-amountSpecified),
                    amountLimit: amountLimit,
                    settleWithPermit2: false
                }),
                zeroForOne,
                poolKey,
                hookData
            )
        );
    }

    /// -----------------------

    /// TODO: document that `data = abi.encode(BaseData, PermitParams, ...)
    /// @inheritdoc IV4SwapRouter
    function swapWithPermit2(bytes calldata data, uint256 deadline)
        public
        payable
        virtual
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
