// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

// Pool helpers.
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {PoolManager} from "@v4/src/PoolManager.sol";
import {Currency, CurrencyLibrary} from "@v4/src/types/Currency.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {TickMath} from "@v4/src/libraries/TickMath.sol";

// Test helpers.
import {Test} from "../lib/forge-std/src/Test.sol";
import {MockERC20} from "@solady/test/utils/mocks/MockERC20.sol";

// Router.
import {SwapHookRouter} from "../src/SwapHookRouter.sol";

// Hooks.
import {SenderHook} from "./utils/mocks/hooks/SenderHook.sol";

contract SwapHookRouterTest is Test {
    using CurrencyLibrary for Currency;

    address aliceSwapper;
    SwapHookRouter internal router;
    PoolManager internal manager;
    address internal currency0Addr;
    address internal currency1Addr;

    address internal senderHook;

    function setUp() public payable {
        aliceSwapper = makeAddr("alice");
        payable(aliceSwapper).transfer(1 ether);

        manager = new PoolManager(500000);
        router = new SwapHookRouter(manager);

        //senderHook = address(new SenderHook(manager));

        currency0Addr = address(new MockERC20("Test0", "Test0", 18));
        currency1Addr = address(new MockERC20("Test1", "Test1", 18));

        if (currency0Addr > currency1Addr) {
            (currency0Addr, currency1Addr) = (currency1Addr, currency0Addr);
        }

        MockERC20(currency0Addr).mint(aliceSwapper, 100 ether);
        MockERC20(currency1Addr).mint(aliceSwapper, 100 ether);
        vm.prank(aliceSwapper);
        MockERC20(currency0Addr).approve(address(router), type(uint256).max);
        vm.prank(aliceSwapper);
        MockERC20(currency1Addr).approve(address(router), type(uint256).max);
    }

    function testDeployGas() public payable {
        router = new SwapHookRouter(manager);
    }

    // TEST INIT

    function testInitHooklessPool() public payable returns (PoolKey memory pool) {
        uint24 swapFee = 500; // 0.05% fee tier
        int24 tickSpacing = 10;

        // floor(sqrt(1) * 2^96)
        uint160 startingPrice = 79228162514264337593543950336;

        // hookless pool doesnt expect any initialization data
        bytes memory hookData = new bytes(0);

        pool = PoolKey({
            currency0: Currency.wrap(currency0Addr),
            currency1: Currency.wrap(currency1Addr),
            fee: swapFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0x0)) // !!! Hookless pool is address(0x0)
        });

        manager.initialize(pool, startingPrice, hookData);
    }

    function testInitAccessRestrictedHookPool() public payable returns (PoolKey memory pool) {
        uint24 swapFee = 500; // 0.05% fee tier
        int24 tickSpacing = 10;

        // floor(sqrt(1) * 2^96)
        uint160 startingPrice = 79228162514264337593543950336;

        // Assume the custom hook requires a sender-lock when initializing it
        bytes memory hookData = abi.encode(aliceSwapper);

        pool = PoolKey({
            currency0: Currency.wrap(currency0Addr),
            currency1: Currency.wrap(currency1Addr),
            fee: swapFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0x0))
        });

        manager.initialize(pool, startingPrice, hookData);
    }

    // HELPERS

    function createRandomSqrtPriceX96(int24 tickSpacing, int256 seed)
        internal
        pure
        returns (uint160)
    {
        int256 min = int256(TickMath.minUsableTick(tickSpacing));
        int256 max = int256(TickMath.maxUsableTick(tickSpacing));
        int256 randomTick = bound(seed, min + 1, max - 1);
        return TickMath.getSqrtPriceAtTick(int24(randomTick));
    }

    function initPools(uint24 fee, int24 tickSpacing, int256 sqrtPriceX96seed)
        internal
        returns (PoolKey memory key_, uint160 sqrtPriceX96)
    {
        fee = uint24(bound(fee, 0, 999999));
        tickSpacing = int24(bound(tickSpacing, 1, 16383));

        sqrtPriceX96 = createRandomSqrtPriceX96(tickSpacing, sqrtPriceX96seed);

        key_ = PoolKey(
            Currency.wrap(currency0Addr),
            Currency.wrap(currency1Addr),
            fee,
            tickSpacing,
            IHooks(address(0))
        );
        manager.initialize(key_, sqrtPriceX96, "");
    }
}
