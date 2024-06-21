// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";

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

    /// @dev Initialize with Uniswap V4 pool manager.
    constructor(IPoolManager manager) payable {
        UNISWAP_V4_POOL_MANAGER = manager;
    }

    /// ===================== SWAP EXECUTION ===================== ///

    /// @dev Swap an exact input `amountSpecified` (-) for equivalent exchange against pool `key`.
    function swapSingle(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        public
        payable
    {
        UNISWAP_V4_POOL_MANAGER.unlock(abi.encode(msg.sender, key, params, hookData));
    }

    function unlockCallback(bytes calldata callBackData) public payable {
        if (msg.sender != address(UNISWAP_V4_POOL_MANAGER)) revert Unauthorized();

        // Decode and extract the swap instructions from the PoolManager callback data.
        (address swapper, PoolKey memory key, SwapParams memory params, bytes memory hookData) =
            abi.decode(callBackData, (address, PoolKey, SwapParams, bytes));

        bool exactIn = 0 > params.amountSpecified;

        // Sort the input and output currencies for the given direction (`zeroForOne`).
        (address fromCurrency, address toCurrency) =
            params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        // Apply directional price limit.
        params.sqrtPriceLimitX96 =
            params.zeroForOne ? MIN_SQRT_RATIO_PLUS_ONE : MAX_SQRT_RATIO_MINUS_ONE;

        // Call `swap()` on the PoolManager and memo the `delta` output.
        int256 delta = UNISWAP_V4_POOL_MANAGER.swap(key, params, hookData);

        // Call `sync()` on the PoolManager to update currency reserves.
        UNISWAP_V4_POOL_MANAGER.sync(fromCurrency);

        /// @dev The amount that can be taken or requires settlement if not `exactIn`.
        uint256 takeAmount =
            uint256(uint128(int128(params.zeroForOne ? _amount1(delta) : _amount0(delta))));
        console.log(takeAmount);

        // If not native token (ETH) as input, then pull `swapper` tokens to PoolManager.
        if (fromCurrency != address(0)) {
            safeTransferFrom(
                fromCurrency,
                swapper,
                msg.sender, // PoolManager.
                exactIn ? uint256(-params.amountSpecified) : takeAmount
            );
        }

        // Call `settle()` on PoolManager to update reserves (attach local value to account for ETH `fromCurrency`).
        UNISWAP_V4_POOL_MANAGER.settle{value: address(this).balance}(fromCurrency);

        // Call `take()` on the PoolManager and send `takeAmount` to `swapper` with switch case on `exactIn`.
        UNISWAP_V4_POOL_MANAGER.take(
            toCurrency, swapper, exactIn ? takeAmount : uint256(-params.amountSpecified)
        );
    }

    /// @dev Extract `amount0` from packed `balanceDelta` int256.
    function _amount0(int256 balanceDelta) internal pure returns (int128 amount0) {
        assembly {
            amount0 := sar(128, balanceDelta)
        }
    }

    /// @dev Extract `amount1` from packed `balanceDelta` int256.
    function _amount1(int256 balanceDelta) internal pure returns (int128 amount1) {
        assembly {
            amount1 := signextend(15, balanceDelta)
        }
    }
}

/// @dev Uniswap V4 pool key.
struct PoolKey {
    address currency0; // Syntax-simple.
    address currency1; // Syntax-simple.
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

/// @dev Uniswap V4 swap params.
struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

//// @dev Minimal Uniswap V4 pool manager interface with syntax simplicity.
interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (int256); // BalanceDelta (syntax-simple).
    function sync(address currency) external returns (uint256 balance);
    function settle(address token) external payable returns (uint256 paid);
    function take(address currency, address to, uint256 amount) external;
}

/// @dev Solady ERC20 token pull pattern that gracefully handles non-standard returns.
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
