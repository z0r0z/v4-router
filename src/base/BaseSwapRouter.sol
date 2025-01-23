// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {SafeCast} from "@v4/src/libraries/SafeCast.sol";
import {TickMath} from "@v4/src/libraries/TickMath.sol";
import {PathKey, PathKeyLibrary} from "../libraries/PathKey.sol";
import {CurrencySettler} from "@v4/test/utils/CurrencySettler.sol";
import {Currency, CurrencyLibrary} from "@v4/src/types/Currency.sol";
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

    /// @dev ETH refund fail.
    error ETHTransferFailed();

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
        override(SafeCallback)
        returns (bytes memory)
    {
        BaseData memory data = abi.decode(callbackData, (BaseData));

        (Currency inputCurrency, Currency outputCurrency, BalanceDelta delta) =
            _parseAndSwap(data.isSingleSwap, data.isExactOutput, data.amount, callbackData);

        // get the actual currency delta from pool manager
        int256 inputAmount = poolManager.currencyDelta(address(this), inputCurrency);

        // ensure settlement matches the delta
        inputCurrency.settle(poolManager, data.payer, uint256(-inputAmount), false);

        // for output, use the actual delta from the swap
        uint256 outputAmount = data.isExactOutput
            ? data.amount
            : (
                inputCurrency < outputCurrency
                    ? uint256(uint128(delta.amount1()))
                    : uint256(uint128(delta.amount0()))
            );

        outputCurrency.take(poolManager, data.to, outputAmount, false);

        // trigger refund of ETH if any left over after swap
        if (inputCurrency == CurrencyLibrary.ADDRESS_ZERO) {
            if ((outputAmount = address(this).balance) != 0) {
                _refundETH(data.payer, outputAmount);
            }
        }

        return abi.encode(delta);
    }

    function _parseAndSwap(
        bool isSingleSwap,
        bool isExactOutput,
        uint256 amount,
        bytes calldata callbackData
    )
        internal
        virtual
        returns (Currency inputCurrency, Currency outputCurrency, BalanceDelta delta)
    {
        unchecked {
            if (isSingleSwap) {
                (, bool zeroForOne, PoolKey memory key, bytes memory hookData) =
                    abi.decode(callbackData, (BaseData, bool, PoolKey, bytes));

                (inputCurrency, outputCurrency) =
                    zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

                delta = _swap(
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

                delta = isExactOutput
                    ? _exactOutputMultiSwap(inputCurrency, path, amount)
                    : _exactInputMultiSwap(inputCurrency, path, amount);
            }
        }
    }

    function _exactInputMultiSwap(Currency inputCurrency, PathKey[] memory path, uint256 amount)
        internal
        virtual
        returns (BalanceDelta finalDelta)
    {
        PoolKey memory poolKey;
        PathKey memory pathKey;
        bool zeroForOne;
        int256 amountSpecified = -(amount.toInt256());

        for (uint256 i; i != path.length; ++i) {
            pathKey = path[i];
            (poolKey, zeroForOne) = pathKey.getPoolAndSwapDirection(inputCurrency);
            finalDelta = _swap(poolKey, zeroForOne, amountSpecified, pathKey.hookData);

            inputCurrency = pathKey.intermediateCurrency;
            amountSpecified = zeroForOne ? -finalDelta.amount1() : -finalDelta.amount0();
        }
    }

    function _exactOutputMultiSwap(Currency startCurrency, PathKey[] memory path, uint256 amount)
        internal
        virtual
        returns (BalanceDelta finalDelta)
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

            // execute final swap and return its delta
            (poolKey, zeroForOne) = path[0].getPoolAndSwapDirection(startCurrency);
            finalDelta = _swap(poolKey, zeroForOne, amountSpecified, path[0].hookData);
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
        IPoolManager _poolManager = poolManager;
        assembly ("memory-safe") {
            if iszero(eq(caller(), _poolManager)) {
                mstore(0x00, 0x82b42900) // `Unauthorized()`.
                revert(0x1c, 0x04)
            }
        }
    }

    function _refundETH(address to, uint256 amount) internal virtual {
        assembly ("memory-safe") {
            if iszero(call(gas(), to, amount, codesize(), 0x00, codesize(), 0x00)) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }
}
