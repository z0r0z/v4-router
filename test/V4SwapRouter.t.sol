// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {V4SwapRouter} from "../src/V4SwapRouter.sol";
import {IPoolManager, PoolManager} from "@v4/src/PoolManager.sol";

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "@v4/src/types/Currency.sol";

import {Test} from "@forge/Test.sol";
import {MockERC20} from "@solady/test/utils/mocks/MockERC20.sol";

import {NoOpSwapHook} from "./utils/mocks/hooks/NoOpSwapHook.sol";

import {PoolModifyLiquidityTest} from "@v4/src/test/PoolModifyLiquidityTest.sol";

import {PathKey} from "../src/libraries/PathKey.sol";

import {console} from "forge-std/console.sol";

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
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook, startingPrice);

        keyNoHook2 = PoolKey({
            currency0: Currency.wrap(currency2Addr),
            currency1: Currency.wrap(currency3Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook2, startingPrice);

        keyNoHook3 = PoolKey({
            currency0: Currency.wrap(currency1Addr),
            currency1: Currency.wrap(currency3Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook3, startingPrice);

        keyNoHook4 = PoolKey({
            currency0: Currency.wrap(currency1Addr),
            currency1: Currency.wrap(currency2Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook4, startingPrice);

        keyNoHook5 = PoolKey({
            currency0: Currency.wrap(currency0Addr),
            currency1: Currency.wrap(currency3Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(keyNoHook5, startingPrice);

        ethKeyNoHook = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(currency1Addr),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolManager(manager).initialize(ethKeyNoHook, startingPrice);

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

        console.log("currency0:", currency0Addr);
        console.log("currency1:", currency1Addr);
        console.log("currency2:", currency2Addr);
        console.log("currency3:", currency3Addr);
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

    function test_exactInput_singleSwap() public {
        // keyNoHook.c0 -> keyNoHook.c1
        // currency0 -> currency1
        vm.prank(aliceSwapper);
        router.swap(-0.1 ether, 0, true, keyNoHook, "", aliceSwapper, block.timestamp + 1);
    }

    function test_exactInput_multiSwap() public {
        // keyNoHook.c0 -> keyNoHook.c1 -> keyNoHook3.c1
        // currency0 -> currency1 -> currency3
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: keyNoHook.currency1,
            fee: keyNoHook.fee,
            tickSpacing: keyNoHook.tickSpacing,
            hooks: keyNoHook.hooks,
            hookData: ""
        });
        path[1] = PathKey({
            intermediateCurrency: keyNoHook3.currency1,
            fee: keyNoHook3.fee,
            tickSpacing: keyNoHook3.tickSpacing,
            hooks: keyNoHook3.hooks,
            hookData: ""
        });

        vm.prank(aliceSwapper);
        router.swapExactTokensForTokens(
            0.1 ether, 0, keyNoHook.currency0, path, aliceSwapper, block.timestamp + 1
        );
    }

    function test_exactOutput_singleSwap() public {
        uint256 balanceBefore = MockERC20(currency1Addr).balanceOf(aliceSwapper);

        // Want exactly 0.1 ether of currency1, providing up to 0.15 ether of currency0
        vm.prank(aliceSwapper);
        router.swapTokensForExactTokens(
            0.1 ether, // exact amount out
            0.15 ether, // maximum amount in
            true, // zeroForOne
            keyNoHook, // pool key
            "", // hook data
            aliceSwapper, // recipient
            block.timestamp + 1
        );

        uint256 balanceAfter = MockERC20(currency1Addr).balanceOf(aliceSwapper);
        assertEq(balanceAfter - balanceBefore, 0.1 ether, "Incorrect output amount");
    }

    function test_exactOutput_multiSwap() public {
        uint256 initialBalance0 = MockERC20(currency0Addr).balanceOf(aliceSwapper);
        uint256 initialBalance1 = MockERC20(currency1Addr).balanceOf(aliceSwapper);
        uint256 initialBalance2 = MockERC20(currency2Addr).balanceOf(aliceSwapper);

        // First swap: currency0 -> currency1
        vm.prank(aliceSwapper);
        router.swapTokensForExactTokens(
            0.1 ether, 0.15 ether, true, keyNoHook, "", aliceSwapper, block.timestamp + 1
        );

        uint256 midBalance1 = MockERC20(currency1Addr).balanceOf(aliceSwapper);
        assertEq(midBalance1 - initialBalance1, 0.1 ether, "First swap output incorrect");

        // Second swap: currency1 -> currency2
        vm.prank(aliceSwapper);
        router.swapTokensForExactTokens(
            0.1 ether, 0.15 ether, true, keyNoHook4, "", aliceSwapper, block.timestamp + 1
        );

        uint256 finalBalance2 = MockERC20(currency2Addr).balanceOf(aliceSwapper);
        assertEq(finalBalance2 - initialBalance2, 0.1 ether, "Final output amount incorrect");
    }

    function test_slippageProtection_exactInput() public {
        vm.prank(aliceSwapper);
        vm.expectRevert(); // Should revert due to insufficient output
        router.swapExactTokensForTokens(
            0.1 ether, // input amount
            1 ether, // minimum output (unreasonably high)
            keyNoHook.currency0,
            new PathKey[](0),
            aliceSwapper,
            block.timestamp + 1
        );
    }

    function test_deadline() public {
        vm.prank(aliceSwapper);
        vm.expectRevert(); // Should revert due to expired deadline
        router.swapExactTokensForTokens(
            0.1 ether,
            0,
            keyNoHook.currency0,
            new PathKey[](0),
            aliceSwapper,
            block.timestamp - 1 // Past deadline
        );
    }

    function test_improperPath() public {
        // Setup invalid path (missing intermediate currencies)
        PathKey[] memory path = new PathKey[](2);

        vm.prank(aliceSwapper);
        vm.expectRevert(); // Should revert due to invalid path
        router.swapExactTokensForTokens(
            0.1 ether, 0, keyNoHook.currency0, path, aliceSwapper, block.timestamp + 1
        );
    }

    function test_zeroAmount() public {
        vm.prank(aliceSwapper);
        vm.expectRevert(); // Should revert due to zero amount
        router.swapExactTokensForTokens(
            0, // zero amount
            0,
            keyNoHook.currency0,
            new PathKey[](0),
            aliceSwapper,
            block.timestamp + 1
        );
    }

    function test_insufficientBalance() public {
        uint256 hugeAmount = 1000 ether;

        vm.prank(aliceSwapper);
        vm.expectRevert(); // Should revert due to insufficient balance
        router.swapExactTokensForTokens(
            hugeAmount, 0, keyNoHook.currency0, new PathKey[](0), aliceSwapper, block.timestamp + 1
        );
    }

    function test_exactInput_zeroForOne() public {
        uint256 balanceBefore = MockERC20(currency1Addr).balanceOf(aliceSwapper);

        // Provide 0.1 ether of currency0, expect at least 0.09 ether of currency1
        vm.prank(aliceSwapper);
        router.swapExactTokensForTokens(
            0.1 ether, // exact amount in
            0.09 ether, // minimum amount out
            true, // zeroForOne
            keyNoHook, // pool key
            "", // hook data
            aliceSwapper, // recipient
            block.timestamp + 1
        );

        uint256 balanceAfter = MockERC20(currency1Addr).balanceOf(aliceSwapper);
        assertGt(balanceAfter, balanceBefore, "Balance should increase");
        assertGe(balanceAfter - balanceBefore, 0.09 ether, "Insufficient output amount");
    }

    function test_exactInput_oneForZero() public {
        uint256 balanceBefore = MockERC20(currency0Addr).balanceOf(aliceSwapper);

        // Provide 0.1 ether of currency1, expect at least 0.09 ether of currency0
        vm.prank(aliceSwapper);
        router.swapExactTokensForTokens(
            0.1 ether, // exact amount in
            0.09 ether, // minimum amount out
            false, // oneForZero
            keyNoHook, // pool key
            "", // hook data
            aliceSwapper, // recipient
            block.timestamp + 1
        );

        uint256 balanceAfter = MockERC20(currency0Addr).balanceOf(aliceSwapper);
        assertGt(balanceAfter, balanceBefore, "Balance should increase");
        assertGe(balanceAfter - balanceBefore, 0.09 ether, "Insufficient output amount");
    }

    function test_exactOutput_oneForZero() public {
        uint256 balanceBefore = MockERC20(currency0Addr).balanceOf(aliceSwapper);

        // Want exactly 0.1 ether of currency0, providing up to 0.15 ether of currency1
        vm.prank(aliceSwapper);
        router.swapTokensForExactTokens(
            0.1 ether, // exact amount out
            0.15 ether, // maximum amount in
            false, // oneForZero
            keyNoHook, // pool key
            "", // hook data
            aliceSwapper, // recipient
            block.timestamp + 1
        );

        uint256 balanceAfter = MockERC20(currency0Addr).balanceOf(aliceSwapper);
        assertEq(balanceAfter - balanceBefore, 0.1 ether, "Incorrect output amount");
    }

    function test_revertDeadlinePassed() public {
        vm.warp(100); // Set current timestamp

        vm.prank(aliceSwapper);
        vm.expectRevert(abi.encodeWithSignature("DeadlinePassed(uint256)", 99));
        router.swapExactTokensForTokens(
            0.1 ether, // exact amount in
            0.09 ether, // minimum amount out
            true, // zeroForOne
            keyNoHook, // pool key
            "", // hook data
            aliceSwapper, // recipient
            99 // deadline in the past
        );
    }

    function test_revertInsufficientOutputAmount() public {
        vm.prank(aliceSwapper);
        vm.expectRevert(abi.encodeWithSignature("SlippageExceeded()"));
        router.swapExactTokensForTokens(
            0.1 ether, // exact amount in
            1000 ether, // unreasonably high minimum output
            true, // zeroForOne
            keyNoHook, // pool key
            "", // hook data
            aliceSwapper, // recipient
            block.timestamp + 1
        );
    }
}
