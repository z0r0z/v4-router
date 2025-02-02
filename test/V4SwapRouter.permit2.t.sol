// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {PathKey} from "../src/libraries/PathKey.sol";
import {IERC20Minimal} from "@v4/src/interfaces/external/IERC20Minimal.sol";

import {Counter} from "@v4-template/src/Counter.sol";
import {BaseHook} from "@v4-periphery/src/base/hooks/BaseHook.sol";

import {V4SwapRouter} from "../src/V4SwapRouter.sol";

import {
    SwapRouterFixtures,
    Deployers,
    TestCurrencyBalances,
    InputOutputBalances
} from "./utils/SwapRouterFixtures.sol";
import {MockCurrencyLibrary} from "./utils/mocks/MockCurrencyLibrary.sol";
import {HookData} from "./utils/hooks/HookData.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {PermitSignature} from "permit2/test/utils/PermitSignature.sol";
import {BaseData} from "../src/base/BaseSwapRouter.sol";
import "permit2/src/interfaces/IPermit2.sol";

contract V4SwapRouterPermit2Test is SwapRouterFixtures, DeployPermit2, PermitSignature {
    using MockCurrencyLibrary for Currency;

    V4SwapRouter router;
    ISignatureTransfer permit2 = ISignatureTransfer(address(PERMIT2_ADDRESS));
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
        router = new V4SwapRouter(manager);

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

    function test_encoded_single_permit2_exactInput(
        address recipient,
        bool zeroForOne,
        uint256 seed
    ) public {
        vm.assume(recipient != address(manager) && recipient != address(this));
        // randomly select a pool
        PoolKey memory poolKey = vanillaPoolKeys[seed % vanillaPoolKeys.length];

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(alice, inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

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
                payer: address(router),
                to: recipient,
                isSingleSwap: true,
                isExactOutput: false,
                amount: amountIn,
                amountLimit: amountOutMin
            }),
            zeroForOne,
            poolKey,
            ZERO_BYTES
        );
        vm.prank(alice);
        router.swapWithPermit2(swapCalldata, uint256(block.timestamp), permit, signature);

        InputOutputBalances memory thisAfter =
            inputOutputBalances(alice, inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract paid input currency
        // recipient did not spend input currency
        assertEq(thisBefore.inputCurrency - thisAfter.inputCurrency, amountIn);
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertApproxEqRel(
            recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountIn, 0.01e18
        ); // allow 1% error

        // verify slippage: recieved > amountOutMin
        assertGt((recipientAfter.outputCurrency - recipientBefore.outputCurrency), amountOutMin);
    }

    function test_encoded_single_permit2_exactOutput(address recipient, bool zeroForOne, uint256 seed) public {
        vm.assume(recipient != address(manager) && recipient != address(this));
        // randomly select a pool
        PoolKey memory poolKey = vanillaPoolKeys[seed % vanillaPoolKeys.length];

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        InputOutputBalances memory thisBefore =
            inputOutputBalances(alice, inputCurrency, outputCurrency);
        InputOutputBalances memory recipientBefore =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

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
                payer: address(router),
                to: recipient,
                isSingleSwap: true,
                isExactOutput: true,
                amount: amountOut,
                amountLimit: amountInMax
            }),
            zeroForOne,
            poolKey,
            ZERO_BYTES
        );
        vm.prank(alice);
        router.swapWithPermit2(swapCalldata, uint256(block.timestamp), permit, signature);

        InputOutputBalances memory thisAfter =
            inputOutputBalances(alice, inputCurrency, outputCurrency);
        InputOutputBalances memory recipientAfter =
            inputOutputBalances(recipient, inputCurrency, outputCurrency);

        // Check balances
        // test contract did not receive outputCurrency
        // recipient received outputCurrency
        assertEq(thisBefore.outputCurrency, thisAfter.outputCurrency);
        assertEq(recipientAfter.outputCurrency - recipientBefore.outputCurrency, amountOut);

        // test contract paid inputCurrency
        // recipient did not spend inputCurrency
        assertApproxEqRel(thisBefore.inputCurrency - thisAfter.inputCurrency, amountOut, 0.01e18); // allow 1% error
        assertEq(recipientBefore.inputCurrency, recipientAfter.inputCurrency);

        // verify slippage: amountIn < amountInMax
        assertLt((thisBefore.inputCurrency - thisAfter.inputCurrency), amountInMax);
    }

    function getPermitTransferToSignature(
        ISignatureTransfer.PermitTransferFrom memory permit,
        uint256 privateKey,
        address to
    ) internal view returns (bytes memory sig) {
        bytes32 tokenPermissions =
            keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                permit2.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        _PERMIT_TRANSFER_FROM_TYPEHASH,
                        tokenPermissions,
                        to,
                        permit.nonce,
                        permit.deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }
}
