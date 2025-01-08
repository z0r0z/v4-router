// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";

import {V4SwapRouter} from "../src/V4SwapRouter.sol";

import {SwapRouterFixtures, Deployers} from "./utils/SwapRouterFixtures.sol";
import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";

contract RouterGasTest is SwapRouterFixtures {
    using MockCurrencyLibrary for Currency;

    V4SwapRouter router;

    PoolKey[] vanillaPoolKeys;
    PoolKey[] nativePoolKeys;
    PoolKey[] hookedPoolKeys;
    PoolKey[] csmmPoolKeys;

    function setUp() public payable {
        // Deploy v4 contracts
        Deployers.deployFreshManagerAndRouters();
        router = new V4SwapRouter(manager);

        // Create currencies
        (currencyA, currencyB, currencyC, currencyD) = _createSortedCurrencies();

        currencyA.mint(address(this), 10_000e18);
        currencyB.mint(address(this), 10_000e18);
        currencyC.mint(address(this), 10_000e18);
        currencyD.mint(address(this), 10_000e18);

        currencyA.maxApprove(address(modifyLiquidityRouter));
        currencyB.maxApprove(address(modifyLiquidityRouter));
        currencyC.maxApprove(address(modifyLiquidityRouter));
        currencyD.maxApprove(address(modifyLiquidityRouter));

        // TODO: deploy hooks

        // Define and create pools with liquidity
        PoolKey[] memory _vanillaPoolKeys = _createPoolKeys(address(0));
        _copyArrayToStorage(_vanillaPoolKeys, vanillaPoolKeys);
        PoolKey[] memory _nativePoolKeys = _createNativePoolKeys(address(0));
        _copyArrayToStorage(_nativePoolKeys, nativePoolKeys);
        PoolKey[] memory _hookedPoolKeys = _createPoolKeys(address(Hooks.BEFORE_SWAP_FLAG));
        _copyArrayToStorage(_hookedPoolKeys, hookedPoolKeys);
        PoolKey[] memory _csmmPoolKeys = _createPoolKeys(address(Hooks.AFTER_SWAP_FLAG));
        _copyArrayToStorage(_csmmPoolKeys, csmmPoolKeys);

        PoolKey[] memory allPoolKeys =
            _concatPools(vanillaPoolKeys, nativePoolKeys, hookedPoolKeys, csmmPoolKeys);
        _initializePools(allPoolKeys);
        _addLiquidity(allPoolKeys, 10_000e18);
    }

    function test_gas_single_exactOutput() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));

        router.swapTokensForExactTokens(
            0.1 ether, // exact amount out
            0.15 ether, // maximum amount in
            true, // zeroForOne
            vanillaPoolKeys[0], // standard pool without hooks
            "", // no hook data
            address(this), // recipient
            block.timestamp + 1
        );
    }

    // Skip native token test as not implemented yet
    function test_gas_single_exactOutput_native() public {}

    /*function test_gas_single_exactOutput_hooked() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));

        router.swapTokensForExactTokens(
            0.1 ether, // exact amount out
            0.15 ether, // maximum amount in
            true, // zeroForOne
            hookedPoolKeys[0], // pool with hooks
            "", // hook data (empty for now)
            address(this), // recipient
            block.timestamp + 1
        );
    }

    function test_gas_single_exactOutput_customCurve() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));

        router.swapTokensForExactTokens(
            0.1 ether, // exact amount out
            0.15 ether, // maximum amount in
            true, // zeroForOne
            csmmPoolKeys[0], // pool with custom curve
            "", // no hook data
            address(this), // recipient
            block.timestamp + 1
        );
    }*/

    function test_gas_multi_exactOutput() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));

        // Second swap (B->C)
        router.swapTokensForExactTokens(
            0.1 ether, // exact amount of C wanted
            0.15 ether, // maximum B to spend
            true,
            vanillaPoolKeys[1],
            "",
            address(this),
            block.timestamp + 1
        );

        // First swap (A->B)
        router.swapTokensForExactTokens(
            0.15 ether, // exact amount of B needed for second swap
            0.2 ether, // maximum A to spend
            true,
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1
        );
    }

    // Skip native token test as not implemented yet
    function test_gas_multi_exactOutput_native() public {}

    /*function test_gas_multi_exactOutput_hooked() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));

        // Second swap (B->C)
        router.swapTokensForExactTokens(
            0.1 ether, // exact amount of C wanted
            0.15 ether, // maximum B to spend
            true,
            hookedPoolKeys[1],
            "", // hook data (empty for now)
            address(this),
            block.timestamp + 1
        );

        // First swap (A->B)
        router.swapTokensForExactTokens(
            0.15 ether, // exact amount of B needed for second swap
            0.2 ether, // maximum A to spend
            true,
            hookedPoolKeys[0],
            "", // hook data (empty for now)
            address(this),
            block.timestamp + 1
        );
    }

    function test_gas_multi_exactOutput_customCurve() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));

        // Second swap (B->C)
        router.swapTokensForExactTokens(
            0.1 ether, // exact amount of C wanted
            0.15 ether, // maximum B to spend
            true,
            csmmPoolKeys[1],
            "",
            address(this),
            block.timestamp + 1
        );

        // First swap (A->B)
        router.swapTokensForExactTokens(
            0.15 ether, // exact amount of B needed for second swap
            0.2 ether, // maximum A to spend
            true,
            csmmPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1
        );
    }*/

    //function test_gas_multi_exactInput() public {}
    //function test_gas_multi_exactInput_native() public {}
    //function test_gas_multi_exactInput_hooked() public {}
    //function test_gas_multi_exactInput_customCurve() public {}

    //function test_gas_multi_exactOutput() public {}
    //function test_gas_multi_exactOutput_native() public {}
    //function test_gas_multi_exactOutput_hooked() public {}
    //function test_gas_multi_exactOutput_customCurve() public {}

    //function test_gas_single_exactInput() public {}
    //function test_gas_single_exactInput_native() public {}
    //function test_gas_single_exactInput_hooked() public {}
    //function test_gas_single_exactInput_customCurve() public {}

    //function test_gas_single_exactOutput() public {}
    //function test_gas_single_exactOutput_native() public {}
    //function test_gas_single_exactOutput_hooked() public {}
    //function test_gas_single_exactOutput_customCurve() public {}
}
