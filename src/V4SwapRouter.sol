// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {TickMath} from "@v4/src/libraries/TickMath.sol";
import {IPoolManager} from "@v4/src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@v4/src/types/BalanceDelta.sol";

/// @dev Uniswap V4 swap params.
struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

/// @dev The router swap params.
struct Swap {
    address receiver;
    Currency fromCurrency;
    int256 amountSpecified;
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

    /// @dev Pool auth.
    error Unauthorized();

    /// ========================= CONSTANTS ========================= ///

    /// @dev The address of the Uniswap V4 pool manager singleton.
    /// note: This is made `internal` to save gas. PoolManager
    /// will be a canonical deployment, so address is known.
    IPoolManager internal immutable UNISWAP_V4_POOL_MANAGER;

    /// ======================== CONSTRUCTOR ======================== ///

    /// @dev Create with Uniswap V4 pool manager.
    constructor(IPoolManager manager) payable {
        UNISWAP_V4_POOL_MANAGER = manager;
    }

    /// ===================== SWAP EXECUTION ===================== ///

    function swap(Swap calldata swaps) public payable returns (BalanceDelta) {
        return abi.decode(
            UNISWAP_V4_POOL_MANAGER.unlock(abi.encodePacked(msg.sender, abi.encode(swaps))),
            (BalanceDelta)
        );
    }

    function unlockCallback(bytes calldata callbackData) public payable returns (bytes memory) {
        if (msg.sender != address(UNISWAP_V4_POOL_MANAGER)) revert Unauthorized();

        address swapper = address(bytes20(callbackData[:20]));
        Swap memory swaps = abi.decode(callbackData[20:], (Swap));

        if (swaps.keys.length == 1) {
            return _swapSingle(swapper, swaps);
        } else {
            (swaps.fromCurrency, swaps.amountSpecified) = _swapInitial(swapper, swaps);
            uint256 i = 1;
            if (swaps.keys.length > 2) {
                unchecked {
                    for (i; i != swaps.keys.length - 1; ++i) {
                        (swaps.fromCurrency, swaps.amountSpecified) = _swapIntermediate(
                            swaps.fromCurrency, swaps.amountSpecified, swaps.keys[i]
                        );
                    }
                }
            }
            return
                _swapFinal(swaps.fromCurrency, swaps.amountSpecified, swaps.keys[i], swaps.receiver);
        }
    }

    function _swapSingle(address swapper, Swap memory swaps) internal returns (bytes memory) {
        bool exactIn = swaps.amountSpecified < 0;
        bool zeroForOne = swaps.fromCurrency < swaps.keys[0].key.currency1;
        Currency toCurrency = zeroForOne ? swaps.keys[0].key.currency1 : swaps.keys[0].key.currency0;

        uint160 sqrtPriceLimitX96 =
            zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        BalanceDelta delta = UNISWAP_V4_POOL_MANAGER.swap(
            swaps.keys[0].key,
            IPoolManager.SwapParams(zeroForOne, swaps.amountSpecified, sqrtPriceLimitX96),
            swaps.keys[0].hookData
        );

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

        UNISWAP_V4_POOL_MANAGER.settle{value: address(this).balance}(swaps.fromCurrency);
        UNISWAP_V4_POOL_MANAGER.take(
            toCurrency, swaps.receiver, exactIn ? takeAmount : uint256(swaps.amountSpecified)
        );

        return abi.encode(delta);
    }

    function _swapInitial(address swapper, Swap memory swaps) internal returns (Currency, int256) {
        bool exactIn = swaps.amountSpecified < 0;
        bool zeroForOne = swaps.fromCurrency < swaps.keys[0].key.currency1;
        Currency toCurrency = zeroForOne ? swaps.keys[0].key.currency1 : swaps.keys[0].key.currency0;

        uint160 sqrtPriceLimitX96 =
            zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        BalanceDelta delta = UNISWAP_V4_POOL_MANAGER.swap(
            swaps.keys[0].key,
            IPoolManager.SwapParams(zeroForOne, swaps.amountSpecified, sqrtPriceLimitX96),
            swaps.keys[0].hookData
        );

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

        UNISWAP_V4_POOL_MANAGER.settle{value: address(this).balance}(swaps.fromCurrency);
        UNISWAP_V4_POOL_MANAGER.take(
            toCurrency, address(this), exactIn ? takeAmount : uint256(swaps.amountSpecified)
        );

        return (toCurrency, exactIn ? int256(takeAmount) : swaps.amountSpecified);
    }

    function _swapIntermediate(Currency fromCurrency, int256 takeIn, Key memory key)
        internal
        returns (Currency, int256)
    {
        bool zeroForOne = fromCurrency < key.key.currency1;
        Currency toCurrency = zeroForOne ? key.key.currency1 : key.key.currency0;

        uint160 sqrtPriceLimitX96 =
            zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        BalanceDelta delta = UNISWAP_V4_POOL_MANAGER.swap(
            key.key, IPoolManager.SwapParams(zeroForOne, -takeIn, sqrtPriceLimitX96), key.hookData
        );

        uint256 takeAmount = uint256(uint128((zeroForOne ? delta.amount1() : delta.amount0())));
        UNISWAP_V4_POOL_MANAGER.sync(fromCurrency);

        if (Currency.unwrap(fromCurrency) != address(0)) {
            safeTransfer(
                Currency.unwrap(fromCurrency),
                msg.sender, // PoolManager.
                uint256(takeIn)
            );
        }

        UNISWAP_V4_POOL_MANAGER.settle{value: address(this).balance}(fromCurrency);
        UNISWAP_V4_POOL_MANAGER.take(toCurrency, address(this), takeAmount);

        return (toCurrency, int256(takeAmount));
    }

    function _swapFinal(Currency fromCurrency, int256 takeIn, Key memory key, address receiver)
        internal
        returns (bytes memory)
    {
        bool zeroForOne = fromCurrency < key.key.currency1;
        Currency toCurrency = zeroForOne ? key.key.currency1 : key.key.currency0;

        uint160 sqrtPriceLimitX96 =
            zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        BalanceDelta delta = UNISWAP_V4_POOL_MANAGER.swap(
            key.key, IPoolManager.SwapParams(zeroForOne, -takeIn, sqrtPriceLimitX96), key.hookData
        );

        uint256 takeAmount = uint256(uint128((zeroForOne ? delta.amount1() : delta.amount0())));
        UNISWAP_V4_POOL_MANAGER.sync(fromCurrency);

        if (Currency.unwrap(fromCurrency) != address(0)) {
            safeTransfer(
                Currency.unwrap(fromCurrency),
                msg.sender, // PoolManager.
                uint256(takeIn)
            );
        }

        UNISWAP_V4_POOL_MANAGER.settle{value: address(this).balance}(fromCurrency);
        UNISWAP_V4_POOL_MANAGER.take(toCurrency, receiver, takeAmount);

        return abi.encode(delta);
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
