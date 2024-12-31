// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockERC20} from "@solady/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "@v4/src/types/Currency.sol";

library MockCurrencyLibrary {

    function mint(Currency currency, address to, uint256 value) internal {
        MockERC20(address(Currency.unwrap(currency))).mint(to, value);
    }

    function burn(Currency currency, address from, uint256 value) internal {
        MockERC20(address(Currency.unwrap(currency))).burn(from, value);
    }
}