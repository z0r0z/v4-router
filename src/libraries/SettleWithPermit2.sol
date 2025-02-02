// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Currency} from "@v4/src/types/Currency.sol";
import {IPoolManager} from "@v4/src/interfaces/IPoolManager.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

/// @title SettleWithPermit2 Library
/// @notice Helper library for settling Uniswap V4 trades using Permit2 signatures
library SettleWithPermit2 {
    /// @notice Settles a trade using Permit2 for ERC20 tokens or direct transfer for ETH
    /// @param currency The currency being settled
    /// @param manager The Uniswap V4 pool manager contract
    /// @param permit2 The Permit2 contract instance
    /// @param payer The address paying for the trade
    /// @param amount The amount of currency to settle
    /// @param permit The Permit2 permission data for the transfer
    /// @param signature The signature authorizing the Permit2 transfer
    function settleWithPermit2(
        Currency currency,
        IPoolManager manager,
        ISignatureTransfer permit2,
        address payer,
        uint256 amount,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory signature
    ) internal {
        if (currency.isAddressZero()) {
            manager.settle{value: amount}();
        } else {
            manager.sync(currency);
            permit2.permitTransferFrom(
                permit,
                ISignatureTransfer.SignatureTransferDetails({
                    to: address(manager),
                    requestedAmount: amount
                }),
                payer,
                signature
            );
            manager.settle();
        }
    }
}
