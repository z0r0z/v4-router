// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {PathKey} from "../src/libraries/PathKey.sol";
import {IERC20Minimal} from "@v4/src/interfaces/external/IERC20Minimal.sol";

import {Counter} from "@v4-template/src/Counter.sol";
import {BaseHook} from "@v4-periphery/src/utils/BaseHook.sol";

import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";

import {ISignatureTransfer, UniswapV4Router04} from "../src/UniswapV4Router04.sol";

import {
    SwapRouterFixtures,
    Deployers,
    TestCurrencyBalances,
    InputOutputBalances
} from "./utils/SwapRouterFixtures.sol";
import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";
import {HookData} from "./utils/hooks/HookData.sol";
import {HookMsgSender} from "./utils/hooks/HookMsgSender.sol";

contract SinglehopTest is SwapRouterFixtures {
    using MockCurrencyLibrary for Currency;

    UniswapV4Router04 router;

    Counter hook;

    PoolKey[] vanillaPoolKeys;
    PoolKey[] nativePoolKeys;
    PoolKey[] hookedPoolKeys;
    PoolKey[] csmmPoolKeys;
    PoolKey[] hookMsgSenderPoolKeys;

    // Test contract inherits `receive` function through SwapRouterFixtures' Deployers contract

    function setUp() public payable {
        // Deploy v4 contracts
        Deployers.deployFreshManagerAndRouters();
        DeployPermit2.deployPermit2();
        router = new UniswapV4Router04(manager, permit2);

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
        _deployHookMsgSender();

        // Define and create all pools with their respective hooks
        PoolKey[] memory _vanillaPoolKeys = _createPoolKeys(address(0));
        _copyArrayToStorage(_vanillaPoolKeys, vanillaPoolKeys);

        PoolKey[] memory _nativePoolKeys = _createNativePoolKeys(address(0));
        _copyArrayToStorage(_nativePoolKeys, nativePoolKeys);

        PoolKey[] memory _hookedPoolKeys = _createPoolKeys(address(hookWithData));
        _copyArrayToStorage(_hookedPoolKeys, hookedPoolKeys);
        PoolKey[] memory _csmmPoolKeys = _createPoolKeys(address(csmm));
        _copyArrayToStorage(_csmmPoolKeys, csmmPoolKeys);
        PoolKey[] memory _hookMsgSenderPoolKeys = _createPoolKeys(address(hookMsgSender));
        _copyArrayToStorage(_hookMsgSenderPoolKeys, hookMsgSenderPoolKeys);

        PoolKey[] memory allPoolKeys =
            _concatPools(vanillaPoolKeys, nativePoolKeys, hookedPoolKeys, csmmPoolKeys);
        _initializePools(allPoolKeys);
        _initializePools(hookMsgSenderPoolKeys);

        _addLiquidity(vanillaPoolKeys, 10_000e18);
        _addLiquidity(nativePoolKeys, 10_000e18);
        _addLiquidity(hookedPoolKeys, 10_000e18);
        _addLiquidity(hookMsgSenderPoolKeys, 10_000e18);
        _addLiquidityCSMM(csmmPoolKeys, 1_000e18);
    }

    function test_single_exactInput(address recipient, bool zeroForOne, uint256 seed) public {
        vm.assume(recipient != address(manager) && recipient != address(this));
        // randomly select a pool
        PoolKey memory poolKey = vanillaPoolKeys[seed % vanillaPoolKeys.length];

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            zeroForOne,
            poolKey,
            ZERO_BYTES,
            recipient,
            uint256(block.timestamp)
        );

        InputOutputBalances memory thisAfter =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract paid input currency
        // recipient did not spend input currency
        assertEq(thisBefore.inputCurrency - thisAfter.inputCurrency, amountIn);
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertApproxEqRel(
            recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountIn, 0.01e18
        ); // allow 1% error

        // verify slippage: recieved > amountOutMin
        assertGt((recipientAfter.outputCurrency - recipientBefore.outputCurrency), amountOutMin);
    }

    function test_single_exactInput_nativeInput(address recipient, uint256 seed) public {
        vm.assume(recipient != address(manager) && recipient != address(this));

        // randomly select a pool
        PoolKey memory poolKey = nativePoolKeys[seed % nativePoolKeys.length];

        bool zeroForOne = true; // native ether is the input
        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        router.swapExactTokensForTokens{value: amountIn}(
            amountIn,
            amountOutMin,
            zeroForOne,
            poolKey,
            ZERO_BYTES,
            recipient,
            uint256(block.timestamp)
        );

        InputOutputBalances memory thisAfter =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract paid input currency
        // recipient did not spend input currency
        assertEq(thisBefore.inputCurrency - thisAfter.inputCurrency, amountIn);
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertApproxEqRel(
            recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountIn, 0.01e18
        ); // allow 1% error

        // verify slippage: recieved > amountOutMin
        assertGt((recipientAfter.outputCurrency - recipientBefore.outputCurrency), amountOutMin);
    }

    function test_single_exactInput_nativeOutput(uint256 seed) public {
        // do not fuzz recipient since not all contracts have receive functions
        address recipient = address(0xABC123);
        // randomly select a pool
        PoolKey memory poolKey = nativePoolKeys[seed % nativePoolKeys.length];

        bool zeroForOne = false; // native ether is the output
        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            zeroForOne,
            poolKey,
            ZERO_BYTES,
            recipient,
            uint256(block.timestamp)
        );

        InputOutputBalances memory thisAfter =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract paid input currency
        // recipient did not spend input currency
        assertEq(thisBefore.inputCurrency - thisAfter.inputCurrency, amountIn);
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertApproxEqRel(
            recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountIn, 0.01e18
        ); // allow 1% error

        // verify slippage: recieved > amountOutMin
        assertGt((recipientAfter.outputCurrency - recipientBefore.outputCurrency), amountOutMin);
    }

    function test_single_exactInput_hookData(address recipient, bool zeroForOne, uint256 seed)
        public
    {
        vm.assume(recipient != address(manager) && recipient != address(this));
        // randomly select a pool
        PoolKey memory poolKey = hookedPoolKeys[seed % hookedPoolKeys.length];
        // data to be passed to the hook
        uint256 num0 = 111;

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.BeforeSwapData(num0);
        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.AfterSwapData(num0);

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            zeroForOne,
            poolKey,
            abi.encode(num0),
            recipient,
            uint256(block.timestamp)
        );

        InputOutputBalances memory thisAfter =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract paid input currency
        // recipient did not spend input currency
        assertEq(thisBefore.inputCurrency - thisAfter.inputCurrency, amountIn);
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertApproxEqRel(
            recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountIn, 0.01e18
        ); // allow 1% error

        // verify slippage: recieved > amountOutMin
        assertGt((recipientAfter.outputCurrency - recipientBefore.outputCurrency), amountOutMin);
    }

    function test_single_exactInput_customCurve(address recipient, bool zeroForOne, uint256 seed)
        public
    {
        vm.assume(recipient != address(manager) && recipient != address(this));
        // randomly select a pool
        PoolKey memory poolKey = csmmPoolKeys[seed % csmmPoolKeys.length];

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            zeroForOne,
            poolKey,
            ZERO_BYTES,
            recipient,
            uint256(block.timestamp)
        );

        InputOutputBalances memory thisAfter =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract paid input currency
        // recipient did not spend input currency
        assertEq(thisBefore.inputCurrency - thisAfter.inputCurrency, amountIn);
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertEq(recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountIn);

        // verify slippage: recieved > amountOutMin
        assertGt((recipientAfter.outputCurrency - recipientBefore.outputCurrency), amountOutMin);
    }

    function test_single_exactOutput(address recipient, bool zeroForOne, uint256 seed) public {
        vm.assume(recipient != address(manager) && recipient != address(this));
        // randomly select a pool
        PoolKey memory poolKey = vanillaPoolKeys[seed % vanillaPoolKeys.length];

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            zeroForOne,
            poolKey,
            ZERO_BYTES,
            recipient,
            uint256(block.timestamp)
        );

        InputOutputBalances memory thisAfter =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertEq(recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountOut);

        // test contract paid inputCurrency
        // recipient did not spend inputCurrency
        assertApproxEqRel(thisBefore.inputCurrency - thisAfter.inputCurrency, amountOut, 0.01e18); // allow 1% error
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // verify slippage: amountIn < amountInMax
        assertLt((thisBefore.inputCurrency - thisAfter.inputCurrency), amountInMax);
    }

    function test_single_exactOutput_nativeInput(address recipient, uint256 seed) public {
        vm.assume(recipient != address(manager) && recipient != address(this));
        // randomly select a pool
        PoolKey memory poolKey = nativePoolKeys[seed % nativePoolKeys.length];

        bool zeroForOne = true; // native ether is the input
        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        router.swapTokensForExactTokens{value: amountInMax}(
            amountOut,
            amountInMax,
            zeroForOne,
            poolKey,
            ZERO_BYTES,
            recipient,
            uint256(block.timestamp)
        );

        InputOutputBalances memory thisAfter =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertEq(recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountOut);

        // test contract paid inputCurrency
        // recipient did not spend inputCurrency
        assertApproxEqRel(thisBefore.inputCurrency - thisAfter.inputCurrency, amountOut, 0.01e18); // allow 1% error
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // verify slippage: amountIn < amountInMax
        assertLt((thisBefore.inputCurrency - thisAfter.inputCurrency), amountInMax);
    }

    function test_single_exactOutput_nativeOutput(uint256 seed) public {
        // do not fuzz recipient since not all addresses have a receive function
        address recipient = address(0xABC123);
        // randomly select a pool
        PoolKey memory poolKey = nativePoolKeys[seed % nativePoolKeys.length];

        bool zeroForOne = false; // native ether is the output
        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            zeroForOne,
            poolKey,
            ZERO_BYTES,
            recipient,
            uint256(block.timestamp)
        );

        InputOutputBalances memory thisAfter =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertEq(recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountOut);

        // test contract paid inputCurrency
        // recipient did not spend inputCurrency
        assertApproxEqRel(thisBefore.inputCurrency - thisAfter.inputCurrency, amountOut, 0.01e18); // allow 1% error
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // verify slippage: amountIn < amountInMax
        assertLt((thisBefore.inputCurrency - thisAfter.inputCurrency), amountInMax);
    }

    function test_single_exactOutput_hookData(address recipient, bool zeroForOne, uint256 seed)
        public
    {
        vm.assume(recipient != address(manager) && recipient != address(this));
        // randomly select a pool
        PoolKey memory poolKey = hookedPoolKeys[seed % hookedPoolKeys.length];
        // data to be passed to the hook
        uint256 num0 = 333;

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.BeforeSwapData(num0);
        vm.expectEmit(true, true, true, true, address(hookWithData));
        emit HookData.AfterSwapData(num0);

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            zeroForOne,
            poolKey,
            abi.encode(num0),
            recipient,
            uint256(block.timestamp)
        );

        InputOutputBalances memory thisAfter =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertEq(recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountOut);

        // test contract paid inputCurrency
        // recipient did not spend inputCurrency
        assertApproxEqRel(thisBefore.inputCurrency - thisAfter.inputCurrency, amountOut, 0.01e18); // allow 1% error
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // verify slippage: amountIn < amountInMax
        assertLt((thisBefore.inputCurrency - thisAfter.inputCurrency), amountInMax);
    }

    function test_single_exactOutput_customCurve(address recipient, bool zeroForOne, uint256 seed)
        public
    {
        vm.assume(recipient != address(manager) && recipient != address(this));
        // randomly select a pool
        PoolKey memory poolKey = csmmPoolKeys[seed % csmmPoolKeys.length];

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            zeroForOne,
            poolKey,
            ZERO_BYTES,
            recipient,
            uint256(block.timestamp)
        );

        InputOutputBalances memory thisAfter =
            inputOutputBalances(address(this), inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertEq(recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountOut);

        // test contract paid inputCurrency
        // recipient did not spend inputCurrency
        assertEq(thisBefore.inputCurrency - thisAfter.inputCurrency, amountOut); // CSMM is 1:1 swaps
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // verify slippage: amountIn < amountInMax
        assertLt((thisBefore.inputCurrency - thisAfter.inputCurrency), amountInMax);
    }

    // Utility Tests

    function test_single_exactInput_hookMsgSender(
        address pranker,
        address recipient,
        bool zeroForOne,
        uint256 seed
    ) public {
        vm.assume(recipient != address(manager) && recipient != address(this));
        // randomly select a pool
        PoolKey memory poolKey = hookMsgSenderPoolKeys[seed % hookMsgSenderPoolKeys.length];
        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        inputCurrency.mint(pranker, 1e18);

        vm.prank(pranker);
        inputCurrency.maxApprove(address(router));

        vm.expectEmit(true, true, true, true, address(hookMsgSender));
        emit HookMsgSender.BeforeSwapWallet(pranker);
        vm.expectEmit(true, true, true, true, address(hookMsgSender));
        emit HookMsgSender.AfterSwapWallet(pranker);

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        vm.prank(pranker);
        router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            zeroForOne,
            poolKey,
            ZERO_BYTES,
            recipient,
            uint256(block.timestamp)
        );
    }
}
