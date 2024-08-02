// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {TickMath} from "@v4/src/libraries/TickMath.sol";
import {IPoolManager} from "@v4/src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@v4/src/types/BalanceDelta.sol";

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

/// @title Uniswap V4 Swap Router
/// @notice Router for stateless execution of swaps against Uniswap V4.
contract V4SwapRouter {
    /// ======================= CUSTOM ERRORS ======================= ///

    /// @dev Pool authority check.
    error Unauthorized();

    /// @dev Insufficient swap output.
    error InsufficientOutput();

    /// ========================= CONSTANTS ========================= ///

    /// @dev The address of the Uniswap V4 pool manager singleton.
    /// note: This is made `internal` to save gas. PoolManager
    /// will be a canonical deployment, so address is known.
    IPoolManager internal immutable UNISWAP_V4_POOL_MANAGER;

    /// @dev The minimum sqrt price limit for the swap.
    uint160 internal constant MIN = TickMath.MIN_SQRT_PRICE + 1;

    /// @dev The maximum sqrt price limit for the swap.
    uint160 internal constant MAX = TickMath.MAX_SQRT_PRICE - 1;

    /// ======================== CONSTRUCTOR ======================== ///

    /// @dev Create with Uniswap V4 pool manager.
    constructor(IPoolManager manager) payable {
        UNISWAP_V4_POOL_MANAGER = manager;
    }

    /// ===================== SWAP EXECUTION ===================== ///

    /// @dev Call into the PoolManager with Swap struct and path of keys.
    function swap(Swap calldata swaps) public payable returns (BalanceDelta) {
        return abi.decode(
            UNISWAP_V4_POOL_MANAGER.unlock(abi.encodePacked(msg.sender, abi.encode(swaps))),
            (BalanceDelta)
        );
    }

    /// @dev Handle PoolManager Swap instructions and perform any swaps in their key sequence.
    function unlockCallback(bytes calldata callbackData) public payable returns (bytes memory) {
        if (msg.sender != address(UNISWAP_V4_POOL_MANAGER)) revert Unauthorized();

        address swapper; // Optimize callback calldata load.
        assembly ("memory-safe") {
            swapper := shr(96, calldataload(callbackData.offset))
        }

        Swap memory swaps = abi.decode(callbackData[20:], (Swap));

        uint256 swapLen = swaps.keys.length;

        if (swapLen == 1) {
            return _swapSingle(swapper, swaps);
        } else {
            (swaps.fromCurrency, swaps.amountSpecified) = _swapFirst(swapper, swaps);
            uint256 i = 1;
            if (swapLen > 2) {
                unchecked {
                    for (i; i != swapLen - 1; ++i) {
                        (swaps.fromCurrency, swaps.amountSpecified) =
                            _swapMid(swaps.fromCurrency, swaps.amountSpecified, swaps.keys[i]);
                    }
                }
            }
            return _swapLast(
                swaps.fromCurrency,
                swaps.amountSpecified,
                swaps.keys[i],
                swaps.receiver,
                swaps.amountOutMin
            );
        }
    }

    function _swapSingle(address swapper, Swap memory swaps) internal returns (bytes memory) {
        bool exactIn = swaps.amountSpecified < 0;

        (bool zeroForOne, Currency toCurrency, BalanceDelta delta) =
            _swap(swaps.fromCurrency, swaps.amountSpecified, swaps.keys[0]);

        uint256 takeAmount = zeroForOne
            ? (exactIn ? uint256(uint128(delta.amount1())) : uint256(uint128(-delta.amount0())))
            : (exactIn ? uint256(uint128(delta.amount0())) : uint256(uint128(-delta.amount1())));

        UNISWAP_V4_POOL_MANAGER.sync(swaps.fromCurrency);

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

        UNISWAP_V4_POOL_MANAGER.settle{value: address(this).balance}();
        UNISWAP_V4_POOL_MANAGER.take(toCurrency, swaps.receiver, amountOut);

        return abi.encode(delta);
    }

    function _swapFirst(address swapper, Swap memory swaps) internal returns (Currency, int256) {
        bool exactIn = swaps.amountSpecified < 0;

        (bool zeroForOne, Currency toCurrency, BalanceDelta delta) =
            _swap(swaps.fromCurrency, swaps.amountSpecified, swaps.keys[0]);

        uint256 takeAmount = zeroForOne
            ? (exactIn ? uint256(uint128(delta.amount1())) : uint256(uint128(-delta.amount0())))
            : (exactIn ? uint256(uint128(delta.amount0())) : uint256(uint128(-delta.amount1())));

        UNISWAP_V4_POOL_MANAGER.sync(swaps.fromCurrency);

        if (Currency.unwrap(swaps.fromCurrency) != address(0)) {
            safeTransferFrom(
                Currency.unwrap(swaps.fromCurrency),
                swapper,
                msg.sender, // PoolManager.
                exactIn ? uint256(-swaps.amountSpecified) : takeAmount
            );
        }

        UNISWAP_V4_POOL_MANAGER.settle{value: address(this).balance}();
        UNISWAP_V4_POOL_MANAGER.take(
            toCurrency, address(this), exactIn ? takeAmount : uint256(swaps.amountSpecified)
        );

        return (toCurrency, exactIn ? int256(takeAmount) : swaps.amountSpecified);
    }

    function _swapMid(Currency fromCurrency, int256 takeIn, Key memory key)
        internal
        returns (Currency, int256)
    {
        (bool zeroForOne, Currency toCurrency, BalanceDelta delta) =
            _swap(fromCurrency, -takeIn, key);

        uint256 takeAmount = uint256(uint128((zeroForOne ? delta.amount1() : delta.amount0())));
        UNISWAP_V4_POOL_MANAGER.sync(fromCurrency);

        if (Currency.unwrap(fromCurrency) != address(0)) {
            safeTransfer(
                Currency.unwrap(fromCurrency),
                msg.sender, // PoolManager.
                uint256(takeIn)
            );
        }

        UNISWAP_V4_POOL_MANAGER.settle{value: address(this).balance}();
        UNISWAP_V4_POOL_MANAGER.take(toCurrency, address(this), takeAmount);

        return (toCurrency, int256(takeAmount));
    }

    function _swapLast(
        Currency fromCurrency,
        int256 takeIn,
        Key memory key,
        address receiver,
        uint256 amountOutMin
    ) internal returns (bytes memory) {
        (bool zeroForOne, Currency toCurrency, BalanceDelta delta) =
            _swap(fromCurrency, -takeIn, key);

        uint256 takeAmount = uint256(uint128((zeroForOne ? delta.amount1() : delta.amount0())));
        if (takeAmount < amountOutMin) revert InsufficientOutput();
        UNISWAP_V4_POOL_MANAGER.sync(fromCurrency);

        if (Currency.unwrap(fromCurrency) != address(0)) {
            safeTransfer(
                Currency.unwrap(fromCurrency),
                msg.sender, // PoolManager.
                uint256(takeIn)
            );
        }

        UNISWAP_V4_POOL_MANAGER.settle{value: address(this).balance}();
        UNISWAP_V4_POOL_MANAGER.take(toCurrency, receiver, takeAmount);

        return abi.encode(delta);
    }

    function _swap(Currency fromCurrency, int256 amountSpecified, Key memory key)
        internal
        returns (bool zeroForOne, Currency toCurrency, BalanceDelta delta)
    {
        zeroForOne = fromCurrency < key.key.currency1;
        toCurrency = zeroForOne ? key.key.currency1 : key.key.currency0;
        delta = UNISWAP_V4_POOL_MANAGER.swap(
            key.key,
            IPoolManager.SwapParams(zeroForOne, amountSpecified, zeroForOne ? MIN : MAX),
            key.hookData
        );
    }

    receive() external payable {
        if (msg.sender != address(UNISWAP_V4_POOL_MANAGER)) revert Unauthorized();
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
