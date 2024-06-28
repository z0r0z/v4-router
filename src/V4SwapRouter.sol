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

    /// @dev Swap an exact input (-) or output (+) `amountSpecified` via pool `key` with `hookData`.
    function swapSingle(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        bytes calldata hookData
    ) public payable returns (BalanceDelta) {
        return abi.decode(
            UNISWAP_V4_POOL_MANAGER.unlock(abi.encodePacked(false, abi.encode(msg.sender, key, params, hookData))),
            (BalanceDelta)
        );
    }

    /// @dev Multi-hop struct.
    struct CallbackData {
        PoolKey key;
        IPoolManager.SwapParams params;
        bytes hookData;
    }

    /// @dev Perform multi-hop swap.
    function swapMulti(CallbackData[] calldata swaps) public payable returns (BalanceDelta) {
        return abi.decode(
            UNISWAP_V4_POOL_MANAGER.unlock(abi.encodePacked(true, abi.encode(swaps))),
            (BalanceDelta)
        );
    }

    /// @dev Receive call from PoolManager and perform swap actions in sequence based on inputs.
    function unlockCallback(bytes calldata callBackData) public payable returns (bytes memory) {
        if (msg.sender != address(UNISWAP_V4_POOL_MANAGER)) revert Unauthorized();

        bool multi; // Flag in first byte.
        assembly ("memory-safe") {
            multi := byte(0, calldataload(0))
        }

        if (!multi) {
            return _singleSwap(callBackData);
        } else {
            return _multiSwap(callBackData);
        }
    }
    
    /// @dev Complete single swap exact-in/out.
    function _singleSwap(bytes calldata callBackData) internal returns (bytes memory) {
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

        // Apply the directional price limit if zero (or as specified if non-zero).
        if (params.sqrtPriceLimitX96 == 0) {
            params.sqrtPriceLimitX96 =
                params.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        }

        // Call `swap()` on the PoolManager and memo the `delta` output.
        BalanceDelta delta = UNISWAP_V4_POOL_MANAGER.swap(key, params, hookData);

        // The amount that can be taken or that requires settlement if not `exactIn`.
        uint256 takeAmount =
            uint256(uint128((params.zeroForOne && exactIn ? delta.amount1() : -delta.amount0())));

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
            toCurrency, swapper, exactIn ? takeAmount : uint256(params.amountSpecified)
        );

        return abi.encode(delta); // Return the swap delta.
    }

    /// @dev Complete multi-hop swap exact-in/out in for loop sequence.
    function _multiSwap(bytes calldata callBackData) internal returns (bytes memory) {
        CallbackData[] memory swaps = abi.decode(callBackData[1:], (CallbackData[]));
        BalanceDelta totalDelta;

        for (uint256 i = 0; i < swaps.length; i++) {
            PoolKey memory key = swaps[i].key;
            IPoolManager.SwapParams memory params = swaps[i].params;
            bytes memory hookData = swaps[i].hookData;

            // Adjust parameters for each hop
            if (params.sqrtPriceLimitX96 == 0) {
                params.sqrtPriceLimitX96 =
                    params.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
            }

            BalanceDelta delta = UNISWAP_V4_POOL_MANAGER.swap(key, params, hookData);
            totalDelta = totalDelta + delta;

            // Synchronize and settle as needed
            UNISWAP_V4_POOL_MANAGER.sync(params.zeroForOne ? key.currency0 : key.currency1);
            UNISWAP_V4_POOL_MANAGER.settle{value: address(this).balance}(
                params.zeroForOne ? key.currency0 : key.currency1
            );
        }

        // Final settlement and take
        CallbackData memory lastSwap = swaps[swaps.length - 1];
        UNISWAP_V4_POOL_MANAGER.take(
            lastSwap.params.zeroForOne ? lastSwap.key.currency1 : lastSwap.key.currency0,
            msg.sender,
            uint256(lastSwap.params.amountSpecified)
        );

        return abi.encode(totalDelta); // Return the total swap delta.
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
