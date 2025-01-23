// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {PathKey} from "../src/libraries/PathKey.sol";
import {IERC20Minimal} from "@v4/src/interfaces/external/IERC20Minimal.sol";

import {Counter} from "@v4-template/src/Counter.sol";
import {BaseHook} from "@v4-periphery/src/base/hooks/BaseHook.sol";

import {V4SwapRouter} from "../src/V4SwapRouter.sol";

import {SwapRouterFixtures, Deployers, TestCurrencyBalances} from "./utils/SwapRouterFixtures.sol";
import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";
import {HookData} from "./utils/hooks/HookData.sol";

contract MultihopTest is SwapRouterFixtures {
    using MockCurrencyLibrary for Currency;

    V4SwapRouter router;
    Counter hook;

    PoolKey[] vanillaPoolKeys;
    PoolKey[] nativePoolKeys;
    PoolKey[] hookedPoolKeys;
    PoolKey[] csmmPoolKeys;

    // Test contract inherits `receive` function through SwapRouterFixtures' Deployers contract

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

        // Deploy the hook to an address with the correct flags
        _deployCSMM();
        _deployHookWithData();

        // Define and create all pools with their respective hooks
        PoolKey[] memory _vanillaPoolKeys = _createPoolKeys(address(0));
        _copyArrayToStorage(_vanillaPoolKeys, vanillaPoolKeys);

        PoolKey[] memory _nativePoolKeys = _createNativePoolKeys(address(0));
        _copyArrayToStorage(_nativePoolKeys, nativePoolKeys);

        PoolKey[] memory _hookedPoolKeys = _createPoolKeys(address(hookWithData));
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

    function test_multi_exactInput(address recipient) public {
        vm.assume(recipient != address(manager));
        TestCurrencyBalances memory thisBefore = currencyBalances(address(this));
        TestCurrencyBalances memory recipientBefore = currencyBalances(recipient);

        // Swap Path: A --> B --> C
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
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
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
        assertApproxEqRel(recipientAfter.currencyC - recipientBefore.currencyC, amountIn, 0.01e18); // allow 1% error

        // verify slippage: recieved > amountOutMin
        assertGt((recipientAfter.currencyC - recipientBefore.currencyC), amountOutMin);
    }

    function test_multi_exactInput_nativeInput(address recipient) public {
        vm.assume(recipient != address(manager));
        TestCurrencyBalances memory thisBefore = currencyBalances(address(this));
        TestCurrencyBalances memory recipientBefore = currencyBalances(recipient);

        // Swap Path: ETH --> C --> D
        Currency startCurrency = native;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyC,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        router.swapExactTokensForTokens{value: amountIn}(
            amountIn, amountOutMin, startCurrency, path, recipient, uint256(block.timestamp)
        );

        TestCurrencyBalances memory thisAfter = currencyBalances(address(this));
        TestCurrencyBalances memory recipientAfter = currencyBalances(recipient);

        // Check balances
        // test contract paid native
        // recipient did not spend native
        assertEq(thisBefore.native - thisAfter.native, amountIn);
        assertEq(recipientBefore.native, recipientAfter.native);

        // intermediate currencyC unspent
        assertEq(thisBefore.currencyC, thisAfter.currencyC);
        assertEq(recipientBefore.currencyC, recipientAfter.currencyC);

        // test contract did not receive currencyD
        // recipient received currencyD
        assertEq(thisBefore.currencyD, thisAfter.currencyD);
        assertApproxEqRel(recipientAfter.currencyD - recipientBefore.currencyD, amountIn, 0.01e18); // allow 1% error

        // verify slippage: recieved > amountOutMin
        assertGt((recipientAfter.currencyD - recipientBefore.currencyD), amountOutMin);
    }

    function test_multi_exactInput_nativeOutput() public {
        // do not fuzz recipient since not all contracts have receive functions
        address recipient = address(0xABC123);
        TestCurrencyBalances memory thisBefore = currencyBalances(address(this));
        TestCurrencyBalances memory recipientBefore = currencyBalances(recipient);

        // Swap Path: B --> C --> ETH
        Currency startCurrency = currencyB;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyC,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: native,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, startCurrency, path, recipient, uint256(block.timestamp)
        );

        TestCurrencyBalances memory thisAfter = currencyBalances(address(this));
        TestCurrencyBalances memory recipientAfter = currencyBalances(recipient);

        // Check balances
        // test contract paid currencyB
        // recipient did not spend currencyB
        assertEq(thisBefore.currencyB - thisAfter.currencyB, amountIn);
        assertEq(recipientBefore.currencyB, recipientAfter.currencyB);

        // intermediate currencyC unspent
        assertEq(thisBefore.currencyC, thisAfter.currencyC);
        assertEq(recipientBefore.currencyC, recipientAfter.currencyC);

        // test contract did not receive native
        // recipient received native
        assertEq(thisBefore.native, thisAfter.native);
        assertApproxEqRel(recipientAfter.native - recipientBefore.native, amountIn, 0.01e18); // allow 1% error

        // verify slippage: recieved > amountOutMin
        assertGt((recipientAfter.native - recipientBefore.native), amountOutMin);
    }

    function test_multi_exactInput_nativeIntermediate(address recipient) public {
        vm.assume(recipient != address(manager));
        TestCurrencyBalances memory thisBefore = currencyBalances(address(this));
        TestCurrencyBalances memory recipientBefore = currencyBalances(recipient);

        // Swap Path: A --> ETH --> B
        Currency startCurrency = currencyA;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: native,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: currencyB,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
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

        // intermediate native unspent
        assertEq(thisBefore.native, thisAfter.native);
        assertEq(recipientBefore.native, recipientAfter.native);

        // test contract did not receive currencyB
        // recipient received currencyB
        assertEq(thisBefore.currencyB, thisAfter.currencyB);
        assertApproxEqRel(recipientAfter.currencyB - recipientBefore.currencyB, amountIn, 0.01e18); // allow 1% error

        // verify slippage: recieved > amountOutMin
        assertGt((recipientAfter.currencyB - recipientBefore.currencyB), amountOutMin);
    }

    function test_multi_exactInput_hookData(address recipient) public {
        vm.assume(recipient != address(manager));
        // data to be passed to the hook
        uint256 num0 = 111;
        uint256 num1 = 222;

        // Swap Path: C -(hookWithData)-> D -(hookWithData)-> A
        Currency startCurrency = currencyC;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hookWithData)),
            hookData: abi.encode(num0) // C -> D emits num0
        });
        path[1] = PathKey({
            intermediateCurrency: currencyA,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hookWithData)),
            hookData: abi.encode(num1) // D -> A emits num1
        });

        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.BeforeSwapData(num0);
        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.AfterSwapData(num0);

        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.BeforeSwapData(num1);
        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.AfterSwapData(num1);

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, startCurrency, path, recipient, uint256(block.timestamp)
        );
    }

    function test_multi_exactInput_customCurve(address recipient) public {
        vm.assume(recipient != address(manager));
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

    function test_multi_exactOutput(address recipient) public {
        vm.assume(recipient != address(manager));
        TestCurrencyBalances memory thisBefore = currencyBalances(address(this));
        TestCurrencyBalances memory recipientBefore = currencyBalances(recipient);

        // Swap Path: B --> A --> D
        Currency startCurrency = currencyB;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyA,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        router.swapTokensForExactTokens(
            amountOut, amountInMax, startCurrency, path, recipient, uint256(block.timestamp)
        );

        TestCurrencyBalances memory thisAfter = currencyBalances(address(this));
        TestCurrencyBalances memory recipientAfter = currencyBalances(recipient);

        // Check balances
        // test contract did not receive currencyD
        // recipient received currencyD
        assertEq(thisBefore.currencyD, thisAfter.currencyD);
        assertEq(recipientAfter.currencyD - recipientBefore.currencyD, amountOut);

        // intermediate currencyA unspent
        assertEq(thisBefore.currencyA, thisAfter.currencyA);
        assertEq(recipientBefore.currencyA, recipientAfter.currencyA);

        // test contract paid currencyB
        // recipient did not spend currencyB
        assertApproxEqRel(thisBefore.currencyB - thisAfter.currencyB, amountOut, 0.01e18); // allow 1% error
        assertEq(recipientBefore.currencyB, recipientAfter.currencyB);

        // verify slippage: amountIn < amountInMax
        assertLt((thisBefore.currencyB - thisAfter.currencyB), amountInMax);
    }

    function test_multi_exactOutput_nativeInput(address recipient) public {
        vm.assume(recipient != address(manager));
        TestCurrencyBalances memory thisBefore = currencyBalances(address(this));
        TestCurrencyBalances memory recipientBefore = currencyBalances(recipient);

        // Swap Path: native --> A --> D
        Currency startCurrency = native;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyA,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        router.swapTokensForExactTokens{value: amountInMax}(
            amountOut, amountInMax, startCurrency, path, recipient, uint256(block.timestamp)
        );

        TestCurrencyBalances memory thisAfter = currencyBalances(address(this));
        TestCurrencyBalances memory recipientAfter = currencyBalances(recipient);

        // Check balances
        // test contract did not receive currencyD
        // recipient received currencyD
        assertEq(thisBefore.currencyD, thisAfter.currencyD);
        assertEq(recipientAfter.currencyD - recipientBefore.currencyD, amountOut);

        // intermediate currencyA unspent
        assertEq(thisBefore.currencyA, thisAfter.currencyA);
        assertEq(recipientBefore.currencyA, recipientAfter.currencyA);

        // test contract paid native
        // recipient did not spend native
        assertApproxEqRel(thisBefore.native - thisAfter.native, amountOut, 0.01e18); // allow 1% error
        assertEq(recipientBefore.native, recipientAfter.native);

        // verify slippage: amountIn < amountInMax
        assertLt((thisBefore.native - thisAfter.native), amountInMax);
    }

    function test_multi_exactOutput_hookData(address recipient) public {
        vm.assume(recipient != address(manager));
        TestCurrencyBalances memory thisBefore = currencyBalances(address(this));
        TestCurrencyBalances memory recipientBefore = currencyBalances(recipient);

        // data to be passed to the hook
        uint256 num0 = 333;
        uint256 num1 = 444;

        // Swap Path: A -(hookWithData)-> B -(hookWithData)-> C
        Currency startCurrency = currencyA;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyB,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hookWithData)),
            hookData: abi.encode(num0) // A - B emits num0
        });
        path[1] = PathKey({
            intermediateCurrency: currencyC,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hookWithData)),
            hookData: abi.encode(num1) // B -> C emits num1
        });

        // emit B -> C (num1) first, since swaps are happening in reverse order of `path`
        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.BeforeSwapData(num1);
        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.AfterSwapData(num1);

        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.BeforeSwapData(num0);
        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.AfterSwapData(num0);

        uint256 amountOut = 1e18; // currencyC
        uint256 amountInMax = 1.01e18; // currencyA
        router.swapTokensForExactTokens{value: amountInMax}(
            amountOut, amountInMax, startCurrency, path, recipient, uint256(block.timestamp)
        );

        TestCurrencyBalances memory thisAfter = currencyBalances(address(this));
        TestCurrencyBalances memory recipientAfter = currencyBalances(recipient);

        // Check balances
        // test contract did not receive currencyC
        // recipient received currencyC
        assertEq(thisBefore.currencyC, thisAfter.currencyC);
        assertEq(recipientAfter.currencyC - recipientBefore.currencyC, amountOut);

        // intermediate currencyB unspent
        assertEq(thisBefore.currencyB, thisAfter.currencyB);
        assertEq(recipientBefore.currencyB, recipientAfter.currencyB);

        // test contract paid currencyA
        // recipient did not spend currencyA
        assertApproxEqRel(thisBefore.currencyA - thisAfter.currencyA, amountOut, 0.01e18); // allow 1% error
        assertEq(recipientBefore.currencyA, recipientAfter.currencyA);

        // verify slippage: amountIn < amountInMax
        assertLt((thisBefore.currencyA - thisAfter.currencyA), amountInMax);
    }

    function test_multi_exactOutput_customCurve() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));

        router.swapTokensForExactTokens(
            0.1 ether, 0.15 ether, true, csmmPoolKeys[1], "", address(this), block.timestamp + 1
        );

        router.swapTokensForExactTokens(
            0.15 ether, 0.2 ether, true, csmmPoolKeys[0], "", address(this), block.timestamp + 1
        );
    }
}
