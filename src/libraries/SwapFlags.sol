// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/// @title SwapFlags Library
/// @notice Library for managing swap configuration flags using bitwise operations
/// @dev Provides constants and utilities for working with swap flags encoded as uint8
library SwapFlags {
    /// @notice Flag indicating a single pool swap vs multi-hop swap
    /// @dev Bit position 0 (0b00001)
    uint8 constant SINGLE_SWAP = 1 << 0;

    /// @notice Flag indicating exact output swap vs exact input swap
    /// @dev Bit position 1 (0b00010)
    uint8 constant EXACT_OUTPUT = 1 << 1;

    /// @notice Flag indicating input token is ERC6909
    /// @dev Bit position 2 (0b00100)
    uint8 constant INPUT_6909 = 1 << 2;

    /// @notice Flag indicating output token is ERC6909
    /// @dev Bit position 3 (0b01000)
    uint8 constant OUTPUT_6909 = 1 << 3;

    /// @notice Flag indicating swap uses Permit2 for token approvals
    /// @dev Bit position 4 (0b10000)
    uint8 constant PERMIT2 = 1 << 4;

    /// @notice Unpacks individual boolean flags from packed uint8
    /// @param flags The packed uint8 containing all flag bits
    /// @return singleSwap True if single pool swap
    /// @return exactOutput True if exact output swap
    /// @return input6909 True if input token is ERC6909
    /// @return output6909 True if output token is ERC6909
    /// @return permit2 True if using Permit2
    function unpackFlags(uint8 flags)
        internal
        pure
        returns (bool singleSwap, bool exactOutput, bool input6909, bool output6909, bool permit2)
    {
        singleSwap = flags & SINGLE_SWAP != 0;
        exactOutput = flags & EXACT_OUTPUT != 0;
        input6909 = flags & INPUT_6909 != 0;
        output6909 = flags & OUTPUT_6909 != 0;
        permit2 = flags & PERMIT2 != 0;
    }
}
