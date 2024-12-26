// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";

struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
    bytes hookData;
}

using PathKeyLibrary for PathKey global;

/// @title PathKey Library
/// @notice Memory-oriented version of v4-periphery/src/libraries/PathKeyLibrary.sol
/// @dev Handles PathKey operations in memory rather than calldata for router operations
library PathKeyLibrary {
    /// @notice Decoder for converting PathKey from calldata to memory
    /// @param path The PathKey array in calldata to decode
    /// @return decodedPath The PathKey array in memory
    function decodePath(PathKey[] calldata path)
        internal
        pure
        returns (PathKey[] memory decodedPath)
    {
        decodedPath = new PathKey[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            decodedPath[i] = decodePathKey(path[i]);
        }
    }

    /// @notice Decoder for converting a single PathKey from calldata to memory
    /// @param key The PathKey in calldata to decode
    /// @return decoded The PathKey in memory
    function decodePathKey(PathKey calldata key) internal pure returns (PathKey memory decoded) {
        decoded.intermediateCurrency = key.intermediateCurrency;
        decoded.fee = key.fee;
        decoded.tickSpacing = key.tickSpacing;
        decoded.hooks = key.hooks;
        decoded.hookData = key.hookData;
    }

    /// @notice Get the pool and swap direction for a given PathKey
    /// @param params the given PathKey
    /// @param currencyIn the input currency
    /// @return poolKey the pool key of the swap
    /// @return zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    function getPoolAndSwapDirection(PathKey memory params, Currency currencyIn)
        internal
        pure
        returns (PoolKey memory poolKey, bool zeroForOne)
    {
        Currency currencyOut = params.intermediateCurrency;
        (Currency currency0, Currency currency1) =
            currencyIn < currencyOut ? (currencyIn, currencyOut) : (currencyOut, currencyIn);

        zeroForOne = currencyIn == currency0;
        poolKey = PoolKey(currency0, currency1, params.fee, params.tickSpacing, params.hooks);
    }
}
