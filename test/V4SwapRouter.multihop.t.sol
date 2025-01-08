// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {IERC20Minimal} from "@v4/src/interfaces/external/IERC20Minimal.sol";

import {Counter} from "@v4-template/src/Counter.sol";
import {HookMiner} from "@v4-template/test/utils/HookMiner.sol";
import {CustomCurveHook} from "./utils/hooks/CustomCurveHook.sol";
import {BaseHook} from "@v4-periphery/src/base/hooks/BaseHook.sol";

import {V4SwapRouter} from "../src/V4SwapRouter.sol";

import {SwapRouterFixtures, Deployers} from "./utils/SwapRouterFixtures.sol";
import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";

contract MultihopTest is SwapRouterFixtures {
    using MockCurrencyLibrary for Currency;

    V4SwapRouter router;
    Counter hook;
    CustomCurveHook hookCsmm;

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

        // Deploy Counter hook with correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144)
        );

        bytes memory constructorArgs = abi.encode(manager);
        deployCodeTo("Counter.sol:Counter", constructorArgs, flags);
        hook = Counter(flags);

        // Deploy CustomCurveHook with correct flags
        address csmmFlags =
            address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x5555 << 144));
        bytes memory csmmConstructorArgs = abi.encode(manager);
        deployCodeTo("CustomCurveHook.sol:CustomCurveHook", csmmConstructorArgs, csmmFlags);
        hookCsmm = CustomCurveHook(csmmFlags);

        // Define and create all pools with their respective hooks
        PoolKey[] memory _vanillaPoolKeys = _createPoolKeys(address(0));
        _copyArrayToStorage(_vanillaPoolKeys, vanillaPoolKeys);

        PoolKey[] memory _nativePoolKeys = _createNativePoolKeys(address(0));
        _copyArrayToStorage(_nativePoolKeys, nativePoolKeys);

        PoolKey[] memory _hookedPoolKeys = _createPoolKeys(address(hook));
        _copyArrayToStorage(_hookedPoolKeys, hookedPoolKeys);

        PoolKey[] memory _csmmPoolKeys = _createPoolKeys(address(hookCsmm));
        _copyArrayToStorage(_csmmPoolKeys, csmmPoolKeys);

        PoolKey[] memory allPoolKeys =
            _concatPools(vanillaPoolKeys, nativePoolKeys, hookedPoolKeys, csmmPoolKeys);
        _initializePools(allPoolKeys);
        _addLiquidity(allPoolKeys, 10_000e18);
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
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));

        assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 0);
        assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 0);
        assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 0);
        assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 0);

        router.swapExactTokensForTokens(
            0.1 ether, 0.09 ether, true, hookedPoolKeys[0], "", address(this), block.timestamp + 1
        );

        router.swapExactTokensForTokens(
            0.09 ether, 0.08 ether, true, hookedPoolKeys[1], "", address(this), block.timestamp + 1
        );

        assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 1);
        assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 1);
        assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 1);
        assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 1);
    }

    function test_multi_exactInput_customCurve() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));

        router.swapExactTokensForTokens(
            0.1 ether, 0.09 ether, true, csmmPoolKeys[0], "", address(this), block.timestamp + 1
        );

        router.swapExactTokensForTokens(
            0.09 ether, 0.08 ether, true, csmmPoolKeys[1], "", address(this), block.timestamp + 1
        );
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
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));

        assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 0);
        assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 0);
        assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 0);
        assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 0);

        router.swapTokensForExactTokens(
            0.1 ether, 0.15 ether, true, hookedPoolKeys[1], "", address(this), block.timestamp + 1
        );

        router.swapTokensForExactTokens(
            0.15 ether, 0.2 ether, true, hookedPoolKeys[0], "", address(this), block.timestamp + 1
        );

        assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 1);
        assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 1);
        assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 1);
        assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 1);
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
