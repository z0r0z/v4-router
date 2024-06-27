// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {IPoolManager} from "@v4/src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@v4/src/types/BalanceDelta.sol";

/// @dev Uniswap V4 swap params.
struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

/// @title Uniswap V4 Swap Router
/// @notice Router for stateless execution of swaps against Uniswap V4.
contract V4SwapRouter {
    /// ======================= CUSTOM ERRORS ======================= ///

    /// @dev Pool auth.
    error Unauthorized();

    /// ========================= CONSTANTS ========================= ///

    /// @dev The minimum value that can be returned from `getSqrtRatioAtTick` (plus one).
    uint160 internal constant MIN_SQRT_RATIO_PLUS_ONE = 4295128740;

    /// @dev The maximum value that can be returned from `getSqrtRatioAtTick` (minus one).
    uint160 internal constant MAX_SQRT_RATIO_MINUS_ONE =
        1461446703485210103287273052203988822378723970341;

    /// @dev The address of the Uniswap V4 pool manager.
    IPoolManager internal immutable UNISWAP_V4_POOL_MANAGER;

    /// @dev Create with Uniswap V4 pool manager.
    constructor(IPoolManager manager) payable {
        UNISWAP_V4_POOL_MANAGER = manager;
    }

    /// ===================== SWAP EXECUTION ===================== ///

    /// @dev Swap an exact input (-) or output (+) `amountSpecified` via pool `key` with `hookData`.
    function swapSingle(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        bytes calldata hookData
    ) public payable {
        UNISWAP_V4_POOL_MANAGER.unlock(abi.encode(msg.sender, key, params, hookData));
    }

    function unlockCallback(bytes calldata callBackData) public payable returns (bytes memory) {
        if (msg.sender != address(UNISWAP_V4_POOL_MANAGER)) revert Unauthorized();
        (
            address swapper,
            PoolKey memory key,
            IPoolManager.SwapParams memory params,
            bytes memory hookData
        ) = abi.decode(callBackData, (address, PoolKey, IPoolManager.SwapParams, bytes));

        // Memo if exact-in or exact-out based on `amountSpecified` flag (+/-).
        bool exactIn = params.amountSpecified < 0;

        // Sort the input and output currencies for the given direction (`zeroForOne`).
        (Currency fromCurrency, Currency toCurrency) =
            params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        // Apply the directional price limit.
        params.sqrtPriceLimitX96 =
            params.zeroForOne ? MIN_SQRT_RATIO_PLUS_ONE : MAX_SQRT_RATIO_MINUS_ONE;

        // Call `swap()` on the PoolManager and memo the `delta` output.
        BalanceDelta delta = UNISWAP_V4_POOL_MANAGER.swap(key, params, hookData);

        // The amount that can be taken or that requires settlement if not `exactIn`.
        uint256 takeAmount =
            uint256(uint128((params.zeroForOne ? delta.amount1() : delta.amount0())));

        // Call `sync()` on the PoolManager to update currency reserves.
        UNISWAP_V4_POOL_MANAGER.sync(fromCurrency);

        // If not native token (ETH) as input, then pull `swapper` currency to PoolManager.
        if (Currency.unwrap(fromCurrency) != address(0)) {
            safeTransferFrom(
                Currency.unwrap(fromCurrency),
                swapper,
                msg.sender, // PoolManager.
                exactIn ? uint256(-params.amountSpecified) : takeAmount
            );
        }

        // Call `settle()` on PoolManager to update reserves (attach local value to account for ETH `fromCurrency`).
        UNISWAP_V4_POOL_MANAGER.settle{value: address(this).balance}(fromCurrency);

        // Call `take()` on the PoolManager with `takeAmount` sent to `swapper` (with switch case on `exactIn`).
        UNISWAP_V4_POOL_MANAGER.take(
            toCurrency, swapper, exactIn ? takeAmount : uint256(-params.amountSpecified)
        );

        return ""; // End callback with empty output to follow interface.
    }
}

/// @dev Solady ERC20 token pull pattern to gracefully handles non-standard return.
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
