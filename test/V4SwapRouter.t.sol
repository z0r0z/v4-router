// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {PathKey} from "../src/libraries/PathKey.sol";
import {IERC20Minimal} from "@v4/src/interfaces/external/IERC20Minimal.sol";
import {IERC6909Claims} from "@v4/src/interfaces/external/IERC6909Claims.sol";

import {Counter} from "@v4-template/src/Counter.sol";
import {HookMiner} from "@v4-template/test/utils/HookMiner.sol";
import {CustomCurveHook} from "./utils/hooks/CustomCurveHook.sol";
import {BaseHook} from "@v4-periphery/src/base/hooks/BaseHook.sol";

import {IPoolManager, ISignatureTransfer, BaseData, V4SwapRouter} from "../src/V4SwapRouter.sol";

import {SwapRouterFixtures, Deployers} from "./utils/SwapRouterFixtures.sol";
import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";

contract RouterTest is SwapRouterFixtures {
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
        router = new V4SwapRouter(manager, permit2);

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

        // Deploy Counter hook
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144)
        );

        bytes memory constructorArgs = abi.encode(manager);
        deployCodeTo("Counter.sol:Counter", constructorArgs, flags);
        hook = Counter(flags);

        // Deploy CustomCurveHook
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

    function test_revert_deadline_passed() public {
        vm.warp(100); // Set current timestamp

        vm.expectRevert(abi.encodeWithSignature("DeadlinePassed(uint256)", 99));
        router.swapExactTokensForTokens(
            0.1 ether,
            0.09 ether,
            true,
            vanillaPoolKeys[0],
            "",
            address(this),
            99 // deadline in the past
        );
    }

    function test_revert_zero_amount() public {
        vm.expectRevert(); // Should revert due to zero amount
        router.swapExactTokensForTokens(
            0, 0, true, vanillaPoolKeys[0], "", address(this), block.timestamp + 1
        );
    }

    function test_revert_insufficient_balance() public {
        uint256 hugeAmount = 1000 ether;

        vm.expectRevert(); // Should revert due to insufficient balance
        router.swapExactTokensForTokens(
            hugeAmount, 0, true, vanillaPoolKeys[0], "", address(this), block.timestamp + 1
        );
    }

    function test_router_deploy_gas() public {
        router = new V4SwapRouter(manager, permit2);
    }

    function test_zero_for_one() public {
        // For zeroForOne, we need to approve and have balance of currency0 (AA)
        Currency currency0 = vanillaPoolKeys[0].currency0;
        currency0.mint(address(this), 1 ether);
        currency0.maxApprove(address(router));

        uint256 balanceBefore =
            IERC20Minimal(Currency.unwrap(vanillaPoolKeys[0].currency1)).balanceOf(address(this));

        router.swapExactTokensForTokens(
            0.1 ether,
            0.09 ether,
            true, // zeroForOne
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1
        );

        uint256 balanceAfter =
            IERC20Minimal(Currency.unwrap(vanillaPoolKeys[0].currency1)).balanceOf(address(this));
        assertGt(balanceAfter, balanceBefore, "Balance should increase");
        assertGe(balanceAfter - balanceBefore, 0.09 ether, "Insufficient output amount");
    }

    function test_one_for_zero() public {
        // For oneForZero, we need to approve and have balance of currency1 (BB)
        Currency currency1 = vanillaPoolKeys[0].currency1;
        currency1.mint(address(this), 1 ether);
        currency1.maxApprove(address(router));

        uint256 balanceBefore =
            IERC20Minimal(Currency.unwrap(vanillaPoolKeys[0].currency0)).balanceOf(address(this));

        router.swapExactTokensForTokens(
            0.1 ether,
            0.09 ether,
            false, // oneForZero
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1
        );

        uint256 balanceAfter =
            IERC20Minimal(Currency.unwrap(vanillaPoolKeys[0].currency0)).balanceOf(address(this));
        assertGt(balanceAfter, balanceBefore, "Balance should increase");
        assertGe(balanceAfter - balanceBefore, 0.09 ether, "Insufficient output amount");
    }

    function test_revert_slippage_exceeded_exactInput() public {
        // Setup: Mint and approve tokens
        Currency currency0 = vanillaPoolKeys[0].currency0;
        currency0.mint(address(this), 1 ether);
        currency0.maxApprove(address(router));

        // Set minimum output amount very high to trigger slippage protection
        uint256 unreasonablyHighMinimumOutput = 0.99 ether; // Expecting more than 99% of input

        vm.expectRevert(abi.encodeWithSignature("SlippageExceeded()"));
        router.swapExactTokensForTokens(
            0.1 ether, // input amount
            unreasonablyHighMinimumOutput, // minimum output (unreasonably high)
            true, // zeroForOne
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1
        );
    }

    function test_revert_slippage_exceeded_exactOutput() public {
        // Setup: Mint and approve tokens
        Currency currency0 = vanillaPoolKeys[0].currency0;
        currency0.mint(address(this), 1 ether);
        currency0.maxApprove(address(router));

        // Set maximum input amount very low to trigger slippage protection
        uint256 unreasonablyLowMaximumInput = 0.01 ether; // Only willing to pay 1% of output requested

        vm.expectRevert(abi.encodeWithSignature("SlippageExceeded()"));
        router.swapTokensForExactTokens(
            1 ether, // exact output wanted
            unreasonablyLowMaximumInput, // maximum input (unreasonably low)
            true, // zeroForOne
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1
        );
    }

    function test_revert_single_swap_exactInput_not_enough_output() public {
        // Setup: Mint and approve tokens
        Currency currency0 = vanillaPoolKeys[0].currency0;
        currency0.mint(address(this), 1 ether);
        currency0.maxApprove(address(router));

        // Set unreasonably high minimum output
        uint256 amountIn = 0.1 ether;
        uint256 unreasonableMinOutput = 1 ether; // Expecting 10x return

        vm.expectRevert(abi.encodeWithSignature("SlippageExceeded()"));
        router.swapExactTokensForTokens(
            amountIn,
            unreasonableMinOutput,
            true,
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1
        );
    }

    function test_revert_single_swap_exactOutput_not_enough_input() public {
        // Setup: Mint and approve tokens
        Currency currency0 = vanillaPoolKeys[0].currency0;
        currency0.mint(address(this), 1 ether);
        currency0.maxApprove(address(router));

        // Set unreasonably low maximum input
        uint256 amountOut = 1 ether;
        uint256 unreasonableMaxInput = 0.01 ether; // Only willing to pay 1% of output

        vm.expectRevert(abi.encodeWithSignature("SlippageExceeded()"));
        router.swapTokensForExactTokens(
            amountOut,
            unreasonableMaxInput,
            true,
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1
        );
    }

    function test_revert_multihop_exactInput_not_enough_output() public {
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
        uint256 unreasonableMinOutput = 10e18; // Expecting 10x return

        vm.expectRevert(abi.encodeWithSignature("SlippageExceeded()"));
        router.swapExactTokensForTokens(
            amountIn, unreasonableMinOutput, startCurrency, path, address(this), block.timestamp + 1
        );
    }

    function test_revert_multihop_exactOutput_not_enough_input() public {
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

        uint256 amountOut = 1e18;
        uint256 unreasonableMaxInput = 0.01e18; // Only willing to pay 1% of output

        vm.expectRevert(abi.encodeWithSignature("SlippageExceeded()"));
        router.swapTokensForExactTokens(
            amountOut, unreasonableMaxInput, startCurrency, path, address(this), block.timestamp + 1
        );
    }
}
