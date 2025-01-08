// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";

import {Counter} from "@v4-template/src/Counter.sol";
import {HookMiner} from "@v4-template/test/utils/HookMiner.sol";
import {CustomCurveHook} from "./utils/hooks/CustomCurveHook.sol";
import {BaseHook} from "@v4-periphery/src/base/hooks/BaseHook.sol";

import {V4SwapRouter} from "../src/V4SwapRouter.sol";

import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";
import {SwapRouterFixtures, Deployers} from "./utils/SwapRouterFixtures.sol";

contract RouterGasTest is SwapRouterFixtures {
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
        ); // Same namespace as in Counter test

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

        // Vanilla pool - no hook
        PoolKey[] memory _vanillaPoolKeys = _createPoolKeys(address(0));
        _copyArrayToStorage(_vanillaPoolKeys, vanillaPoolKeys);

        // Native ETH pool
        PoolKey[] memory _nativePoolKeys = _createNativePoolKeys(address(0));
        _copyArrayToStorage(_nativePoolKeys, nativePoolKeys);

        // Counter hook for regular hook
        PoolKey[] memory _hookedPoolKeys = _createPoolKeys(address(hook));
        _copyArrayToStorage(_hookedPoolKeys, hookedPoolKeys);

        // Simple curve hook from utils
        PoolKey[] memory _csmmPoolKeys = _createPoolKeys(address(hookCsmm));
        _copyArrayToStorage(_csmmPoolKeys, csmmPoolKeys);

        PoolKey[] memory allPoolKeys =
            _concatPools(vanillaPoolKeys, nativePoolKeys, hookedPoolKeys, csmmPoolKeys);
        _initializePools(allPoolKeys);
        _addLiquidity(allPoolKeys, 10_000e18);
    }

    function test_gas_single_exactInput() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));

        router.swapExactTokensForTokens(
            0.1 ether, 0.09 ether, true, vanillaPoolKeys[0], "", address(this), block.timestamp + 1
        );
    }

    function test_gas_single_exactInput_hooked() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));

        assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 0);
        assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 0);

        router.swapExactTokensForTokens(
            0.1 ether, 0.09 ether, true, hookedPoolKeys[0], "", address(this), block.timestamp + 1
        );

        assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 1);
        assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 1);
    }

    function test_gas_single_exactInput_customCurve() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));

        router.swapExactTokensForTokens(
            0.1 ether, 0.09 ether, true, csmmPoolKeys[0], "", address(this), block.timestamp + 1
        );
    }

    function test_gas_multi_exactInput() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));

        router.swapExactTokensForTokens(
            0.1 ether, 0.09 ether, true, vanillaPoolKeys[0], "", address(this), block.timestamp + 1
        );

        router.swapExactTokensForTokens(
            0.09 ether, 0.08 ether, true, vanillaPoolKeys[1], "", address(this), block.timestamp + 1
        );
    }

    function test_gas_multi_exactInput_hooked() public {
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

    function test_gas_multi_exactInput_customCurve() public {
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

    function test_gas_single_exactOutput_hooked() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));

        // Check initial counts using pool key directly
        assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 0);
        assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 0);

        router.swapTokensForExactTokens(
            0.1 ether, // exact amount out
            0.15 ether, // maximum amount in
            true, // zeroForOne
            hookedPoolKeys[0], // pool with Counter hook
            "", // no hook data
            address(this), // recipient
            block.timestamp + 1
        );

        // Verify hook interactions using pool key directly
        assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 1);
        assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 1);
    }

    function test_gas_single_exactOutput_customCurve() public {
        currencyA.mint(address(this), 1 ether);
        currencyA.maxApprove(address(router));

        router.swapTokensForExactTokens(
            0.1 ether, 0.15 ether, true, csmmPoolKeys[0], "", address(this), block.timestamp + 1
        );
    }

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

    function test_gas_multi_exactOutput_hooked() public {
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

    function test_gas_multi_exactOutput_customCurve() public {
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

    // Native token tests WIP
    //function test_gas_single_exactInput_native() public {}
    //function test_gas_multi_exactInput_native() public {}
    //function test_gas_single_exactOutput_native() public {}
    //function test_gas_multi_exactOutput_native() public {}
}
