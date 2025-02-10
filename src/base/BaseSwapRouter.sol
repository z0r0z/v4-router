// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {SwapFlags} from "../libraries/SwapFlags.sol";
import {SafeCast} from "@v4/src/libraries/SafeCast.sol";
import {TickMath} from "@v4/src/libraries/TickMath.sol";
import {BalanceDelta} from "@v4/src/types/BalanceDelta.sol";
import {CurrencySettler} from "@v4/test/utils/CurrencySettler.sol";
import {ISignatureTransfer} from "@permit2/interfaces/ISignatureTransfer.sol";
import {TransientStateLibrary} from "@v4/src/libraries/TransientStateLibrary.sol";
import {IPoolManager, SafeCallback} from "@v4-periphery/src/base/SafeCallback.sol";
import {
    Currency, CurrencyLibrary, PoolKey, PathKey, PathKeyLibrary
} from "../libraries/PathKey.sol";

struct BaseData {
    uint256 amount;
    uint256 amountLimit;
    address payer;
    address receiver;
    uint8 flags;
}

struct PermitPayload {
    ISignatureTransfer.PermitTransferFrom permit;
    bytes signature;
}

/// @title Base Swap Router
/// @notice Template for data parsing and callback swap handling in Uniswap V4
abstract contract BaseSwapRouter is SafeCallback {
    using TransientStateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using PathKeyLibrary for PathKey;
    using SafeCast for uint256;
    using SafeCast for int256;

    ISignatureTransfer public immutable permit2;

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

    constructor(IPoolManager manager, ISignatureTransfer _permit2) SafeCallback(manager) {
        permit2 = _permit2;
    }

    /// ===================== SWAP EXECUTION ===================== ///

    function _unlockCallback(bytes calldata callbackData)
        internal
        virtual
        override(SafeCallback)
        returns (bytes memory)
    {
        unchecked {
            BaseData memory data = abi.decode(callbackData, (BaseData));

            (bool singleSwap, bool exactOutput, bool input6909, bool output6909, bool _permit2) =
                SwapFlags.unpackFlags(data.flags);

            (Currency inputCurrency, Currency outputCurrency, BalanceDelta delta) =
                _parseAndSwap(singleSwap, exactOutput, data.amount, _permit2, callbackData);

            uint256 inputAmount = uint256(-poolManager.currencyDelta(address(this), inputCurrency));
            uint256 outputAmount = exactOutput
                ? data.amount
                : (
                    inputCurrency < outputCurrency
                        ? uint256(uint128(delta.amount1()))
                        : uint256(uint128(delta.amount0()))
                );

            if (exactOutput ? inputAmount >= data.amountLimit : outputAmount <= data.amountLimit) {
                revert SlippageExceeded();
            }

            // handle ERC20 with permit2...
            if (_permit2) {
                (, PermitPayload memory permitPayload) =
                    abi.decode(callbackData, (BaseData, PermitPayload));
                poolManager.sync(inputCurrency);
                permit2.permitTransferFrom(
                    permitPayload.permit,
                    ISignatureTransfer.SignatureTransferDetails({
                        to: address(poolManager),
                        requestedAmount: inputAmount
                    }),
                    data.payer,
                    permitPayload.signature
                );
                poolManager.settle();
            } else {
                inputCurrency.settle(poolManager, data.payer, inputAmount, input6909);
            }

            outputCurrency.take(poolManager, data.receiver, outputAmount, output6909);

            // trigger refund of ETH if any left over after swap
            if (inputCurrency == CurrencyLibrary.ADDRESS_ZERO) {
                if (exactOutput) {
                    if ((outputAmount = address(this).balance) != 0) {
                        _refundETH(data.payer, outputAmount);
                    }
                }
            }

            return abi.encode(delta);
        }
    }

    function _parseAndSwap(
        bool isSingleSwap,
        bool isExactOutput,
        uint256 amount,
        bool settleWithPermit2,
        bytes calldata callbackData
    )
        internal
        virtual
        returns (Currency inputCurrency, Currency outputCurrency, BalanceDelta delta)
    {
        unchecked {
            if (isSingleSwap) {
                bool zeroForOne;
                PoolKey memory key;
                bytes memory hookData;

                if (settleWithPermit2) {
                    (,, zeroForOne, key, hookData) =
                        abi.decode(callbackData, (BaseData, PermitPayload, bool, PoolKey, bytes));
                } else {
                    (, zeroForOne, key, hookData) =
                        abi.decode(callbackData, (BaseData, bool, PoolKey, bytes));
                }

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
                if (settleWithPermit2) {
                    (,, inputCurrency, path) =
                        abi.decode(callbackData, (BaseData, PermitPayload, Currency, PathKey[]));
                } else {
                    (, inputCurrency, path) =
                        abi.decode(callbackData, (BaseData, Currency, PathKey[]));
                }

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
        unchecked {
            PoolKey memory poolKey;
            bool zeroForOne;
            int256 amountSpecified = -(amount.toInt256());
            uint256 len = path.length;

            // cache first path key
            PathKey memory pathKey = path[0];

            for (uint256 i; i < len;) {
                (poolKey, zeroForOne) = pathKey.getPoolAndSwapDirection(inputCurrency);
                finalDelta = _swap(poolKey, zeroForOne, amountSpecified, pathKey.hookData);

                inputCurrency = pathKey.intermediateCurrency;
                amountSpecified = zeroForOne ? -finalDelta.amount1() : -finalDelta.amount0();

                // load next path key
                if (++i < len) pathKey = path[i];
            }
        }
    }

    function _exactOutputMultiSwap(Currency startCurrency, PathKey[] memory path, uint256 amount)
        internal
        virtual
        returns (BalanceDelta finalDelta)
    {
        unchecked {
            PoolKey memory poolKey;
            bool zeroForOne;
            int256 amountSpecified = amount.toInt256();
            uint256 len = path.length;

            // cache last path key for first iteration
            PathKey memory pathKey = path[len - 1];

            // handle all but the final swap
            for (uint256 i = len - 1; i != 0;) {
                (poolKey, zeroForOne) =
                    pathKey.getPoolAndSwapDirection(path[--i].intermediateCurrency);

                BalanceDelta delta = _swap(poolKey, zeroForOne, amountSpecified, pathKey.hookData);

                // update amount for next iteration
                amountSpecified = zeroForOne ? -delta.amount0() : -delta.amount1();

                // load next pathKey for next iteration
                pathKey = path[i];
            }

            // final swap
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
                mstore(0x00, 0x82b42900) // `Unauthorized()`
                revert(0x1c, 0x04)
            }
        }
    }

    function _refundETH(address receiver, uint256 amount) internal virtual {
        assembly ("memory-safe") {
            if iszero(call(gas(), receiver, amount, codesize(), 0x00, codesize(), 0x00)) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`
                revert(0x1c, 0x04)
            }
        }
    }
}
