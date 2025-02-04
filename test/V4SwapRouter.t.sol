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

import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";

import {IPoolManager, ISignatureTransfer, BaseData, V4SwapRouter} from "../src/V4SwapRouter.sol";

import {SwapRouterFixtures, Deployers} from "./utils/SwapRouterFixtures.sol";
import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";

import {console} from "forge-std/console.sol";

contract RouterTest is SwapRouterFixtures, DeployPermit2 {
    using MockCurrencyLibrary for Currency;

    V4SwapRouter router;
    ISignatureTransfer permit2 = ISignatureTransfer(address(PERMIT2_ADDRESS));

    Counter hook;
    CustomCurveHook hookCsmm;

    PoolKey[] vanillaPoolKeys;
    PoolKey[] nativePoolKeys;
    PoolKey[] hookedPoolKeys;
    PoolKey[] csmmPoolKeys;

    function setUp() public payable {
        // Deploy v4 contracts
        Deployers.deployFreshManagerAndRouters();
        DeployPermit2.deployPermit2();
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

    function test_revertDeadlinePassed() public {
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

    function test_revertZeroAmount() public {
        vm.expectRevert(); // Should revert due to zero amount
        router.swapExactTokensForTokens(
            0, 0, true, vanillaPoolKeys[0], "", address(this), block.timestamp + 1
        );
    }

    function test_revertInsufficientBalance() public {
        uint256 hugeAmount = 1000 ether;

        vm.expectRevert(); // Should revert due to insufficient balance
        router.swapExactTokensForTokens(
            hugeAmount, 0, true, vanillaPoolKeys[0], "", address(this), block.timestamp + 1
        );
    }

    function test_routerDeployGas() public {
        router = new V4SwapRouter(manager, permit2);
    }

    function test_zeroForOne() public {
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

    function test_oneForZero() public {
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

    function test_revertSlippageExceededExactInput() public {
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

    function test_revertSlippageExceededExactOutput() public {
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

    function test_singleSwap20To6909() public {
        // Setup initial ERC20 balance and approval
        Currency currency0 = vanillaPoolKeys[0].currency0;
        Currency currency1 = vanillaPoolKeys[0].currency1;

        currency0.mint(address(this), 1 ether);
        currency0.maxApprove(address(router));

        // Initial ERC6909 balance check
        uint256 balanceBefore = manager.balanceOf(address(this), currency1.toId());

        router.swap(
            -0.1 ether, // negative amountSpecified for exact input
            0.095 ether, // minimum amount out
            true, // zeroForOne
            vanillaPoolKeys[0], // poolKey
            "", // hookData
            address(this), // recipient
            block.timestamp + 1, // deadline
            false, // inputIs6909 (ERC20 input)
            true // outputIs6909 (ERC6909 output)
        );

        uint256 balanceAfter = manager.balanceOf(address(this), currency1.toId());
        assertGt(balanceAfter, balanceBefore, "Balance should increase");
        assertGe(balanceAfter - balanceBefore, 0.095 ether, "Insufficient output amount");
    }

    function test_chainedSwaps6909() public {
        Currency currency0 = vanillaPoolKeys[0].currency0;
        Currency currency1 = vanillaPoolKeys[0].currency1;

        console.log("Currency0 ID:", currency0.toId());
        console.log("Currency1 ID:", currency1.toId());

        // Initial setup - mint ERC20 and approve
        currency0.mint(address(this), 1 ether);
        currency0.maxApprove(address(router));

        // First swap: ERC20 -> ERC6909
        router.swap(
            -0.1 ether,
            0.095 ether,
            true,
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1,
            false,
            true
        );

        uint256 currency1Balance = manager.balanceOf(address(this), currency1.toId());
        console.log("Received ERC6909 balance of currency1:", currency1Balance);

        // Approve router for ERC6909 operations
        IERC6909(address(manager)).setOperator(address(router), true);

        uint256 swapAmount = 0.001 ether;
        require(swapAmount <= currency1Balance, "Insufficient balance");

        console.log("Pre-swap balances:");
        console.log("Currency0 (ERC6909):", manager.balanceOf(address(this), currency0.toId()));
        console.log("Currency1 (ERC6909):", manager.balanceOf(address(this), currency1.toId()));
        console.log("Attempting to swap amount:", swapAmount);

        // Swap back: currency1 -> currency0
        router.swap(
            -int256(swapAmount),
            (swapAmount * 95) / 100,
            false,
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1,
            true,
            true
        );

        console.log("Final balances:");
        console.log("Currency0 (ERC6909):", manager.balanceOf(address(this), currency0.toId()));
        console.log("Currency1 (ERC6909):", manager.balanceOf(address(this), currency1.toId()));
    }

    function test_chainedSwaps6909ToERC20() public {
        Currency currency0 = vanillaPoolKeys[0].currency0;
        Currency currency1 = vanillaPoolKeys[0].currency1;

        console.log("Currency0 ID:", currency0.toId());
        console.log("Currency1 ID:", currency1.toId());

        // Initial setup - mint ERC20 and approve
        currency0.mint(address(this), 1 ether);
        currency0.maxApprove(address(router));

        // First swap: ERC20 -> ERC6909
        router.swap(
            -0.1 ether,
            0.095 ether,
            true,
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1,
            false, // input is ERC20
            true // output as ERC6909
        );

        uint256 currency1Balance = manager.balanceOf(address(this), currency1.toId());
        console.log("Received ERC6909 balance of currency1:", currency1Balance);

        // Approve router for ERC6909 operations
        IERC6909(address(manager)).setOperator(address(router), true);

        uint256 swapAmount = 0.001 ether;
        require(swapAmount <= currency1Balance, "Insufficient balance");

        console.log("Pre-swap balances:");
        console.log("Currency0 (ERC20):", currency0.balanceOf(address(this)));
        console.log("Currency1 (ERC6909):", manager.balanceOf(address(this), currency1.toId()));
        console.log("Attempting to swap amount:", swapAmount);

        // Swap back: currency1 (ERC6909) -> currency0 (ERC20)
        router.swap(
            -int256(swapAmount),
            (swapAmount * 95) / 100,
            false,
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1,
            true, // input is ERC6909
            false // output as ERC20
        );

        console.log("Final balances:");
        console.log("Currency0 (ERC20):", currency0.balanceOf(address(this)));
        console.log("Currency1 (ERC6909):", manager.balanceOf(address(this), currency1.toId()));
    }
}

interface IERC6909 {
    function setOperator(address, bool) external;
}
