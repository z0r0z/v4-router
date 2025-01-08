// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {PathKey} from "../src/libraries/PathKey.sol";

import {V4SwapRouter} from "../src/V4SwapRouter.sol";

import {SwapRouterFixtures, Deployers, TestCurrencyBalances} from "./utils/SwapRouterFixtures.sol";
import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";

contract MultihopTest is SwapRouterFixtures {
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

        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));
        currencyC.maxApprove(address(router));
        currencyD.maxApprove(address(router));

        // TODO: deploy hooks
        // Deploy the hook to an address with the correct flags
        _deployCSMM();

        // Define and create pools with liquidity
        PoolKey[] memory _vanillaPoolKeys = _createPoolKeys(address(0));
        _copyArrayToStorage(_vanillaPoolKeys, vanillaPoolKeys);
        PoolKey[] memory _nativePoolKeys = _createNativePoolKeys(address(0));
        _copyArrayToStorage(_nativePoolKeys, nativePoolKeys);
        PoolKey[] memory _hookedPoolKeys = _createPoolKeys(address(Hooks.BEFORE_SWAP_FLAG));
        _copyArrayToStorage(_hookedPoolKeys, hookedPoolKeys);
        PoolKey[] memory _csmmPoolKeys = _createPoolKeys(address(csmm));
        _copyArrayToStorage(_csmmPoolKeys, csmmPoolKeys);

        PoolKey[] memory allPoolKeys =
            _concatPools(vanillaPoolKeys, nativePoolKeys, hookedPoolKeys, csmmPoolKeys);
        _initializePools(allPoolKeys);

        _addLiquidity(vanillaPoolKeys, 10_000e18);
        _addLiquidity(nativePoolKeys, 10_000e18);
        _addLiquidity(hookedPoolKeys, 10_000e18);
        _addLiquidityCSMM(csmmPoolKeys, 1_000e18);
    }

    function test_multi_exactInput() public {}
    function test_multi_exactInput_native() public {}
    function test_multi_exactInput_hookData() public {}

    function test_multi_exactInput_customCurve(address recipient) public {
        // Swap Path: A -(vanilla)-> B -(CSMM)-> C
        Currency startCurrency = currencyA;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyB,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: currencyC,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(csmm)),
            hookData: ZERO_BYTES
        });

        TestCurrencyBalances memory thisBefore = currencyBalances(address(this));
        TestCurrencyBalances memory recipientBefore = currencyBalances(recipient);

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.995e18;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, startCurrency, path, recipient, uint256(block.timestamp)
        );

        TestCurrencyBalances memory thisAfter = currencyBalances(address(this));
        TestCurrencyBalances memory recipientAfter = currencyBalances(recipient);

        // Check balances
        // test contract paid currencyA
        // recipient did not spend currencyA
        assertEq(thisBefore.currencyA - thisAfter.currencyA, amountIn);
        assertEq(recipientBefore.currencyA, recipientAfter.currencyA);

        // currencyB unspent
        assertEq(thisBefore.currencyB, thisAfter.currencyB);
        assertEq(recipientBefore.currencyB, recipientAfter.currencyB);

        // test contract did not receive currencyC
        // recipient received currencyC
        assertEq(thisBefore.currencyC, thisAfter.currencyC);
        assertApproxEqRel(recipientAfter.currencyC - recipientBefore.currencyC, amountIn, 0.005e18); // allow 50 bips error

        // verify slippage: recieved > amountOutMin
        assertGt((recipientAfter.currencyC - recipientBefore.currencyC), amountOutMin);
    }

    function test_multi_exactOutput() public {}
    function test_multi_exactOutput_native() public {}
    function test_multi_exactOutput_hookData() public {}
    function test_multi_exactOutput_customCurve() public {}
}
