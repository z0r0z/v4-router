// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @title V4 Swap Router
/// @author z0r0z.eth
/// @dev A hyper-optimized single-swap router for UniswapV4.
contract V4SwapRouter {
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

    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        public
        payable
    {
        UNISWAP_V4_POOL_MANAGER.unlock(abi.encode(msg.sender, key, params, hookData));
    }

    /// @dev note: Initially testing exact-in single swap.
    /// Elaboration to exact-out and multi-hop should be not difficult,
    /// if this overall format holds up. Please comment on v4 niceties so far.
    function unlockCallback(bytes calldata callBackData) public payable {
        if (msg.sender != address(UNISWAP_V4_POOL_MANAGER)) revert Unauthorized();
        (address swapper, PoolKey memory key, SwapParams memory params, bytes memory hookData) =
            abi.decode(callBackData, (address, PoolKey, SwapParams, bytes));
        (address fromCurrency, address toCurrency) =
            params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);
        params.sqrtPriceLimitX96 =
            params.zeroForOne ? MIN_SQRT_RATIO_PLUS_ONE : MAX_SQRT_RATIO_MINUS_ONE;
        int256 delta = UNISWAP_V4_POOL_MANAGER.swap(key, params, hookData);
        if (fromCurrency != address(0)) {
            UNISWAP_V4_POOL_MANAGER.sync(fromCurrency);
            safeTransferFrom(
                fromCurrency,
                swapper,
                msg.sender, // PoolManager.
                uint256(params.amountSpecified)
            );
        }
        UNISWAP_V4_POOL_MANAGER.settle{value: msg.value}(fromCurrency);
        UNISWAP_V4_POOL_MANAGER.take(
            toCurrency,
            swapper,
            params.zeroForOne ? uint128(-1 * amount1(delta)) : uint128(-1 * amount0(delta))
        );
    }

    function amount0(int256 balanceDelta) internal pure returns (int128 _amount0) {
        assembly ("memory-safe") {
            _amount0 := sar(128, balanceDelta)
        }
    }

    function amount1(int256 balanceDelta) internal pure returns (int128 _amount1) {
        assembly ("memory-safe") {
            _amount1 := signextend(15, balanceDelta)
        }
    }
}

// Appendix ~~

/// @dev Pool auth.
error Unauthorized();

/// @dev Simple Uniswap V4 pool key.
struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

/// @dev Simple Uniswap V4 swap params.
struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

//// @dev Minimal Uniswap V4 pool manager interface.
interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (int256); // BalanceDelta.
    function sync(address currency) external returns (uint256 balance);
    function settle(address token) external payable returns (uint256 paid);
    function take(address currency, address to, uint256 amount) external;
}

/// @dev Sourced from the pristine machinations of the Solady solidity library.
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
