// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Currency} from "@v4/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPoolManager} from "@v4/src/interfaces/IPoolManager.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

import "forge-std/console2.sol";

/// TODO: natspec
library SettleWithPermit2 {
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
            console2.log("PERMIT TRANSFER FROM");
            permit2.permitTransferFrom(
                permit,
                ISignatureTransfer.SignatureTransferDetails({
                    to: address(manager),
                    requestedAmount: amount
                }),
                payer,
                signature
            );
            console2.log("SETTLE");
            manager.settle();
        }
    }
}
