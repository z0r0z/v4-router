// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "@v4/src/libraries/Hooks.sol";
import {IPoolManager} from "@v4/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@v4/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@v4/src/types/PoolId.sol";
import {BalanceDelta} from "@v4/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@v4/src/types/BeforeSwapDelta.sol";
import {Currency} from "@v4/src/types/Currency.sol";
import {SafeCast} from "@v4/src/libraries/SafeCast.sol";

contract CSMM is BaseHook {
    using SafeCast for uint256;
    using PoolIdLibrary for PoolKey;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Constant sum swap via custom accounting, tokens are exchanged 1:1
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        // determine inbound/outbound token based on 0->1 or 1->0 swap
        (Currency inputCurrency, Currency outputCurrency) =
            params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        bool isExactInput = params.amountSpecified < 0;

        // tokens are always swapped 1:1, so use amountSpecified to determine both input and output amounts
        uint256 amount =
            isExactInput ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        // take the input token, as ERC6909, from the PoolManager
        // the debt will be paid by the swapper via the swap router
        // input currency is added to hook's reserves
        poolManager.mint(address(this), inputCurrency.toId(), amount);

        // pay the output token, as ERC6909, to the PoolManager
        // the credit will be forwarded to the swap router, which then forwards it to the swapper
        // output currency is paid from the hook's reserves
        poolManager.burn(address(this), outputCurrency.toId(), amount);

        int128 tokenAmount = amount.toInt128();
        // return the delta to the PoolManager, so it can process the accounting
        // exact input:
        //   specifiedDelta = positive, to offset the input token taken by the hook (negative delta)
        //   unspecifiedDelta = negative, to offset the credit of the output token paid by the hook (positive delta)
        // exact output:
        //   specifiedDelta = negative, to offset the output token paid by the hook (positive delta)
        //   unspecifiedDelta = positive, to offset the input token taken by the hook (negative delta)
        BeforeSwapDelta returnDelta = isExactInput
            ? toBeforeSwapDelta(tokenAmount, -tokenAmount)
            : toBeforeSwapDelta(-tokenAmount, tokenAmount);

        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }

    /// @notice No liquidity will be managed by v4 PoolManager
    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert("No v4 Liquidity allowed");
    }

    // -----------------------------------------------
    // Liquidity Functions, not production ready
    // -----------------------------------------------
    /// @notice Add liquidity 1:1 for the constant sum curve
    /// @param key PoolKey of the pool to add liquidity to
    /// @param amountPerToken The amount of each token to be added as liquidity
    function addLiquidity(PoolKey calldata key, uint256 amountPerToken) external {
        poolManager.unlock(abi.encode(msg.sender, key.currency0, key.currency1, amountPerToken));
    }

    function _unlockCallback(bytes calldata data)
        internal
        virtual
        override
        returns (bytes memory)
    {
        (address payer, Currency currency0, Currency currency1, uint256 amountPerToken) =
            abi.decode(data, (address, Currency, Currency, uint256));

        // transfer ERC20 to PoolManager
        poolManager.sync(currency0);
        IERC20(Currency.unwrap(currency0)).transferFrom(payer, address(poolManager), amountPerToken);
        poolManager.settle();

        poolManager.sync(currency1);
        IERC20(Currency.unwrap(currency1)).transferFrom(payer, address(poolManager), amountPerToken);
        poolManager.settle();

        // mint ERC6909 to the hook
        poolManager.mint(address(this), currency0.toId(), amountPerToken);
        poolManager.mint(address(this), currency1.toId(), amountPerToken);

        // TODO: mint an LP receipt token

        return "";
    }
}
