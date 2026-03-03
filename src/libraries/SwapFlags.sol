// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/// @title SwapFlags Library
/// @notice Library for managing swap configuration flags using bitwise operations
/// @dev Provides constants and utilities for working with swap flags encoded as uint8
library SwapFlags {
    /// @notice Flag indicating a single pool swap vs multi-hop swap
    /// @dev Bit position 0 (0b01)
    uint8 constant SINGLE_SWAP = 1 << 0;

    /// @notice Flag indicating exact output swap vs exact input swap
    /// @dev Bit position 1 (0b10)
    uint8 constant EXACT_OUTPUT = 1 << 1;

    /// @notice Unpacks individual boolean flags from packed uint8
    /// @param flags The packed uint8 containing all flag bits
    /// @return singleSwap True if single pool swap
    /// @return exactOutput True if exact output swap
    function unpackFlags(uint8 flags) internal pure returns (bool singleSwap, bool exactOutput) {
        singleSwap = flags & SINGLE_SWAP != 0;
        exactOutput = flags & EXACT_OUTPUT != 0;
    }
}
