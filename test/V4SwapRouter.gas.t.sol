// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {PathKey} from "../src/libraries/PathKey.sol";

import {Counter} from "@v4-template/src/Counter.sol";

import {ISignatureTransfer, V4SwapRouter} from "../src/V4SwapRouter.sol";

import {SwapRouterFixtures, Deployers, TestCurrencyBalances} from "./utils/SwapRouterFixtures.sol";
import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {HookData} from "./utils/hooks/HookData.sol";

// Enum for snapshot string
enum TokenType {
    NATIVE,
    ERC20,
    ERC6909
}

contract MultihopTest is SwapRouterFixtures, DeployPermit2 {
    using MockCurrencyLibrary for Currency;

    V4SwapRouter router;
    ISignatureTransfer permit2 = ISignatureTransfer(address(PERMIT2_ADDRESS));

    Counter hook;

    PoolKey[] vanillaPoolKeys;
    PoolKey[] nativePoolKeys;
    PoolKey[] hookedPoolKeys;
    PoolKey[] csmmPoolKeys;

    // Test contract inherits `receive` function through SwapRouterFixtures' Deployers contract

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

        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));
        currencyC.maxApprove(address(router));
        currencyD.maxApprove(address(router));

        // Deploy the hook to an address with the correct flags
        _deployCSMM();
        _deployHookWithData();

        // Define and create all pools with their respective hooks
        PoolKey[] memory _vanillaPoolKeys = _createPoolKeys(address(0));
        _copyArrayToStorage(_vanillaPoolKeys, vanillaPoolKeys);

        PoolKey[] memory _nativePoolKeys = _createNativePoolKeys(address(0));
        _copyArrayToStorage(_nativePoolKeys, nativePoolKeys);

        PoolKey[] memory _hookedPoolKeys = _createPoolKeys(address(hookWithData));
        _copyArrayToStorage(_hookedPoolKeys, hookedPoolKeys);
        PoolKey[] memory _csmmPoolKeys = _createPoolKeys(address(csmm));
        _copyArrayToStorage(_csmmPoolKeys, csmmPoolKeys);

        PoolKey[] memory allPoolKeys =
            _concatPools(vanillaPoolKeys, nativePoolKeys, hookedPoolKeys, csmmPoolKeys);
        _initializePools(allPoolKeys);

        _addLiquidity(vanillaPoolKeys, 10_000e18);
        _addLiquidity(nativePoolKeys, 10_000e18);
        _addLiquidity(hookedPoolKeys, 10_000e18);
        _addLiquidityCSMM(csmmPoolKeys, 1_000e18);
    }

    function test_gas_multi_exactInput() public {
        // Swap Path: A --> B --> C
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
        uint256 amountOutMin = 0.99e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(true, false, TokenType.ERC20, TokenType.ERC20, "vanilla")
        );
    }

    function test_gas_multi_exactInput_nativeInput() public {
        // Swap Path: ETH --> C --> D
        Currency startCurrency = native;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyC,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapExactTokensForTokens{value: amountIn}(
            amountIn, amountOutMin, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(true, false, TokenType.NATIVE, TokenType.ERC20, "nativeInput")
        );
    }

    function test_gas_multi_exactInput_nativeOutput() public {
        // Swap Path: B --> C --> ETH
        Currency startCurrency = currencyB;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyC,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: native,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(true, false, TokenType.ERC20, TokenType.NATIVE, "nativeOutput")
        );
    }

    function test_gas_multi_exactInput_nativeIntermediate() public {
        // Swap Path: A --> ETH --> B
        Currency startCurrency = currencyA;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: native,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: currencyB,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(true, false, TokenType.ERC20, TokenType.ERC20, "nativeIntermediate")
        );
    }

    function test_gas_multi_exactInput_hookData() public {
        // data to be passed to the hook
        uint256 num0 = 111;
        uint256 num1 = 222;

        // Swap Path: C -(hookWithData)-> D -(hookWithData)-> A
        Currency startCurrency = currencyC;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hookWithData)),
            hookData: abi.encode(num0) // C -> D emits num0
        });
        path[1] = PathKey({
            intermediateCurrency: currencyA,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hookWithData)),
            hookData: abi.encode(num1) // D -> A emits num1
        });

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(true, false, TokenType.ERC20, TokenType.ERC20, "hookData")
        );
    }

    function test_gas_multi_exactInput_customCurve() public {
        // Swap Path: A -(vanilla)-> B -(CSMM)-> C
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
            hooks: IHooks(address(csmm)),
            hookData: ZERO_BYTES
        });

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.995e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(true, false, TokenType.ERC20, TokenType.ERC20, "customCurve")
        );
    }

    function test_gas_multi_exactOutput() public {
        // Swap Path: B --> A --> D
        Currency startCurrency = currencyB;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyA,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapTokensForExactTokens(
            amountOut, amountInMax, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(false, false, TokenType.ERC20, TokenType.ERC20, "vanilla")
        );
    }

    function test_gas_multi_exactOutput_nativeInput() public {
        // Swap Path: native --> A --> D
        Currency startCurrency = native;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyA,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18; // 1% slippage tolerance
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapTokensForExactTokens{value: amountInMax}(
            amountOut, amountInMax, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(false, false, TokenType.NATIVE, TokenType.ERC20, "nativeInput")
        );
    }

    function test_gas_multi_exactOutput_nativeIntermediate() public {
        // Swap Path: A --> native --> D
        Currency startCurrency = currencyA;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: native,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });
        path[1] = PathKey({
            intermediateCurrency: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapTokensForExactTokens(
            amountOut, amountInMax, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(false, false, TokenType.ERC20, TokenType.ERC20, "nativeIntermediate")
        );
    }

    function test_gas_multi_exactOutput_nativeOutput() public {
        // Swap Path: A --> B --> native
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
            intermediateCurrency: native,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKLESS,
            hookData: ZERO_BYTES
        });

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapTokensForExactTokens(
            amountOut, amountInMax, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(false, false, TokenType.ERC20, TokenType.NATIVE, "nativeOutput")
        );
    }

    function test_gas_multi_exactOutput_hookData() public {
        // data to be passed to the hook
        uint256 num0 = 333;
        uint256 num1 = 444;

        // Swap Path: A -(hookWithData)-> B -(hookWithData)-> C
        Currency startCurrency = currencyA;
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currencyB,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hookWithData)),
            hookData: abi.encode(num0) // A -> B emits num0
        });
        path[1] = PathKey({
            intermediateCurrency: currencyC,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hookWithData)),
            hookData: abi.encode(num1) // B -> C emits num1
        });

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapTokensForExactTokens(
            amountOut, amountInMax, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(false, false, TokenType.ERC20, TokenType.ERC20, "hookData")
        );
    }

    function test_gas_multi_exactOutput_customCurve() public {
        // Swap Path: A -(vanilla)-> B -(CSMM)-> C
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
            hooks: IHooks(address(csmm)),
            hookData: ZERO_BYTES
        });

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.005e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapTokensForExactTokens(
            amountOut, amountInMax, startCurrency, path, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(false, false, TokenType.ERC20, TokenType.ERC20, "customCurve")
        );
    }

    function test_gas_single_exactInput() public {
        bool zeroForOne = true;
        PoolKey memory poolKey = vanillaPoolKeys[0];

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, zeroForOne, poolKey, ZERO_BYTES, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(true, true, TokenType.ERC20, TokenType.ERC20, "vanilla")
        );
    }

    function test_gas_single_exactInput_nativeInput() public {
        bool zeroForOne = true;
        PoolKey memory poolKey = nativePoolKeys[0];

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapExactTokensForTokens{value: amountIn}(
            amountIn, amountOutMin, zeroForOne, poolKey, ZERO_BYTES, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(true, true, TokenType.NATIVE, TokenType.ERC20, "nativeInput")
        );
    }

    function test_gas_single_exactInput_nativeOutput() public {
        bool zeroForOne = false; // native ether is the output
        PoolKey memory poolKey = nativePoolKeys[0];

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, zeroForOne, poolKey, ZERO_BYTES, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(true, true, TokenType.ERC20, TokenType.NATIVE, "nativeOutput")
        );
    }

    function test_gas_single_exactInput_hookData() public {
        bool zeroForOne = true;
        PoolKey memory poolKey = hookedPoolKeys[0];
        uint256 num0 = 111;

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, zeroForOne, poolKey, abi.encode(num0), recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(true, true, TokenType.ERC20, TokenType.ERC20, "hookData")
        );
    }

    function test_gas_single_exactInput_customCurve() public {
        bool zeroForOne = true;
        PoolKey memory poolKey = csmmPoolKeys[0];

        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapExactTokensForTokens(
            amountIn, amountOutMin, zeroForOne, poolKey, ZERO_BYTES, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(true, true, TokenType.ERC20, TokenType.ERC20, "customCurve")
        );
    }

    function test_gas_single_exactOutput() public {
        bool zeroForOne = true;
        PoolKey memory poolKey = vanillaPoolKeys[0];

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapTokensForExactTokens(
            amountOut, amountInMax, zeroForOne, poolKey, ZERO_BYTES, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(false, true, TokenType.ERC20, TokenType.ERC20, "vanilla")
        );
    }

    function test_gas_single_exactOutput_nativeInput() public {
        bool zeroForOne = true;
        PoolKey memory poolKey = nativePoolKeys[0];

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapTokensForExactTokens{value: amountInMax}(
            amountOut, amountInMax, zeroForOne, poolKey, ZERO_BYTES, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(false, true, TokenType.NATIVE, TokenType.ERC20, "nativeInput")
        );
    }

    function test_gas_single_exactOutput_nativeOutput() public {
        bool zeroForOne = false; // native ether is the output
        PoolKey memory poolKey = nativePoolKeys[0];

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapTokensForExactTokens(
            amountOut, amountInMax, zeroForOne, poolKey, ZERO_BYTES, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(false, true, TokenType.ERC20, TokenType.NATIVE, "nativeOutput")
        );
    }

    function test_gas_single_exactOutput_hookData() public {
        bool zeroForOne = true;
        PoolKey memory poolKey = hookedPoolKeys[0];
        // data to be passed to the hook
        uint256 num0 = 333;

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapTokensForExactTokens(
            amountOut, amountInMax, zeroForOne, poolKey, abi.encode(num0), recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(false, true, TokenType.ERC20, TokenType.ERC20, "hookData")
        );
    }

    function test_gas_single_exactOutput_customCurve() public {
        bool zeroForOne = true;
        PoolKey memory poolKey = csmmPoolKeys[0];

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        address recipient = address(this);
        uint256 deadline = block.timestamp;
        router.swapTokensForExactTokens(
            amountOut, amountInMax, zeroForOne, poolKey, ZERO_BYTES, recipient, deadline
        );
        vm.snapshotGasLastCall(
            _snapshotString(false, true, TokenType.ERC20, TokenType.ERC20, "customCurve")
        );
    }

    function _snapshotString(
        bool exactInput,
        bool singleSwap,
        TokenType inputType,
        TokenType outputType,
        string memory hookInfo
    ) internal pure returns (string memory) {
        string memory inputToken;
        string memory outputToken;
        string memory swapType; // exact input or exact output
        string memory singleOrMulti; // single or multi

        if (inputType == TokenType.NATIVE) {
            inputToken = "ETH";
        } else if (inputType == TokenType.ERC20) {
            inputToken = "ERC20";
        } else if (inputType == TokenType.ERC6909) {
            inputToken = "ERC6909";
        }

        if (outputType == TokenType.NATIVE) {
            outputToken = "ETH";
        } else if (outputType == TokenType.ERC20) {
            outputToken = "ERC20";
        } else if (outputType == TokenType.ERC6909) {
            outputToken = "ERC6909";
        }

        swapType = exactInput ? "exactInput" : "exactOutput";
        singleOrMulti = singleSwap ? "single" : "multi";

        return string.concat(
            swapType, "_", singleOrMulti, "_", inputToken, "_to_", outputToken, "_", hookInfo
        );
    }
}
