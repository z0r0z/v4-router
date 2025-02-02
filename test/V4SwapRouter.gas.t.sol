// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.26;

// import {Hooks} from "@v4/src/libraries/Hooks.sol";
// import {PoolKey} from "@v4/src/types/PoolKey.sol";
// import {Currency} from "@v4/src/types/Currency.sol";
// import {IERC20Minimal} from "@v4/src/interfaces/external/IERC20Minimal.sol";

// import {Counter} from "@v4-template/src/Counter.sol";
// import {HookMiner} from "@v4-template/test/utils/HookMiner.sol";
// import {CustomCurveHook} from "./utils/hooks/CustomCurveHook.sol";
// import {BaseHook} from "@v4-periphery/src/base/hooks/BaseHook.sol";

// import {V4SwapRouter} from "../src/V4SwapRouter.sol";

// import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";
// import {SwapRouterFixtures, Deployers} from "./utils/SwapRouterFixtures.sol";

// contract RouterGasTest is SwapRouterFixtures {
//     using MockCurrencyLibrary for Currency;

//     V4SwapRouter router;
//     Counter hook;
//     CustomCurveHook hookCsmm;

//     PoolKey[] vanillaPoolKeys;
//     PoolKey[] nativePoolKeys;
//     PoolKey[] hookedPoolKeys;
//     PoolKey[] csmmPoolKeys;

//     function setUp() public payable {
//         // Deploy v4 contracts
//         Deployers.deployFreshManagerAndRouters();
//         router = new V4SwapRouter(manager);

//         // Create currencies
//         (currencyA, currencyB, currencyC, currencyD) = _createSortedCurrencies();

//         currencyA.mint(address(this), 10_000e18);
//         currencyB.mint(address(this), 10_000e18);
//         currencyC.mint(address(this), 10_000e18);
//         currencyD.mint(address(this), 10_000e18);

//         currencyA.maxApprove(address(modifyLiquidityRouter));
//         currencyB.maxApprove(address(modifyLiquidityRouter));
//         currencyC.maxApprove(address(modifyLiquidityRouter));
//         currencyD.maxApprove(address(modifyLiquidityRouter));

//         // Deploy Counter hook with correct flags
//         address flags = address(
//             uint160(
//                 Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
//                     | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
//             ) ^ (0x4444 << 144)
//         ); // Same namespace as in Counter test

//         bytes memory constructorArgs = abi.encode(manager);
//         deployCodeTo("Counter.sol:Counter", constructorArgs, flags);
//         hook = Counter(flags);

//         // Deploy CustomCurveHook with correct flags
//         address csmmFlags =
//             address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x5555 << 144));
//         bytes memory csmmConstructorArgs = abi.encode(manager);
//         deployCodeTo("CustomCurveHook.sol:CustomCurveHook", csmmConstructorArgs, csmmFlags);
//         hookCsmm = CustomCurveHook(csmmFlags);

//         // Define and create all pools with their respective hooks

//         // Vanilla pool - no hook
//         PoolKey[] memory _vanillaPoolKeys = _createPoolKeys(address(0));
//         _copyArrayToStorage(_vanillaPoolKeys, vanillaPoolKeys);

//         // Native ETH pool
//         PoolKey[] memory _nativePoolKeys = _createNativePoolKeys(address(0));
//         _copyArrayToStorage(_nativePoolKeys, nativePoolKeys);

//         // Counter hook for regular hook
//         PoolKey[] memory _hookedPoolKeys = _createPoolKeys(address(hook));
//         _copyArrayToStorage(_hookedPoolKeys, hookedPoolKeys);

//         // Simple curve hook from utils
//         PoolKey[] memory _csmmPoolKeys = _createPoolKeys(address(hookCsmm));
//         _copyArrayToStorage(_csmmPoolKeys, csmmPoolKeys);

//         PoolKey[] memory allPoolKeys =
//             _concatPools(vanillaPoolKeys, nativePoolKeys, hookedPoolKeys, csmmPoolKeys);
//         _initializePools(allPoolKeys);
//         _addLiquidity(allPoolKeys, 10_000e18);
//     }

//     function test_gas_single_exactInput() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));

//         router.swapExactTokensForTokens(
//             0.1 ether, 0.09 ether, true, vanillaPoolKeys[0], "", address(this), block.timestamp + 1
//         );
//     }

//     function test_gas_single_exactInput_native() public {
//         uint256 initialBalance = address(this).balance;

//         router.swapExactTokensForTokens{value: 0.1 ether}(
//             0.1 ether, // exact ETH input
//             0.09 ether, // minimum token output
//             true, // zeroForOne (ETH -> token)
//             nativePoolKeys[0], // pool with ETH as currency0
//             "", // no hook data
//             address(this), // recipient
//             block.timestamp + 1
//         );

//         // Verify ETH was spent
//         assertEq(
//             address(this).balance,
//             initialBalance - 0.1 ether,
//             "ETH balance should decrease by exact input"
//         );

//         // Verify token received
//         Currency tokenOut = nativePoolKeys[0].currency1;
//         uint256 tokenBalance = IERC20Minimal(Currency.unwrap(tokenOut)).balanceOf(address(this));
//         assertTrue(tokenBalance >= 0.09 ether, "Should receive at least minimum token amount");
//     }

//     function test_gas_single_exactInput_hooked() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));

//         assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 0);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 0);

//         router.swapExactTokensForTokens(
//             0.1 ether, 0.09 ether, true, hookedPoolKeys[0], "", address(this), block.timestamp + 1
//         );

//         assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 1);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 1);
//     }

//     function test_gas_single_exactInput_customCurve() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));

//         router.swapExactTokensForTokens(
//             0.1 ether, 0.09 ether, true, csmmPoolKeys[0], "", address(this), block.timestamp + 1
//         );
//     }

//     function test_gas_multi_exactInput() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));
//         currencyB.maxApprove(address(router));

//         router.swapExactTokensForTokens(
//             0.1 ether, 0.09 ether, true, vanillaPoolKeys[0], "", address(this), block.timestamp + 1
//         );

//         router.swapExactTokensForTokens(
//             0.09 ether, 0.08 ether, true, vanillaPoolKeys[1], "", address(this), block.timestamp + 1
//         );
//     }

//     function test_gas_multi_exactInput_native() public {
//         uint256 initialBalance = address(this).balance;

//         // First swap: ETH -> Token A
//         router.swapExactTokensForTokens{value: 0.1 ether}(
//             0.1 ether, // exact ETH input
//             0.09 ether, // minimum token output
//             true, // zeroForOne
//             nativePoolKeys[0],
//             "",
//             address(this),
//             block.timestamp + 1
//         );

//         // Get intermediate token balance and approve
//         Currency tokenA = nativePoolKeys[0].currency1;
//         uint256 tokenAAmount = IERC20Minimal(Currency.unwrap(tokenA)).balanceOf(address(this));
//         IERC20Minimal(Currency.unwrap(tokenA)).approve(address(router), type(uint256).max);

//         // Second swap: Token A -> Token B (non-native pool)
//         router.swapExactTokensForTokens(
//             tokenAAmount, // exact token input
//             0.08 ether, // minimum output
//             true, // zeroForOne
//             vanillaPoolKeys[0], // Use vanilla pool instead of native pool for second swap
//             "",
//             address(this),
//             block.timestamp + 1
//         );

//         // Verify ETH was spent
//         assertEq(
//             address(this).balance,
//             initialBalance - 0.1 ether,
//             "ETH balance should decrease by exact input"
//         );

//         // Verify final token received
//         Currency tokenB = vanillaPoolKeys[0].currency1;
//         uint256 tokenBBalance = IERC20Minimal(Currency.unwrap(tokenB)).balanceOf(address(this));
//         assertTrue(tokenBBalance >= 0.08 ether, "Should receive at least minimum token amount");
//     }

//     function test_gas_multi_exactInput_hooked() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));
//         currencyB.maxApprove(address(router));

//         assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 0);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 0);
//         assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 0);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 0);

//         router.swapExactTokensForTokens(
//             0.1 ether, 0.09 ether, true, hookedPoolKeys[0], "", address(this), block.timestamp + 1
//         );

//         router.swapExactTokensForTokens(
//             0.09 ether, 0.08 ether, true, hookedPoolKeys[1], "", address(this), block.timestamp + 1
//         );

//         assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 1);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 1);
//         assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 1);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 1);
//     }

//     function test_gas_multi_exactInput_customCurve() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));
//         currencyB.maxApprove(address(router));

//         router.swapExactTokensForTokens(
//             0.1 ether, 0.09 ether, true, csmmPoolKeys[0], "", address(this), block.timestamp + 1
//         );

//         router.swapExactTokensForTokens(
//             0.09 ether, 0.08 ether, true, csmmPoolKeys[1], "", address(this), block.timestamp + 1
//         );
//     }

//     function test_gas_single_exactOutput() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));

//         router.swapTokensForExactTokens(
//             0.1 ether, // exact amount out
//             0.15 ether, // maximum amount in
//             true, // zeroForOne
//             vanillaPoolKeys[0], // standard pool without hooks
//             "", // no hook data
//             address(this), // recipient
//             block.timestamp + 1
//         );
//     }

//     function test_gas_single_exactOutput_native() public {
//         uint256 initialBalance = address(this).balance;

//         // Approve token for input
//         Currency tokenIn = nativePoolKeys[0].currency1;
//         IERC20Minimal(Currency.unwrap(tokenIn)).approve(address(router), type(uint256).max);

//         // Native token as output, token as input
//         router.swapTokensForExactTokens(
//             0.1 ether, // exact ETH output wanted
//             0.15 ether, // maximum token input
//             false, // !zeroForOne (token -> ETH)
//             nativePoolKeys[0],
//             "",
//             address(this),
//             block.timestamp + 1
//         );

//         // Verify ETH received
//         assertEq(
//             address(this).balance - initialBalance, 0.1 ether, "Should receive exact ETH amount"
//         );
//     }

//     function test_gas_single_exactOutput_hooked() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));

//         // Check initial counts using pool key directly
//         assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 0);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 0);

//         router.swapTokensForExactTokens(
//             0.1 ether, // exact amount out
//             0.15 ether, // maximum amount in
//             true, // zeroForOne
//             hookedPoolKeys[0], // pool with Counter hook
//             "", // no hook data
//             address(this), // recipient
//             block.timestamp + 1
//         );

//         // Verify hook interactions using pool key directly
//         assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 1);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 1);
//     }

//     function test_gas_single_exactOutput_customCurve() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));

//         router.swapTokensForExactTokens(
//             0.1 ether, 0.15 ether, true, csmmPoolKeys[0], "", address(this), block.timestamp + 1
//         );
//     }

//     function test_gas_multi_exactOutput() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));
//         currencyB.maxApprove(address(router));

//         // Second swap (B->C)
//         router.swapTokensForExactTokens(
//             0.1 ether, // exact amount of C wanted
//             0.15 ether, // maximum B to spend
//             true,
//             vanillaPoolKeys[1],
//             "",
//             address(this),
//             block.timestamp + 1
//         );

//         // First swap (A->B)
//         router.swapTokensForExactTokens(
//             0.15 ether, // exact amount of B needed for second swap
//             0.2 ether, // maximum A to spend
//             true,
//             vanillaPoolKeys[0],
//             "",
//             address(this),
//             block.timestamp + 1
//         );
//     }

//     function test_gas_multi_exactOutput_native() public {
//         uint256 initialBalance = address(this).balance;

//         // Approve tokens for input
//         Currency tokenA = vanillaPoolKeys[0].currency0;
//         Currency tokenB = vanillaPoolKeys[0].currency1;
//         IERC20Minimal(Currency.unwrap(tokenA)).approve(address(router), type(uint256).max);
//         IERC20Minimal(Currency.unwrap(tokenB)).approve(address(router), type(uint256).max);

//         // First swap: TokenA -> TokenB
//         router.swapTokensForExactTokens(
//             0.15 ether, // exact token output
//             0.2 ether, // maximum input
//             true, // zeroForOne
//             vanillaPoolKeys[0],
//             "",
//             address(this),
//             block.timestamp + 1
//         );

//         // Second swap: TokenB -> ETH
//         router.swapTokensForExactTokens(
//             0.1 ether, // exact ETH output
//             0.15 ether, // maximum token input
//             false, // !zeroForOne
//             nativePoolKeys[0],
//             "",
//             address(this),
//             block.timestamp + 1
//         );

//         // Verify ETH received
//         assertEq(
//             address(this).balance - initialBalance, 0.1 ether, "Should receive exact ETH amount"
//         );
//     }

//     function test_gas_multi_exactOutput_hooked() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));
//         currencyB.maxApprove(address(router));

//         assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 0);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 0);
//         assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 0);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 0);

//         router.swapTokensForExactTokens(
//             0.1 ether, 0.15 ether, true, hookedPoolKeys[1], "", address(this), block.timestamp + 1
//         );

//         router.swapTokensForExactTokens(
//             0.15 ether, 0.2 ether, true, hookedPoolKeys[0], "", address(this), block.timestamp + 1
//         );

//         assertEq(hook.beforeSwapCount(hookedPoolKeys[0].toId()), 1);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[0].toId()), 1);
//         assertEq(hook.beforeSwapCount(hookedPoolKeys[1].toId()), 1);
//         assertEq(hook.afterSwapCount(hookedPoolKeys[1].toId()), 1);
//     }

//     function test_gas_multi_exactOutput_customCurve() public {
//         currencyA.mint(address(this), 1 ether);
//         currencyA.maxApprove(address(router));
//         currencyB.maxApprove(address(router));

//         router.swapTokensForExactTokens(
//             0.1 ether, 0.15 ether, true, csmmPoolKeys[1], "", address(this), block.timestamp + 1
//         );

//         router.swapTokensForExactTokens(
//             0.15 ether, 0.2 ether, true, csmmPoolKeys[0], "", address(this), block.timestamp + 1
//         );
//     }
// }
