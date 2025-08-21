// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {IERC20Minimal} from "@v4/src/interfaces/external/IERC20Minimal.sol";
import {IERC6909Claims} from "@v4/src/interfaces/external/IERC6909Claims.sol";

import {Counter} from "@v4-template/src/Counter.sol";
import {HookMiner} from "@v4-periphery/src/utils/HookMiner.sol";
import {CustomCurveHook} from "./utils/hooks/CustomCurveHook.sol";
import {BaseHook} from "@v4-periphery/src/utils/BaseHook.sol";

import {
    IPoolManager,
    ISignatureTransfer,
    BaseData,
    UniswapV4Router04,
    SwapFlags
} from "../src/UniswapV4Router04.sol";

import {SwapRouterFixtures, Deployers} from "./utils/SwapRouterFixtures.sol";
import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";

import {console} from "forge-std/console.sol";

contract Router6909Test is SwapRouterFixtures {
    using MockCurrencyLibrary for Currency;

    UniswapV4Router04 router;

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
        router = new UniswapV4Router04(manager, permit2);

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
        IERC6909Claims(address(manager)).setOperator(address(router), true);

        // Deploy hooks
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

        // Pool setup
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

        // Initial swaps to get ERC6909 balances for both tokens / warm up pools
        uint8 flags1 = SwapFlags.SINGLE_SWAP | SwapFlags.OUTPUT_6909;
        bytes memory swapData = abi.encode(
            BaseData({
                amount: INITIAL_SWAP_AMOUNT,
                amountLimit: INITIAL_SWAP_AMOUNT * 95 / 100,
                payer: address(this),
                receiver: address(this),
                flags: flags1
            }),
            true, // zeroForOne
            vanillaPoolKeys[1],
            "" // hookData
        );
        router.swap{value: INITIAL_SWAP_AMOUNT}(swapData, block.timestamp + 1);

        // Opposite direction swap
        uint8 flags2 = SwapFlags.SINGLE_SWAP | SwapFlags.INPUT_6909;
        swapData = abi.encode(
            BaseData({
                amount: INITIAL_SWAP_AMOUNT / 2,
                amountLimit: (INITIAL_SWAP_AMOUNT / 2) * 95 / 100,
                payer: address(this),
                receiver: address(this),
                flags: flags2
            }),
            false, // !zeroForOne
            vanillaPoolKeys[1],
            "" // hookData
        );
        router.swap(swapData, block.timestamp + 1);

        // Additional warmup swaps
        uint8 flags3 = SwapFlags.SINGLE_SWAP | SwapFlags.OUTPUT_6909;
        swapData = abi.encode(
            BaseData({
                amount: INITIAL_SWAP_AMOUNT,
                amountLimit: INITIAL_SWAP_AMOUNT * 95 / 100,
                payer: address(this),
                receiver: address(this),
                flags: flags3
            }),
            true, // zeroForOne
            vanillaPoolKeys[0],
            "" // hookData
        );
        router.swap(swapData, block.timestamp + 1);

        swapData = abi.encode(
            BaseData({
                amount: INITIAL_SWAP_AMOUNT,
                amountLimit: INITIAL_SWAP_AMOUNT * 95 / 100,
                payer: address(this),
                receiver: address(this),
                flags: flags3
            }),
            false, // !zeroForOne
            vanillaPoolKeys[0],
            "" // hookData
        );
        router.swap(swapData, block.timestamp + 1);
    }

    function test_swap_erc20_to_erc20() public {
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

    function test_swap_eth_to_erc6909() public {
        uint8 flags = SwapFlags.SINGLE_SWAP | SwapFlags.OUTPUT_6909;
        bytes memory swapData = abi.encode(
            BaseData({
                amount: SWAP_AMOUNT,
                amountLimit: MIN_OUTPUT,
                payer: address(this),
                receiver: address(this),
                flags: flags
            }),
            true, // zeroForOne
            vanillaPoolKeys[1],
            "" // hookData
        );
        router.swap{value: SWAP_AMOUNT}(swapData, block.timestamp + 1);
    }

    function test_swap_erc20_to_erc6909() public {
        uint8 flags = SwapFlags.SINGLE_SWAP | SwapFlags.OUTPUT_6909;
        bytes memory swapData = abi.encode(
            BaseData({
                amount: SWAP_AMOUNT,
                amountLimit: MIN_OUTPUT,
                payer: address(this),
                receiver: address(this),
                flags: flags
            }),
            true, // zeroForOne
            vanillaPoolKeys[0],
            "" // hookData
        );
        router.swap(swapData, block.timestamp + 1);
    }

    function test_swap_erc6909_to_erc6909() public {
        uint8 flags = SwapFlags.SINGLE_SWAP | SwapFlags.INPUT_6909 | SwapFlags.OUTPUT_6909;
        bytes memory swapData = abi.encode(
            BaseData({
                amount: SWAP_AMOUNT,
                amountLimit: MIN_OUTPUT,
                payer: address(this),
                receiver: address(this),
                flags: flags
            }),
            false, // opposite direction from setup swap
            vanillaPoolKeys[0],
            "" // hookData
        );
        router.swap(swapData, block.timestamp + 1);
    }
}
