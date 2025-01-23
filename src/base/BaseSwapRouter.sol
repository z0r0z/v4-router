// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@v4/src/types/Currency.sol";
import {SafeCast} from "@v4/src/libraries/SafeCast.sol";
import {TickMath} from "@v4/src/libraries/TickMath.sol";
import {PathKey, PathKeyLibrary} from "../libraries/PathKey.sol";
import {CurrencySettler} from "@v4/test/utils/CurrencySettler.sol";
import {IPoolManager, SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {TransientStateLibrary} from "@v4/src/libraries/TransientStateLibrary.sol";
import {BalanceDelta, toBalanceDelta, BalanceDeltaLibrary} from "@v4/src/types/BalanceDelta.sol";

struct BaseData {
    uint256 amount;
    uint256 amountLimit;
    address payer;
    bool isSingleSwap;
    address to;
    bool isExactOutput;
}

/// @title Base Swap Router
/// @notice Template for data parsing and callback swap handling in Uniswap V4
abstract contract BaseSwapRouter is SafeCallback {
    using TransientStateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using PathKeyLibrary for PathKey;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// ======================= CUSTOM ERRORS ======================= ///

    /// @dev No path.
    error EmptyPath();

    /// @dev Auth check.
    error Unauthorized();

    /// @dev Slippage check.
    error SlippageExceeded();

    /// @dev Swap `block.timestamp` check.
    error DeadlinePassed(uint256 deadline);

    /// ========================= CONSTANTS ========================= ///

    /// @dev The minimum sqrt price limit for the swap.
    uint160 internal constant MIN = TickMath.MIN_SQRT_PRICE + 1;

    /// @dev The maximum sqrt price limit for the swap.
    uint160 internal constant MAX = TickMath.MAX_SQRT_PRICE - 1;

    /// ======================== CONSTRUCTOR ======================== ///

    constructor(IPoolManager manager) SafeCallback(manager) {}

    /// ===================== SWAP EXECUTION ===================== ///

    function _unlockCallback(bytes calldata callbackData)
        internal
        virtual
        override
        returns (bytes memory)
    {
        BaseData memory data = abi.decode(callbackData, (BaseData));

        (Currency inputCurrency, Currency outputCurrency) =
            _parseAndSwap(data.isSingleSwap, data.isExactOutput, data.amount, callbackData);

        // TODO: optimization - use BalanceDelta from PoolManager calls?
        uint256 inputAmount = uint256(-poolManager.currencyDelta(address(this), inputCurrency));
        uint256 outputAmount = uint256(poolManager.currencyDelta(address(this), outputCurrency));

        if (data.isExactOutput ? inputAmount >= data.amountLimit : outputAmount <= data.amountLimit)
        {
            revert SlippageExceeded();
        }

        inputCurrency.settle(poolManager, data.payer, inputAmount, false);
        outputCurrency.take(poolManager, data.to, outputAmount, false);

        // refund any excess native Ether
        if (0 < address(this).balance) {
            if (inputCurrency == CurrencyLibrary.ADDRESS_ZERO) {
                payable(data.payer).transfer(address(this).balance);
            }
        }

        return abi.encode(
            toBalanceDelta(-(inputAmount.toInt256().toInt128()), outputAmount.toInt256().toInt128())
        );
    }

    function _parseAndSwap(
        bool isSingleSwap,
        bool isExactOutput,
        uint256 amount,
        bytes calldata callbackData
    ) internal virtual returns (Currency inputCurrency, Currency outputCurrency) {
        unchecked {
            if (isSingleSwap) {
                (, bool zeroForOne, PoolKey memory key, bytes memory hookData) =
                    abi.decode(callbackData, (BaseData, bool, PoolKey, bytes));

                (inputCurrency, outputCurrency) =
                    zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

                _swap(
                    key,
                    zeroForOne,
                    isExactOutput ? amount.toInt256() : -(amount.toInt256()),
                    hookData
                );
            } else {
                PathKey[] memory path;
                (, inputCurrency, path) = abi.decode(callbackData, (BaseData, Currency, PathKey[]));

                if (path.length == 0) revert EmptyPath();

                outputCurrency = path[path.length - 1].intermediateCurrency;

                isExactOutput
                    ? _exactOutputMultiSwap(inputCurrency, path, amount)
                    : _exactInputMultiSwap(inputCurrency, path, amount);
            }
        }
    }

    function _exactInputMultiSwap(Currency inputCurrency, PathKey[] memory path, uint256 amount)
        internal
        virtual
    {
        PoolKey memory poolKey;
        PathKey memory pathKey;
        bool zeroForOne;
        int256 amountSpecified = -(amount.toInt256());
        BalanceDelta delta;

        for (uint256 i; i != path.length; ++i) {
            pathKey = path[i];
            (poolKey, zeroForOne) = pathKey.getPoolAndSwapDirection(inputCurrency);
            delta = _swap(poolKey, zeroForOne, amountSpecified, pathKey.hookData);

            inputCurrency = pathKey.intermediateCurrency;
            amountSpecified = zeroForOne ? -delta.amount1() : -delta.amount0();
        }
    }

    function _exactOutputMultiSwap(Currency startCurrency, PathKey[] memory path, uint256 amount)
        internal
        virtual
    {
        unchecked {
            PoolKey memory poolKey;
            PathKey memory pathKey;
            bool zeroForOne;
            int256 amountSpecified = amount.toInt256();
            BalanceDelta delta;

            // iterate backwards through the path
            // for "startCurrency -> B -> C -> D", `path` intermediate currencies are [B, C, D]
            // swap exact output:
            // 1. swap C for D
            // 2. swap B for C
            // 3  swap startCurrency for B
            for (uint256 i = path.length - 1; i != 0; --i) {
                pathKey = path[i];
                (poolKey, zeroForOne) =
                    pathKey.getPoolAndSwapDirection(path[i - 1].intermediateCurrency);
                delta = _swap(poolKey, zeroForOne, amountSpecified, pathKey.hookData);

                // if swapped token0 -> token1, then token0 is negative delta (signalling the "owed" currency)
                // delta.amount0() value should be used as the exactOutput value for the next swap
                // invert the negative delta to a positive value to signal an exactOutput swap
                amountSpecified = zeroForOne ? -delta.amount0() : -delta.amount1();
            }
            (poolKey, zeroForOne) = path[0].getPoolAndSwapDirection(startCurrency);
            _swap(poolKey, zeroForOne, amountSpecified, path[0].hookData);
        }
    }

    function _swap(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        bytes memory hookData
    ) internal virtual returns (BalanceDelta) {
        return poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? MIN : MAX
            }),
            hookData
        );
    }

    function _unlockAndDecode(bytes memory data) internal virtual returns (BalanceDelta) {
        return abi.decode(poolManager.unlock(data), (BalanceDelta));
    }

    modifier checkDeadline(uint256 deadline) virtual {
        if (block.timestamp > deadline) revert DeadlinePassed(deadline);
        _;
    }

    receive() external payable virtual {
        if (msg.sender != address(poolManager)) revert Unauthorized();
    }
}
