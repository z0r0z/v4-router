// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {BalanceDelta} from "@v4/src/types/BalanceDelta.sol";
import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";

/// @title Uniswap V4 Swap Router
/// @notice A simple, stateless router for execution of swaps against Uniswap v4 Pools
/// @dev ABI inspired by UniswapV2Router02
interface IV4SwapRouter {
    /// ================ MULTI POOL SWAPS ================= ///

    /// @notice Exact Input Swap; swap the specified amount of input tokens for as many output tokens as possible, along the path
    /// @param amountIn the amount of input tokens to swap
    /// @param amountOutMin the minimum amount of output tokens that must be received for the transaction not to revert
    /// @param startCurrency the currency to start the swap from
    /// @param path the path of v4 Pools to swap through
    /// @param to the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Currency startCurrency,
        PathKey[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// @notice Exact Output Swap; swap as few input tokens as possible for the specified amount of output tokens, along the path
    /// @param amountOut the amount of output tokens to receive
    /// @param amountInMax the maximum amount of input tokens that can be spent for the transaction not to revert
    /// @param startCurrency the currency to start the swap from
    /// @param path the path of v4 Pools to swap through
    /// @param to the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        Currency startCurrency,
        PathKey[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// @notice a general-purpose swap interface for Uniswap v4 that handles all types of swaps
    /// @param amountSpecified the amount of tokens to be swapped, negative for exact input swaps and positive for exact output swaps
    /// @param amountLimit the minimum amount of output tokens for exact input swaps, the maximum amount of input tokens for exact output swaps
    /// @param startCurrency the currency to start the swap from
    /// @param path the path of v4 Pools to swap through
    /// @param to the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    function swap(
        int256 amountSpecified,
        uint256 amountLimit,
        Currency startCurrency,
        PathKey[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// ================ SINGLE POOL SWAPS ================ ///

    /// @notice Single pool, exact input swap - swap the specified amount of input tokens for as many output tokens as possible, on a single pool
    /// @param amountIn the amount of input tokens to swap
    /// @param amountOutMin the minimum amount of output tokens that must be received for the transaction not to revert
    /// @param zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    /// @param poolKey the pool to swap through
    /// @param hookData the data to be passed to the hook
    /// @param to the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        PoolKey memory poolKey,
        bytes memory hookData,
        address to,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// @notice Singe pool, exact output swap; swap as few input tokens as possible for the specified amount of output tokens, on a single pool
    /// @param amountOut the amount of output tokens to receive
    /// @param amountInMax the maximum amount of input tokens that can be spent for the transaction not to revert
    /// @param zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    /// @param poolKey the pool to swap through
    /// @param hookData the data to be passed to the hook
    /// @param to the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        bool zeroForOne,
        PoolKey memory poolKey,
        bytes memory hookData,
        address to,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// @notice a general-purpose single-pool swap interface
    /// @param amountSpecified the amount of tokens to be swapped, negative for exact input swaps and positive for exact output swaps
    /// @param amountLimit the minimum amount of output tokens for exact input swaps, the maximum amount of input tokens for exact output swaps
    /// @param zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    /// @param poolKey the pool to swap through
    /// @param hookData the data to be passed to the hook
    /// @param to the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    function swap(
        int256 amountSpecified,
        uint256 amountLimit,
        bool zeroForOne,
        PoolKey memory poolKey,
        bytes memory hookData,
        address to,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// ================ OPTIMIZED ================ ///

    /// @notice An generic multi-pool swap function that accepts pre-encoded calldata
    /// @dev a minor optimization to reduce the number of onchain abi.encode calls
    /// @param data TODO: pre-encoded swap data, abi.encode(TODO: )
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    function swap(bytes calldata data, uint256 deadline) external payable returns (BalanceDelta);
}
