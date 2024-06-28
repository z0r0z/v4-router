// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {V4SwapRouter} from "../src/V4SwapRouter.sol";
import {IPoolManager, PoolManager} from "@v4/src/PoolManager.sol";

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "@v4/src/types/Currency.sol";

import {Test} from "../lib/forge-std/src/Test.sol";
import {MockERC20} from "@solady/test/utils/mocks/MockERC20.sol";

import {PoolModifyLiquidityTest} from "@v4/src/test/PoolModifyLiquidityTest.sol";

contract TesterTest is Test {
    address internal aliceSwapper;

    address internal manager;
    V4SwapRouter internal router;

    PoolModifyLiquidityTest internal liqRouter;

    address internal currency0Addr;
    address internal currency1Addr;

    // Min tick for full range with tick spacing of 60.
    int24 internal constant MIN_TICK = -887220;
    // Max tick for full range with tick spacing of 60.
    int24 internal constant MAX_TICK = -MIN_TICK;

    // Vanilla pool (no hook).
    PoolKey internal keyNoHook;

    // ETH based pool (no hook).
    PoolKey internal ethKeyNoHook;

    // floor(sqrt(1) * 2^96)
    uint160 constant startingPrice = 79228162514264337593543950336;

    struct CallbackData {
        PoolKey key;
        IPoolManager.SwapParams params;
        bytes hookData;
    }

    function setUp() public payable {
        aliceSwapper = makeAddr("alice");
        payable(aliceSwapper).transfer(1 ether);

        manager = address(new PoolManager(500000));
        router = new V4SwapRouter(IPoolManager(manager));

        liqRouter = new PoolModifyLiquidityTest(IPoolManager(manager));

        currency0Addr = address(new MockERC20("Test0", "Test0", 18));
        currency1Addr = address(new MockERC20("Test1", "Test1", 18));

        // Sort in appropriate token order.
        if (currency0Addr > currency1Addr) {
            (currency0Addr, currency1Addr) = (currency1Addr, currency0Addr);
        }

        MockERC20(currency0Addr).mint(aliceSwapper, 100 ether);
        MockERC20(currency1Addr).mint(aliceSwapper, 100 ether);

        vm.prank(aliceSwapper);
        MockERC20(currency0Addr).approve(address(router), type(uint256).max);
        vm.prank(aliceSwapper);
        MockERC20(currency1Addr).approve(address(router), type(uint256).max);

        vm.prank(aliceSwapper);
        MockERC20(currency0Addr).approve(address(liqRouter), type(uint256).max);
        vm.prank(aliceSwapper);
        MockERC20(currency1Addr).approve(address(liqRouter), type(uint256).max);

        keyNoHook = PoolKey({
            currency0: Currency.wrap(currency0Addr),
            currency1: Currency.wrap(currency1Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook, startingPrice, "");

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
    }

    function testRouterDeployGas() public payable {
        router = new V4SwapRouter(IPoolManager(manager));
    }

    function testSingleSwapExactInput() public payable {
        vm.prank(aliceSwapper);
        router.swapSingle(keyNoHook, IPoolManager.SwapParams(true, -(0.1 ether), 0), "");
    }

    function testSingleSwapExactOutput() public payable {
        vm.prank(aliceSwapper);
        router.swapSingle(keyNoHook, IPoolManager.SwapParams(true, 0.1 ether, 0), "");
    }
}
