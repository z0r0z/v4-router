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

    // Test amounts
    uint256 constant INITIAL_SWAP_AMOUNT = 0.1 ether;
    uint256 constant SWAP_AMOUNT = 0.001 ether;
    uint256 constant MIN_OUTPUT = 0.00095 ether;

    function setUp() public payable {
        // Deploy v4 contracts
        Deployers.deployFreshManagerAndRouters();
        DeployPermit2.deployPermit2();
        router = new V4SwapRouter(manager, permit2);

        // Create currencies
        (currencyA, currencyB, currencyC, currencyD) = _createSortedCurrencies();

        // Initial mints
        currencyA.mint(address(this), 10_000e18);
        currencyB.mint(address(this), 10_000e18);
        currencyC.mint(address(this), 10_000e18);
        currencyD.mint(address(this), 10_000e18);

        // Setup approvals
        currencyA.maxApprove(address(modifyLiquidityRouter));
        currencyB.maxApprove(address(modifyLiquidityRouter));
        currencyC.maxApprove(address(modifyLiquidityRouter));
        currencyD.maxApprove(address(modifyLiquidityRouter));

        // Additional approvals for router
        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));
        IERC6909(address(manager)).setOperator(address(router), true);

        // Deploy hooks [hook deployment code remains the same]
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144)
        );

        bytes memory constructorArgs = abi.encode(manager);
        deployCodeTo("Counter.sol:Counter", constructorArgs, flags);
        hook = Counter(flags);

        address csmmFlags =
            address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x5555 << 144));
        bytes memory csmmConstructorArgs = abi.encode(manager);
        deployCodeTo("CustomCurveHook.sol:CustomCurveHook", csmmConstructorArgs, csmmFlags);
        hookCsmm = CustomCurveHook(csmmFlags);

        // Pool setup [remains the same]
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

        // Initial swaps to get ERC6909 balances for both tokens
        router.swap(
            -int256(INITIAL_SWAP_AMOUNT),
            INITIAL_SWAP_AMOUNT * 95 / 100,
            true, // zeroForOne
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1,
            false, // inputIs6909
            true // outputIs6909
        );

        router.swap(
            -int256(INITIAL_SWAP_AMOUNT),
            INITIAL_SWAP_AMOUNT * 95 / 100,
            false, // !zeroForOne - opposite direction
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1,
            false, // inputIs6909
            true // outputIs6909
        );
    }

    function test_swapERC20ToERC20() public {
        router.swapExactTokensForTokens(
            SWAP_AMOUNT,
            MIN_OUTPUT,
            true,
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1
        );
    }

    function test_swapERC20ToERC6909() public {
        router.swap(
            -int256(SWAP_AMOUNT),
            MIN_OUTPUT,
            true,
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1,
            false, // inputIs6909
            true // outputIs6909
        );
    }

    function test_swapERC6909ToERC6909() public {
        router.swap(
            -int256(SWAP_AMOUNT),
            MIN_OUTPUT,
            false, // opposite direction from setup swap
            vanillaPoolKeys[0],
            "",
            address(this),
            block.timestamp + 1,
            true, // inputIs6909
            true // outputIs6909
        );
    }
}

interface IERC6909 {
    function setOperator(address, bool) external;
}
