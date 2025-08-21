// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "@forge/interfaces/IERC20.sol";

import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {PoolId} from "@v4/src/types/PoolId.sol";
import {IHooks} from "@v4/src/interfaces/IHooks.sol";
import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "@v4/src/types/Currency.sol";
import {Deployers} from "@v4/test/utils/Deployers.sol";
import {SafeCast} from "@v4/src/libraries/SafeCast.sol";

import {MockERC20} from "@solady/test/utils/mocks/MockERC20.sol";

import {MockCurrencyLibrary} from "./mocks/MockCurrencyLibrary.sol";
import {CSMM} from "./hooks/CSMM.sol";
import {HookData} from "./hooks/HookData.sol";
import {HookMsgSender} from "./hooks/HookMsgSender.sol";

import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {PermitSignature} from "permit2/test/utils/PermitSignature.sol";
import "permit2/src/interfaces/IPermit2.sol";

struct TestCurrencyBalances {
    uint256 currencyA;
    uint256 currencyB;
    uint256 currencyC;
    uint256 currencyD;
    uint256 native;
}

struct InputOutputBalances {
    uint256 inputCurrency;
    uint256 outputCurrency;
}

contract SwapRouterFixtures is Deployers, DeployPermit2, PermitSignature {
    using SafeCast for uint256;

    Currency currencyA;
    Currency currencyB;
    Currency currencyC;
    Currency currencyD;

    CSMM csmm;
    HookData hookWithData;
    HookMsgSender hookMsgSender;
    ISignatureTransfer permit2 = ISignatureTransfer(address(PERMIT2_ADDRESS));

    uint24 constant FEE = 3000;
    int24 constant TICK_SPACING = 60;
    Currency constant native = CurrencyLibrary.ADDRESS_ZERO;
    IHooks constant HOOKLESS = IHooks(address(0));

    /// Lifecycle Functions ///

    function _initializePools(PoolKey[] memory poolKeys) internal {
        for (uint256 i = 0; i < poolKeys.length; i++) {
            manager.initialize(poolKeys[i], SQRT_PRICE_1_1);
        }
    }

    function _addLiquidity(PoolKey[] memory poolKeys, uint256 liquidity) internal {
        LIQUIDITY_PARAMS.liquidityDelta = liquidity.toInt256();

        PoolKey memory _poolKey;
        uint256 msgValue;
        for (uint256 i = 0; i < poolKeys.length; i++) {
            _poolKey = poolKeys[i];
            msgValue = _poolKey.currency0 == native ? 100 ether : 0;
            modifyLiquidityRouter.modifyLiquidity{value: msgValue}(
                _poolKey, LIQUIDITY_PARAMS, ZERO_BYTES
            );
        }
    }

    /// Hook Deployment Functions ///

    function _deployCSMM() internal {
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                    | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager);
        deployCodeTo("test/utils/hooks/CSMM.sol:CSMM", constructorArgs, flags);
        csmm = CSMM(flags);
    }

    function _deployHookWithData() internal {
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager);
        deployCodeTo("test/utils/hooks/HookData.sol:HookData", constructorArgs, flags);
        hookWithData = HookData(flags);
    }

    function _deployHookMsgSender() internal {
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x444A << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager);
        deployCodeTo("test/utils/hooks/HookMsgSender.sol:HookMsgSender", constructorArgs, flags);
        hookMsgSender = HookMsgSender(flags);
    }

    function _addLiquidityCSMM(PoolKey[] memory poolKeys, uint256 liquidity) internal {
        LIQUIDITY_PARAMS.liquidityDelta = liquidity.toInt256();
        PoolKey memory poolKey;
        for (uint256 i = 0; i < poolKeys.length; i++) {
            poolKey = poolKeys[i];
            IERC20(Currency.unwrap(poolKey.currency0)).approve(address(csmm), liquidity);
            IERC20(Currency.unwrap(poolKey.currency1)).approve(address(csmm), liquidity);
            csmm.addLiquidity(poolKey, liquidity);
        }
    }

    /// Setup Functions ///

    function _createSortedCurrencies()
        internal
        returns (Currency _currencyA, Currency _currencyB, Currency _currencyC, Currency _currencyD)
    {
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

    function _createPoolKeys(address hook) internal view returns (PoolKey[] memory _poolKeys) {
        _poolKeys = new PoolKey[](4);

        _poolKeys[0] = PoolKey({
            currency0: currencyA,
            currency1: currencyB,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        _poolKeys[1] = PoolKey({
            currency0: currencyB,
            currency1: currencyC,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        _poolKeys[2] = PoolKey({
            currency0: currencyC,
            currency1: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        _poolKeys[3] = PoolKey({
            currency0: currencyA,
            currency1: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });
    }

    function _createNativePoolKeys(address hook)
        internal
        view
        returns (PoolKey[] memory nativePoolKeys)
    {
        nativePoolKeys = new PoolKey[](4);
        nativePoolKeys[0] = PoolKey({
            currency0: native,
            currency1: currencyA,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        nativePoolKeys[1] = PoolKey({
            currency0: native,
            currency1: currencyB,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        nativePoolKeys[2] = PoolKey({
            currency0: native,
            currency1: currencyC,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        nativePoolKeys[3] = PoolKey({
            currency0: native,
            currency1: currencyD,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });
    }

    /// Utility Functions ///

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

    function _concatPools(
        PoolKey[] memory a,
        PoolKey[] memory b,
        PoolKey[] memory c,
        PoolKey[] memory d
    ) internal pure returns (PoolKey[] memory) {
        PoolKey[] memory result = new PoolKey[](a.length + b.length + c.length + d.length);
        uint256 index;
        for (uint256 i = 0; i < a.length; i++) {
            result[index] = a[i];
            index++;
        }
        for (uint256 i = 0; i < b.length; i++) {
            result[index] = b[i];
            index++;
        }
        for (uint256 i = 0; i < c.length; i++) {
            result[index] = c[i];
            index++;
        }
        for (uint256 i = 0; i < d.length; i++) {
            result[index] = d[i];
            index++;
        }
        return result;
    }

    function _copyArrayToStorage(PoolKey[] memory source, PoolKey[] storage destination) internal {
        for (uint256 i = 0; i < source.length; i++) {
            destination.push(source[i]);
        }
    }

    function currencyBalances(address addr) internal view returns (TestCurrencyBalances memory) {
        return TestCurrencyBalances({
            currencyA: currencyA.balanceOf(addr),
            currencyB: currencyB.balanceOf(addr),
            currencyC: currencyC.balanceOf(addr),
            currencyD: currencyD.balanceOf(addr),
            native: native.balanceOf(addr)
        });
    }

    function inputOutputBalances(address addr, Currency input, Currency output)
        internal
        view
        returns (InputOutputBalances memory)
    {
        return InputOutputBalances({
            inputCurrency: input.balanceOf(addr),
            outputCurrency: output.balanceOf(addr)
        });
    }
}
