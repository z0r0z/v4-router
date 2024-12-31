// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";

import {V4SwapRouter} from "../src/V4SwapRouter.sol";
import {IPoolManager, PoolManager} from "@v4/src/PoolManager.sol";

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "@v4/src/types/Currency.sol";

import {Test} from "../lib/forge-std/src/Test.sol";
import {MockERC20} from "@solady/test/utils/mocks/MockERC20.sol";

import {NoOpSwapHook} from "./utils/mocks/hooks/NoOpSwapHook.sol";

import {PoolModifyLiquidityTest} from "@v4/src/test/PoolModifyLiquidityTest.sol";

import {PathKey} from "../src/libraries/PathKey.sol";

import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";

contract V4SwapRouterTest is Test, GasSnapshot {
    using MockCurrencyLibrary for Currency;
    address internal aliceSwapper;

    address internal manager;
    V4SwapRouter internal router;

    PoolModifyLiquidityTest internal liqRouter;

    Currency internal nativeCurrency = CurrencyLibrary.ADDRESS_ZERO;
    Currency internal currencyA;
    Currency internal currencyB;
    Currency internal currencyC;
    Currency internal currencyD;
    
    address internal currency0Addr;
    address internal currency1Addr;
    address internal currency2Addr;
    address internal currency3Addr;

    // Min tick for full range with tick spacing of TICK_SPACING.
    int24 internal constant MIN_TICK = -887220;
    // Max tick for full range with tick spacing of TICK_SPACING.
    int24 internal constant MAX_TICK = -MIN_TICK;

    uint24 internal constant FEE = FEE;
    int24 internal constant TICK_SPACING = TICK_SPACING;

    // Vanilla pool (no hook).
    PoolKey internal keyNoHook;

    // Vanilla variant for cf.
    PoolKey internal keyNoHook2;

    // Vanilla variant for cf.
    PoolKey internal keyNoHook3;

    // Vanilla variant for cf.
    PoolKey internal keyNoHook4;

    // Vanilla variant for cf.
    PoolKey internal keyNoHook5;

    // ETH based pool (no hook).
    PoolKey internal ethKeyNoHook;

    // Basic no-op hook pool.
    PoolKey internal keyNoOpSwapHook;

    // Basic no-op hook for testing.
    IHooks internal noOpSwapHook;

    // floor(sqrt(1) * 2^96)
    uint1TICK_SPACING constant startingPrice = 79228162514264337593543950336;

    function setUp() public payable {
        aliceSwapper = makeAddr("alice");
        payable(aliceSwapper).transfer(1 ether);

        manager = address(new PoolManager(address(this)));
        router = new V4SwapRouter(IPoolManager(manager));

        liqRouter = new PoolModifyLiquidityTest(IPoolManager(manager));

        address[] memory addrs = new address[](4);

        addrs[0] = address(new MockERC20("Test0", "Test0", 18));
        addrs[1] = address(new MockERC20("Test1", "Test2", 18));
        addrs[2] = address(new MockERC20("Test2", "Test2", 18));
        addrs[3] = address(new MockERC20("Test3", "Test3", 18));

        addrs = _sortAddresses(addrs);
        currency0Addr = addrs[0];
        currency1Addr = addrs[1];
        currency2Addr = addrs[2];
        currency3Addr = addrs[3];

        MockERC20(currency0Addr).mint(aliceSwapper, 100 ether);
        MockERC20(currency1Addr).mint(aliceSwapper, 100 ether);
        MockERC20(currency2Addr).mint(aliceSwapper, 100 ether);
        MockERC20(currency3Addr).mint(aliceSwapper, 100 ether);

        vm.prank(aliceSwapper);
        MockERC20(currency0Addr).approve(address(router), type(uint256).max);
        vm.prank(aliceSwapper);
        MockERC20(currency1Addr).approve(address(router), type(uint256).max);
        vm.prank(aliceSwapper);
        MockERC20(currency2Addr).approve(address(router), type(uint256).max);
        vm.prank(aliceSwapper);
        MockERC20(currency3Addr).approve(address(router), type(uint256).max);

        vm.prank(aliceSwapper);
        MockERC20(currency0Addr).approve(address(liqRouter), type(uint256).max);
        vm.prank(aliceSwapper);
        MockERC20(currency1Addr).approve(address(liqRouter), type(uint256).max);
        vm.prank(aliceSwapper);
        MockERC20(currency2Addr).approve(address(liqRouter), type(uint256).max);
        vm.prank(aliceSwapper);
        MockERC20(currency3Addr).approve(address(liqRouter), type(uint256).max);

        keyNoHook = PoolKey({
            currency0: Currency.wrap(currency0Addr),
            currency1: Currency.wrap(currency1Addr),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook, startingPrice);

        keyNoHook2 = PoolKey({
            currency0: Currency.wrap(currency2Addr),
            currency1: Currency.wrap(currency3Addr),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook2, startingPrice);

        keyNoHook3 = PoolKey({
            currency0: Currency.wrap(currency1Addr),
            currency1: Currency.wrap(currency3Addr),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook3, startingPrice);

        keyNoHook4 = PoolKey({
            currency0: Currency.wrap(currency1Addr),
            currency1: Currency.wrap(currency2Addr),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook4, startingPrice);

        keyNoHook5 = PoolKey({
            currency0: Currency.wrap(currency0Addr),
            currency1: Currency.wrap(currency3Addr),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook5, startingPrice);

        /*noOpSwapHook = IHooks(address(new NoOpSwapHook(IPoolManager(manager))));

        keyNoOpSwapHook = PoolKey({
            currency0: Currency.wrap(currency0Addr),
            currency1: Currency.wrap(currency1Addr),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: noOpSwapHook
        });

        PoolManager(manager).initialize(keyNoOpSwapHook, startingPrice);*/

        ethKeyNoHook = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(currency1Addr),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(ethKeyNoHook, startingPrice);

        int24 tickLower = -TICK_SPACING0;
        int24 tickUpper = TICK_SPACING0;
        int256 liquidity = 20 ether;

        payable(aliceSwapper).transfer(uint256(liquidity));

        vm.prank(aliceSwapper);
        liqRouter.modifyLiquidity(
            keyNoHook,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidity,
                salt: 0
            }),
            ""
        );
        vm.prank(aliceSwapper);
        liqRouter.modifyLiquidity{value: uint256(liquidity)}(
            ethKeyNoHook,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidity,
                salt: 0
            }),
            ""
        );
        vm.prank(aliceSwapper);
        liqRouter.modifyLiquidity(
            keyNoHook2,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidity,
                salt: 0
            }),
            ""
        );
        vm.prank(aliceSwapper);
        liqRouter.modifyLiquidity(
            keyNoHook3,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidity,
                salt: 0
            }),
            ""
        );
        vm.prank(aliceSwapper);
        liqRouter.modifyLiquidity(
            keyNoHook4,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidity,
                salt: 0
            }),
            ""
        );
        vm.prank(aliceSwapper);
        liqRouter.modifyLiquidity(
            keyNoHook5,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidity,
                salt: 0
            }),
            ""
        );
    }

    function _createSortedCurrencies() internal returns (Currency _currencyA, Currency _currencyB, Currency _currencyC, Currency _currencyD) {
        // Namespace and prefix 0x4444 avoid collisions
        address currencyAA = address((0x000000AA) ^ (0x4444 << 144));
        address currencyBB = address((0x000000BB) ^ (0x4444 << 144));
        address currencyCC = address((0x000000CC) ^ (0x4444 << 144));
        address currencyDD = address((0x000000DD) ^ (0x4444 << 144));

        MockERC20 mockToken = new MockERC20("TEST", "TEST", 18);
        vm.etch(currencyAA, address(mockToken).code);
        vm.etch(currencyBB, address(mockToken).code);
        vm.etch(currencyCC, address(mockToken).code);
        vm.etch(currencyDD, address(mockToken).code);

        _currencyA = Currency.wrap(currencyAA);
        _currencyB = Currency.wrap(currencyBB);
        _currencyC = Currency.wrap(currencyCC);
        _currencyD = Currency.wrap(currencyDD);
    }

    function _createVanillaKeys(address hook) internal returns (PoolKey[] memory vanillaKeys) {
        vanillaKeys = new PoolKey[](5);

        vanillaKeys[0] = PoolKey({
            currency0: currencyA,
            currency1: currencyB,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        vanillaKeys[1] = PoolKey({
            currency0: currencyB,
            currency1: currencyC,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        vanillaKeys[2] = PoolKey({
            currency0: currencyC,
            currency1: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        vanillaKeys[3] = PoolKey({
            currency0: currencyD,
            currency1: currencyA,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });
    }

    function _createNativeVanillaKeys(address hook) internal returns (PoolKey[] memory nativeVanillaKeys) {
        nativeKeys = new PoolKey[](4);
        nativeKeys[0] = PoolKey({
            currency0: nativeCurrency,
            currency1: currencyA,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        nativeKeys[1] = PoolKey({
            currency0: nativeCurrency,
            currency1: currencyB,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        nativeKeys[2] = PoolKey({
            currency0: nativeCurrency,
            currency1: currencyC,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        nativeKeys[3] = PoolKey({
            currency0: nativeCurrency,
            currency1: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });
    }
}
