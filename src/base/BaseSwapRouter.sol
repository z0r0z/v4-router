// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {CurrencySettler} from "@v4/test/utils/CurrencySettler.sol";
import {IPoolManager} from "@v4/src/interfaces/IPoolManager.sol";
import {BalanceDelta, toBalanceDelta, BalanceDeltaLibrary} from "@v4/src/types/BalanceDelta.sol";
import {TransientStateLibrary} from "@v4/src/libraries/TransientStateLibrary.sol";
import {SafeCast} from "@v4/src/libraries/SafeCast.sol";
import {PathKey, PathKeyLibrary} from "../libraries/PathKey.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {TickMath} from "@v4/src/libraries/TickMath.sol";

struct BaseData {
    uint256 amount;
    uint256 amountLimit;
    address payer;
    bool isSingleSwap;
    address to;
    bool isExactOutput;
}

/// TODO: natspec
abstract contract BaseSwapRouter is SafeCallback {
    using CurrencySettler for Currency;
    using SafeCast for uint256;
    using TransientStateLibrary for IPoolManager;
    using PathKeyLibrary for PathKey;
    /// ======================= CUSTOM ERRORS ======================= ///

    /// @dev Pool authority check.
    error Unauthorized();

    /// ========================= CONSTANTS ========================= ///

    /// @dev The minimum sqrt price limit for the swap.
    uint160 internal constant MIN = TickMath.MIN_SQRT_PRICE + 1;

    /// @dev The maximum sqrt price limit for the swap.
    uint160 internal constant MAX = TickMath.MAX_SQRT_PRICE - 1;

    /// ======================== CONSTRUCTOR ======================== ///

    /// @dev Create with Uniswap V4 pool manager.
    constructor(IPoolManager manager) SafeCallback(manager) {}

    /// ===================== SWAP EXECUTION ===================== ///

    /// @dev Handle PoolManager Swap instructions and perform any swaps in their key sequence.
    function _unlockCallback(bytes calldata callbackData)
        internal
        virtual
        override
        returns (bytes memory)
    {
        // decode the initial callback data
        BaseData memory data = abi.decode(callbackData, (BaseData));

        // decode additional data, perform single-pool swap or multi-pool swap
        (Currency inputCurrency, Currency outputCurrency) =
            _parseAndSwap(data.isSingleSwap, data.isExactOutput, data.amount, callbackData);

        // resolve deltas pay input currency and collect output currency
        // TODO: optimization - use BalanceDelta from PoolManager calls?
        uint256 inputAmount = uint256(-poolManager.currencyDelta(address(this), inputCurrency));
        uint256 outputAmount = uint256(poolManager.currencyDelta(address(this), outputCurrency));

        // check slippage, TODO: custom error
        data.isExactOutput
            ? require(inputAmount < data.amountLimit)
            : require(outputAmount > data.amountLimit);

        inputCurrency.settle(poolManager, data.payer, inputAmount, false);
        outputCurrency.take(poolManager, data.to, outputAmount, false);

        return abi.encode(toBalanceDelta(0, 0));
    }

    function _parseAndSwap(
        bool isSingleSwap,
        bool isExactOutput,
        uint256 amount,
        bytes calldata callbackData
    ) internal returns (Currency inputCurrency, Currency outputCurrency) {
        if (isSingleSwap) {
            (, bool zeroForOne, PoolKey memory key, bytes memory hookData) =
                abi.decode(callbackData, (BaseData, bool, PoolKey, bytes));
            (inputCurrency, outputCurrency) =
                zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);
            _swap(
                key, zeroForOne, isExactOutput ? amount.toInt256() : -(amount.toInt256()), hookData
            );
        } else {
            PathKey[] memory path;
            (, inputCurrency, path) = abi.decode(callbackData, (BaseData, Currency, PathKey[]));
            outputCurrency = path[path.length - 1].intermediateCurrency;
            isExactOutput
                ? _exactOutputMultiSwap(inputCurrency, path, amount)
                : _exactInputMultiSwap(inputCurrency, path, amount);
        }
    }

    function _exactInputMultiSwap(Currency inputCurrency, PathKey[] memory path, uint256 amount)
        internal
    {
        PoolKey memory poolKey;
        PathKey memory pathKey;
        bool zeroForOne;
        int256 amountSpecified = -(amount.toInt256());
        BalanceDelta delta;
        for (uint256 i; i < path.length; i++) {
            pathKey = path[i];
            (poolKey, zeroForOne) = pathKey.getPoolAndSwapDirection(inputCurrency);
            delta = _swap(poolKey, zeroForOne, amountSpecified, pathKey.hookData);

            inputCurrency = pathKey.intermediateCurrency;
            amountSpecified = zeroForOne ? -delta.amount1() : -delta.amount0();
        }
    }

    function _exactOutputMultiSwap(Currency inputCurrency, PathKey[] memory path, uint256 amount)
        internal
    {}

    function _swap(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        bytes memory hookData
    ) internal returns (BalanceDelta) {
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

    function _unlockAndDecode(bytes memory data) internal returns (BalanceDelta) {
        return abi.decode(poolManager.unlock(data), (BalanceDelta));
    }

    /// @notice Reverts if the deadline has passed
    /// @param deadline The timestamp at which the call is no longer valid, passed in by the caller
    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert(); // TODO: `revert DeadlinePassed(deadline);`
        _;
    }

    receive() external payable {
        if (msg.sender != address(poolManager)) revert Unauthorized();
    }
}
