// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol"; // TODO: remove

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {CurrencySettler} from "@v4/test/utils/CurrencySettler.sol";
import {TickMath} from "@v4/src/libraries/TickMath.sol";
import {IPoolManager} from "@v4/src/interfaces/IPoolManager.sol";
import {BalanceDelta, toBalanceDelta, BalanceDeltaLibrary} from "@v4/src/types/BalanceDelta.sol";
import {TransientStateLibrary} from "@v4/src/libraries/TransientStateLibrary.sol";
import {SafeCast} from "@v4/src/libraries/SafeCast.sol";
import {PathKey, PathKeyLibrary} from "./libraries/PathKey.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {IV4SwapRouter} from "./interfaces/IV4SwapRouter.sol";

/// @dev The swap router params.
struct Swap {
    address receiver;
    Currency fromCurrency;
    int256 amountSpecified;
    uint256 amountOutMin;
    Key[] keys;
}

/// @dev Key and hook params.
struct Key {
    PoolKey key;
    bytes hookData;
}

struct BaseData {
    uint256 amount;
    uint256 amountLimit;
    address payer;
    bool isSingleSwap;
    address to;
    bool isExactOutput;
}

/// @title Uniswap V4 Swap Router
/// @notice Router for stateless execution of swaps against Uniswap V4.
contract V4SwapRouter is IV4SwapRouter, SafeCallback {
    using CurrencySettler for Currency;
    using SafeCast for uint256;
    using TransientStateLibrary for IPoolManager;
    using PathKeyLibrary for PathKey;
    /// ======================= CUSTOM ERRORS ======================= ///

    /// @dev Pool authority check.
    error Unauthorized();

    /// @dev Insufficient swap output.
    error InsufficientOutput();

    /// ========================= CONSTANTS ========================= ///

    /// @dev The minimum sqrt price limit for the swap.
    uint160 internal constant MIN = TickMath.MIN_SQRT_PRICE + 1;

    /// @dev The maximum sqrt price limit for the swap.
    uint160 internal constant MAX = TickMath.MAX_SQRT_PRICE - 1;

    /// ======================== CONSTRUCTOR ======================== ///

    /// @dev Create with Uniswap V4 pool manager.
    constructor(IPoolManager manager) SafeCallback(manager) {}

    /// ===================== SWAP EXECUTION ===================== ///

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

    /// @dev Call into the PoolManager with Swap struct and path of keys.
    function swap(Swap calldata swaps) public payable returns (BalanceDelta) {
        return abi.decode(
            poolManager.unlock(abi.encodePacked(msg.sender, abi.encode(swaps))), (BalanceDelta)
        );
    }

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
                ? _multiExactOutputSwap(inputCurrency, path, amount)
                : _multiExactInputSwap(inputCurrency, path, amount);
        }
    }

    function _swapSingle(address swapper, Swap memory swaps) internal returns (bytes memory) {
        unchecked {
            bool exactIn = swaps.amountSpecified < 0;

            (bool zeroForOne, Currency toCurrency, BalanceDelta delta) =
                _swap(swaps.fromCurrency, swaps.amountSpecified, swaps.keys[0]);

            uint256 takeAmount = zeroForOne
                ? (exactIn ? uint256(uint128(delta.amount1())) : uint256(uint128(-delta.amount0())))
                : (exactIn ? uint256(uint128(delta.amount0())) : uint256(uint128(-delta.amount1())));

            poolManager.sync(swaps.fromCurrency);

            if (Currency.unwrap(swaps.fromCurrency) != address(0)) {
                safeTransferFrom(
                    Currency.unwrap(swaps.fromCurrency),
                    swapper,
                    msg.sender, // PoolManager.
                    exactIn ? uint256(-swaps.amountSpecified) : takeAmount
                );
            }

            uint256 amountOut = exactIn ? takeAmount : uint256(swaps.amountSpecified);
            if (amountOut < swaps.amountOutMin) revert InsufficientOutput();

            poolManager.settle{value: address(this).balance}();
            poolManager.take(toCurrency, swaps.receiver, amountOut);

            return abi.encode(delta);
        }
    }

    function _swapFirst(address swapper, Swap memory swaps) internal returns (Currency, int256) {
        unchecked {
            bool exactIn = swaps.amountSpecified < 0;

            (bool zeroForOne, Currency toCurrency, BalanceDelta delta) =
                _swap(swaps.fromCurrency, swaps.amountSpecified, swaps.keys[0]);

            uint256 takeAmount = zeroForOne
                ? (exactIn ? uint256(uint128(delta.amount1())) : uint256(uint128(-delta.amount0())))
                : (exactIn ? uint256(uint128(delta.amount0())) : uint256(uint128(-delta.amount1())));

            poolManager.sync(swaps.fromCurrency);

            if (Currency.unwrap(swaps.fromCurrency) != address(0)) {
                safeTransferFrom(
                    Currency.unwrap(swaps.fromCurrency),
                    swapper,
                    msg.sender, // PoolManager.
                    exactIn ? uint256(-swaps.amountSpecified) : takeAmount
                );
            }

            poolManager.settle{value: address(this).balance}();
            poolManager.take(
                toCurrency, address(this), exactIn ? takeAmount : uint256(swaps.amountSpecified)
            );

            return (toCurrency, exactIn ? int256(takeAmount) : swaps.amountSpecified);
        }
    }

    function _swapMid(Currency fromCurrency, int256 takeIn, Key memory key)
        internal
        returns (Currency, int256)
    {
        unchecked {
            (bool zeroForOne, Currency toCurrency, BalanceDelta delta) =
                _swap(fromCurrency, -takeIn, key);

            uint256 takeAmount = uint256(uint128((zeroForOne ? delta.amount1() : delta.amount0())));
            poolManager.sync(fromCurrency);

            if (Currency.unwrap(fromCurrency) != address(0)) {
                safeTransfer(
                    Currency.unwrap(fromCurrency),
                    msg.sender, // PoolManager.
                    uint256(takeIn)
                );
            }

            poolManager.settle{value: address(this).balance}();
            poolManager.take(toCurrency, address(this), takeAmount);

            return (toCurrency, int256(takeAmount));
        }
    }

    function _swapLast(
        Currency fromCurrency,
        int256 takeIn,
        Key memory key,
        address receiver,
        uint256 amountOutMin
    ) internal returns (bytes memory) {
        unchecked {
            (bool zeroForOne, Currency toCurrency, BalanceDelta delta) =
                _swap(fromCurrency, -takeIn, key);

            uint256 takeAmount = uint256(uint128((zeroForOne ? delta.amount1() : delta.amount0())));
            if (takeAmount < amountOutMin) revert InsufficientOutput();
            poolManager.sync(fromCurrency);

            if (Currency.unwrap(fromCurrency) != address(0)) {
                safeTransfer(
                    Currency.unwrap(fromCurrency),
                    msg.sender, // PoolManager.
                    uint256(takeIn)
                );
            }

            poolManager.settle{value: address(this).balance}();
            poolManager.take(toCurrency, receiver, takeAmount);

            return abi.encode(delta);
        }
    }

    function _swap(Currency fromCurrency, int256 amountSpecified, Key memory key)
        internal
        returns (bool zeroForOne, Currency toCurrency, BalanceDelta delta)
    {
        unchecked {
            zeroForOne = fromCurrency < key.key.currency1;
            toCurrency = zeroForOne ? key.key.currency1 : key.key.currency0;
            delta = poolManager.swap(
                key.key,
                IPoolManager.SwapParams(zeroForOne, amountSpecified, zeroForOne ? MIN : MAX),
                key.hookData
            );
        }
    }

    function _multiExactInputSwap(Currency inputCurrency, PathKey[] memory path, uint256 amount)
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

    function _multiExactOutputSwap(Currency inputCurrency, PathKey[] memory path, uint256 amount)
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

    function _unlockAndDecode(bytes memory data) private returns (BalanceDelta) {
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

/// @dev Solady ERC20 token push pattern to gracefully handle non-standard return.
function safeTransfer(address token, address to, uint256 amount) {
    assembly ("memory-safe") {
        mstore(0x14, to)
        mstore(0x34, amount)
        mstore(0x00, 0xa9059cbb000000000000000000000000)
        if iszero(
            and(
                or(eq(mload(0x00), 1), iszero(returndatasize())),
                call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
            )
        ) {
            mstore(0x00, 0x90b8ec18)
            revert(0x1c, 0x04)
        }
        mstore(0x34, 0)
    }
}

/// @dev Solady ERC20 token pull pattern to gracefully handle non-standard return.
function safeTransferFrom(address token, address from, address to, uint256 amount) {
    assembly ("memory-safe") {
        let m := mload(0x40)
        mstore(0x60, amount)
        mstore(0x40, to)
        mstore(0x2c, shl(96, from))
        mstore(0x0c, 0x23b872dd000000000000000000000000)
        if iszero(
            and(
                or(eq(mload(0x00), 1), iszero(returndatasize())),
                call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
            )
        ) {
            mstore(0x00, 0x7939f424)
            revert(0x1c, 0x04)
        }
        mstore(0x60, 0)
        mstore(0x40, m)
    }
}
