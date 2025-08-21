// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {PathKey} from "../src/libraries/PathKey.sol";
import {IERC20Minimal} from "@v4/src/interfaces/external/IERC20Minimal.sol";

import {Counter} from "@v4-template/src/Counter.sol";
import {BaseHook} from "@v4-periphery/src/utils/BaseHook.sol";

import {UniswapV4Router04} from "../src/UniswapV4Router04.sol";

import {
    SwapRouterFixtures,
    Deployers,
    TestCurrencyBalances,
    InputOutputBalances
} from "./utils/SwapRouterFixtures.sol";
import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";
import {HookData} from "./utils/hooks/HookData.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {BaseData, PermitPayload, SwapFlags} from "../src/base/BaseSwapRouter.sol";
import "permit2/src/interfaces/IPermit2.sol";

contract UniswapV4Router04Permit2Test is SwapRouterFixtures {
    using MockCurrencyLibrary for Currency;

    UniswapV4Router04 router;

    Counter hook;

    address alice;
    uint256 alicePK;

    PoolKey[] vanillaPoolKeys;
    PoolKey[] nativePoolKeys;
    PoolKey[] hookedPoolKeys;
    PoolKey[] csmmPoolKeys;

    // Test contract inherits `receive` function through SwapRouterFixtures' Deployers contract

    function setUp() public payable {
        (alice, alicePK) = makeAddrAndKey("ALICE");
        // Deploy v4 contracts
        Deployers.deployFreshManagerAndRouters();
        DeployPermit2.deployPermit2();
        router = new UniswapV4Router04(manager, permit2);

        // Create currencies
        (currencyA, currencyB, currencyC, currencyD) = _createSortedCurrencies();

        currencyA.mint(address(this), 10_000e18);
        currencyB.mint(address(this), 10_000e18);
        currencyC.mint(address(this), 10_000e18);
        currencyD.mint(address(this), 10_000e18);
        currencyA.mint(alice, 10_000e18);
        currencyB.mint(alice, 10_000e18);
        currencyC.mint(alice, 10_000e18);
        currencyD.mint(alice, 10_000e18);

        currencyA.maxApprove(address(modifyLiquidityRouter));
        currencyB.maxApprove(address(modifyLiquidityRouter));
        currencyC.maxApprove(address(modifyLiquidityRouter));
        currencyD.maxApprove(address(modifyLiquidityRouter));

        currencyA.maxApprove(address(router));
        currencyB.maxApprove(address(router));
        currencyC.maxApprove(address(router));
        currencyD.maxApprove(address(router));

        vm.startPrank(alice);
        currencyA.maxApprove(address(permit2));
        currencyB.maxApprove(address(permit2));
        currencyC.maxApprove(address(permit2));
        currencyD.maxApprove(address(permit2));
        vm.stopPrank();

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

    function test_encoded_single_permit2_exactInput(address receiver, bool zeroForOne, uint256 seed)
        public
    {
        vm.assume(
            receiver != address(manager) && receiver != address(this) && receiver != address(alice)
        );
        // randomly select a pool
        PoolKey memory poolKey = vanillaPoolKeys[seed % vanillaPoolKeys.length];

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(alice, inputCurrency, outputCurrency);
        InputOutputBalances memory receiverBefore =
            inputOutputBalances(receiver, inputCurrency, outputCurrency);

        // -- SWAP --
        uint256 amountIn = 1e18;
        uint256 amountOutMin = 0.99e18;
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: Currency.unwrap(inputCurrency),
                amount: amountIn
            }),
            nonce: 0,
            deadline: block.timestamp + 100
        });
        bytes memory signature = getPermitTransferToSignature(permit, alicePK, address(router));

        bytes memory swapCalldata = abi.encode(
            BaseData({
                amount: amountIn,
                amountLimit: amountOutMin,
                payer: alice,
                receiver: receiver,
                flags: SwapFlags.SINGLE_SWAP | SwapFlags.PERMIT2
            }),
            zeroForOne,
            poolKey,
            ZERO_BYTES,
            PermitPayload({permit: permit, signature: signature})
        );
        vm.prank(alice);
        router.swap(swapCalldata, uint256(block.timestamp));

        InputOutputBalances memory thisAfter =
            inputOutputBalances(alice, inputCurrency, outputCurrency);
        InputOutputBalances memory receiverAfter =
            inputOutputBalances(receiver, inputCurrency, outputCurrency);

        // Check balances
        // test contract paid input currency
        // receiver did not spend input currency
        assertEq(thisBefore.inputCurrency - thisAfter.inputCurrency, amountIn);
        assertEq(receiverBefore.inputCurrency, receiverAfter.inputCurrency);

        // test contract did not receive outputCurrency
        // receiver received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertApproxEqRel(
            receiverAfter.outputCurrency - receiverBefore.outputCurrency, amountIn, 0.01e18
        ); // allow 1% error

        // verify slippage: received > amountOutMin
        assertGt((receiverAfter.outputCurrency - receiverBefore.outputCurrency), amountOutMin);
    }

    function test_encoded_single_permit2_exactOutput(
        address receiver,
        bool zeroForOne,
        uint256 seed
    ) public {
        vm.assume(
            receiver != address(manager) && receiver != address(this) && receiver != address(alice)
        );
        // randomly select a pool
        PoolKey memory poolKey = vanillaPoolKeys[seed % vanillaPoolKeys.length];

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(alice, inputCurrency, outputCurrency);
        InputOutputBalances memory receiverBefore =
            inputOutputBalances(receiver, inputCurrency, outputCurrency);

        uint256 amountOut = 1e18;
        uint256 amountInMax = 1.01e18;
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: Currency.unwrap(inputCurrency),
                amount: amountInMax
            }),
            nonce: 0,
            deadline: block.timestamp + 100
        });
        bytes memory signature = getPermitTransferToSignature(permit, alicePK, address(router));

        bytes memory swapCalldata = abi.encode(
            BaseData({
                amount: amountOut,
                amountLimit: amountInMax,
                payer: alice,
                receiver: receiver,
                flags: SwapFlags.SINGLE_SWAP | SwapFlags.EXACT_OUTPUT | SwapFlags.PERMIT2
            }),
            zeroForOne,
            poolKey,
            ZERO_BYTES,
            PermitPayload({permit: permit, signature: signature})
        );
        vm.prank(alice);
        router.swap(swapCalldata, uint256(block.timestamp));

        InputOutputBalances memory thisAfter =
            inputOutputBalances(alice, inputCurrency, outputCurrency);
        InputOutputBalances memory receiverAfter =
            inputOutputBalances(receiver, inputCurrency, outputCurrency);

        // Check balances
        // test contract did not receive outputCurrency
        // receiver received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertEq(receiverAfter.outputCurrency - receiverBefore.outputCurrency, amountOut);

        // test contract paid inputCurrency
        // receiver did not spend inputCurrency
        assertApproxEqRel(thisBefore.inputCurrency - thisAfter.inputCurrency, amountOut, 0.01e18); // allow 1% error
        assertEq(receiverBefore.inputCurrency, receiverAfter.inputCurrency);

        // verify slippage: amountIn < amountInMax
        assertLt((thisBefore.inputCurrency - thisAfter.inputCurrency), amountInMax);
    }
}
