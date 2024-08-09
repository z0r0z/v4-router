// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Key, Swap, V4SwapRouter} from "../src/V4SwapRouter.sol";
import {IPoolManager, PoolManager} from "@v4/src/PoolManager.sol";

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "@v4/src/types/Currency.sol";

import {Test} from "../lib/forge-std/src/Test.sol";
import {MockERC20} from "@solady/test/utils/mocks/MockERC20.sol";

import {NoOpSwapHook} from "./utils/mocks/hooks/NoOpSwapHook.sol";

import {PoolModifyLiquidityTest} from "@v4/src/test/PoolModifyLiquidityTest.sol";

contract V4SwapRouterTest is Test {
    address internal aliceSwapper;

    address internal manager;
    V4SwapRouter internal router;

    PoolModifyLiquidityTest internal liqRouter;

    address internal currency0Addr;
    address internal currency1Addr;
    address internal currency2Addr;
    address internal currency3Addr;

    // Min tick for full range with tick spacing of 60.
    int24 internal constant MIN_TICK = -887220;
    // Max tick for full range with tick spacing of 60.
    int24 internal constant MAX_TICK = -MIN_TICK;

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
    uint160 constant startingPrice = 79228162514264337593543950336;

    function setUp() public payable {
        aliceSwapper = makeAddr("alice");
        payable(aliceSwapper).transfer(1 ether);

        manager = address(new PoolManager(500000));
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
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook, startingPrice, "");

        keyNoHook2 = PoolKey({
            currency0: Currency.wrap(currency2Addr),
            currency1: Currency.wrap(currency3Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook2, startingPrice, "");

        keyNoHook3 = PoolKey({
            currency0: Currency.wrap(currency1Addr),
            currency1: Currency.wrap(currency3Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook3, startingPrice, "");

        keyNoHook4 = PoolKey({
            currency0: Currency.wrap(currency1Addr),
            currency1: Currency.wrap(currency2Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook4, startingPrice, "");

        keyNoHook5 = PoolKey({
            currency0: Currency.wrap(currency0Addr),
            currency1: Currency.wrap(currency3Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook5, startingPrice, "");

        /*noOpSwapHook = IHooks(address(new NoOpSwapHook(IPoolManager(manager))));

        keyNoOpSwapHook = PoolKey({
            currency0: Currency.wrap(currency0Addr),
            currency1: Currency.wrap(currency1Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: noOpSwapHook
        });

        PoolManager(manager).initialize(keyNoOpSwapHook, startingPrice, "");*/

        ethKeyNoHook = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(currency1Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(ethKeyNoHook, startingPrice, "");

        int24 tickLower = -600;
        int24 tickUpper = 600;
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
        /*vm.prank(aliceSwapper);
        liqRouter.modifyLiquidity(
            keyNoOpSwapHook,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidity,
                salt: 0
            }),
            ""
        );*/
    }

    function _sortAddresses(address[] memory addresses) internal pure returns (address[] memory) {
        for (uint256 i; i < addresses.length; i++) {
            for (uint256 j = i + 1; j < addresses.length; j++) {
                if (uint160(addresses[i]) > uint160(addresses[j])) {
                    address temp = addresses[i];
                    addresses[i] = addresses[j];
                    addresses[j] = temp;
                }
            }
        }
        return addresses;
    }

    function testRouterDeployGas() public payable {
        router = new V4SwapRouter(IPoolManager(manager));
    }

    function testSingleSwapExactInputZeroForOne() public payable {
        Key[] memory keys = new Key[](1);
        keys[0].key = keyNoHook;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook.currency0; // zeroForOne.
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap);
    }

    function testSingleSwapExactInputZeroForOneNative() public payable {
        Key[] memory keys = new Key[](1);
        keys[0].key = ethKeyNoHook;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = ethKeyNoHook.currency0; // zeroForOne (ETH).
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap{value: 0.1 ether}(swap);
    }

    function testSingleSwapExactInputOneForZero() public payable {
        Key[] memory keys = new Key[](1);
        keys[0].key = keyNoHook;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook.currency1;
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap);
    }

    function testSingleSwapExactInputOneForZeroNative() public payable {
        Key[] memory keys = new Key[](1);
        keys[0].key = ethKeyNoHook;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = ethKeyNoHook.currency1;
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap);
    }

    function testSingleSwapExactOutputZeroForOne() public payable {
        Key[] memory keys = new Key[](1);
        keys[0].key = keyNoHook;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook.currency0; // zeroForOne.
        swap.amountSpecified = 0.1 ether;
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap);
    }

    function testSingleSwapExactOutputOneForZero() public payable {
        Key[] memory keys = new Key[](1);
        keys[0].key = keyNoHook;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook.currency1;
        swap.amountSpecified = 0.1 ether;
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap);
    }

    function testDoubleSwapSame() public payable {
        Key[] memory keys = new Key[](2);
        keys[0].key = keyNoHook;
        keys[1].key = keyNoHook;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook.currency0; // zeroForOne.
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap);
    }

    function testTripleSwapSame() public payable {
        Key[] memory keys = new Key[](3);
        keys[0].key = keyNoHook;
        keys[1].key = keyNoHook;
        keys[2].key = keyNoHook;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook.currency0; // zeroForOne.
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap);
    }

    function testMultihopSwapExactInputTwoHops() public payable {
        Key[] memory keys = new Key[](2);
        keys[0].key = keyNoHook;
        keys[1].key = keyNoHook3;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook.currency0; // zeroForOne.
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap); // 0 for 3.
    }

    function testMultihopSwapExactInputTwoHopsNative() public payable {
        Key[] memory keys = new Key[](2);
        keys[0].key = ethKeyNoHook;
        keys[1].key = keyNoHook3;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = ethKeyNoHook.currency0; // zeroForOne (ETH).
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap{value: 0.1 ether}(swap); // 0 for 3.
    }

    function testMultihopSwapExactInputTwoHopAlt() public payable {
        Key[] memory keys = new Key[](2);
        keys[0].key = keyNoHook;
        keys[1].key = keyNoHook5;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook.currency1;
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap); // 1 for 3.
    }

    function testMultihopSwapExactOutputTwoHops() public payable {
        Key[] memory keys = new Key[](2);
        keys[0].key = keyNoHook;
        keys[1].key = keyNoHook3;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook.currency0; // zeroForOne.
        swap.amountSpecified = 0.1 ether;
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap); // 0 for 3.
    }

    function testMultihopSwapExactOutputTwoHopsAlt() public payable {
        Key[] memory keys = new Key[](2);
        keys[0].key = keyNoHook;
        keys[1].key = keyNoHook5;
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook.currency1;
        swap.amountSpecified = 0.1 ether;
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap); // 1 for 3.
    }

    function testMultihopSwapExactInputThreeHops() public payable {
        Key[] memory keys = new Key[](3);
        keys[0].key = keyNoHook; // 0 for 1.
        keys[1].key = keyNoHook4; // 1 for 2.
        keys[2].key = keyNoHook2; // 2 for 3.
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook.currency0; // zeroForOne.
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap); // 0 for 3.
    }

    function testMultihopSwapExactInputThreeHopsNative() public payable {
        Key[] memory keys = new Key[](3);
        keys[0].key = ethKeyNoHook; // 0 for 1.
        keys[1].key = keyNoHook4; // 1 for 2.
        keys[2].key = keyNoHook2; // 2 for 3.
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = ethKeyNoHook.currency0; // zeroForOne (ETH).
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap{value: 0.1 ether}(swap); // 0 for 3.
    }

    function testMultihopSwapExactInputTwoHopsNativeOutput() public payable {
        Key[] memory keys = new Key[](2);
        keys[0].key = keyNoHook4; // 2 for 1.
        keys[1].key = ethKeyNoHook; // 1 for 0.
        Swap memory swap;
        swap.receiver = aliceSwapper;
        swap.fromCurrency = keyNoHook4.currency1;
        swap.amountSpecified = -(0.1 ether);
        swap.keys = keys;
        vm.prank(aliceSwapper);
        router.swap(swap); // 2 for 0 (ETH).
    }
}
