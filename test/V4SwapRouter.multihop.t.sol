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

contract MultihopTest is SwapRouterFixtures {
    using MockCurrencyLibrary for Currency;

    V4SwapRouter router;
    Counter hook;

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

        // Deploy the hook to an address with the correct flags
        _deployCSMM();

        // Define and create all pools with their respective hooks
        PoolKey[] memory _vanillaPoolKeys = _createPoolKeys(address(0));
        _copyArrayToStorage(_vanillaPoolKeys, vanillaPoolKeys);

        PoolKey[] memory _nativePoolKeys = _createNativePoolKeys(address(0));
        _copyArrayToStorage(_nativePoolKeys, nativePoolKeys);

        PoolKey[] memory _hookedPoolKeys = _createPoolKeys(address(Hooks.BEFORE_SWAP_FLAG)); // TODO: set proper hook address
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

    function test_multi_exactInput() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));

        router.swapExactTokensForTokens(
            0.1 ether, 0.09 ether, true, vanillaPoolKeys[0], "", address(this), block.timestamp + 1
        );

        router.swapExactTokensForTokens(
            0.09 ether, 0.08 ether, true, vanillaPoolKeys[1], "", address(this), block.timestamp + 1
        );

        // Verify final token balance
        Currency tokenC = vanillaPoolKeys[1].currency1;
        uint256 tokenCBalance = IERC20Minimal(Currency.unwrap(tokenC)).balanceOf(address(this));
        assertTrue(tokenCBalance >= 0.08 ether, "Should receive at least minimum token amount");
    }

    function test_multi_exactInput_native() public {
        uint256 initialBalance = address(this).balance;

        // First swap: ETH -> Token A
        router.swapExactTokensForTokens{value: 0.1 ether}(
            0.1 ether, 0.09 ether, true, nativePoolKeys[0], "", address(this), block.timestamp + 1
        );

        // Get intermediate token balance and approve
        Currency tokenA = nativePoolKeys[0].currency1;
        uint256 tokenAAmount = IERC20Minimal(Currency.unwrap(tokenA)).balanceOf(address(this));
        IERC20Minimal(Currency.unwrap(tokenA)).approve(address(router), type(uint256).max);

        // Second swap: Token A -> Token B
        router.swapExactTokensForTokens(
            tokenAAmount,
            0.08 ether,
            true,
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1
        );

        // Verify ETH spent and final token received
        assertEq(address(this).balance, initialBalance - 0.1 ether, "ETH balance should decrease");
        Currency tokenB = vanillaPoolKeys[0].currency1;
        uint256 tokenBBalance = IERC20Minimal(Currency.unwrap(tokenB)).balanceOf(address(this));
        assertTrue(tokenBBalance >= 0.08 ether, "Should receive at least minimum token amount");
    }

    function test_multi_exactInput_hookData() public {
        // TODO: use hook which operates on hookData
        // TODO: encode multi-pool path

        // currencyA.mint(address(this), 1 ether);
        // currencyA.maxApprove(address(router));
        // currencyB.maxApprove(address(router));

        // assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 0);
        // assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 0);
        // assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 0);
        // assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 0);

        // router.swapExactTokensForTokens(
        //     0.1 ether, 0.09 ether, true, hookedPoolKeys[0], "", address(this), block.timestamp + 1
        // );

        // router.swapExactTokensForTokens(
        //     0.09 ether, 0.08 ether, true, hookedPoolKeys[1], "", address(this), block.timestamp + 1
        // );

        // assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 1);
        // assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 1);
        // assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 1);
        // assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 1);
    }

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

    function test_multi_exactOutput() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));

        router.swapTokensForExactTokens(
            0.1 ether, 0.15 ether, true, vanillaPoolKeys[1], "", address(this), block.timestamp + 1
        );

        router.swapTokensForExactTokens(
            0.15 ether, 0.2 ether, true, vanillaPoolKeys[0], "", address(this), block.timestamp + 1
        );
    }

    function test_multi_exactOutput_native() public {
        uint256 initialBalance = address(this).balance;

        // Approve tokens for input
        Currency tokenA = vanillaPoolKeys[0].currency0;
        Currency tokenB = vanillaPoolKeys[0].currency1;
        IERC20Minimal(Currency.unwrap(tokenA)).approve(address(router), type(uint256).max);
        IERC20Minimal(Currency.unwrap(tokenB)).approve(address(router), type(uint256).max);

        // First swap: TokenA -> TokenB
        router.swapTokensForExactTokens(
            0.15 ether, 0.2 ether, true, vanillaPoolKeys[0], "", address(this), block.timestamp + 1
        );

        // Second swap: TokenB -> ETH
        router.swapTokensForExactTokens(
            0.1 ether, 0.15 ether, false, nativePoolKeys[0], "", address(this), block.timestamp + 1
        );

        assertEq(
            address(this).balance - initialBalance, 0.1 ether, "Should receive exact ETH amount"
        );
    }

    function test_multi_exactOutput_hookData() public {
        // TODO: use hook which operates on hookData
        // TODO: encode multi-pool path

        // currencyA.mint(address(this), 1 ether);
        // currencyA.maxApprove(address(router));
        // currencyB.maxApprove(address(router));

        // assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 0);
        // assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 0);
        // assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 0);
        // assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 0);

        // router.swapTokensForExactTokens(
        //     0.1 ether, 0.15 ether, true, hookedPoolKeys[1], "", address(this), block.timestamp + 1
        // );

        // router.swapTokensForExactTokens(
        //     0.15 ether, 0.2 ether, true, hookedPoolKeys[0], "", address(this), block.timestamp + 1
        // );

        // assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 1);
        // assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 1);
        // assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 1);
        // assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 1);
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
