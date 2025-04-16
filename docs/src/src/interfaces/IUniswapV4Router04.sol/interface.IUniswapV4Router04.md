# IUniswapV4Router04
[Git Source](https://github.com/z0r0z/v4-router/blob/2136c4940d470a172e9d496b4ec339d98f9187ae/src/interfaces/IUniswapV4Router04.sol)

A simple, stateless router for execution of swaps against Uniswap v4 Pools

*ABI inspired by UniswapV2Router02*


## Functions
### swapExactTokensForTokens

================ MULTI POOL SWAPS ================= ///

Exact Input Swap; swap the specified amount of input tokens for as many output tokens as possible, along the path


```solidity
function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    Currency startCurrency,
    PathKey[] calldata path,
    address receiver,
    uint256 deadline
) external payable returns (BalanceDelta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amountIn`|`uint256`|the amount of input tokens to swap|
|`amountOutMin`|`uint256`|the minimum amount of output tokens that must be received for the transaction not to revert. reverts on equals to|
|`startCurrency`|`Currency`|the currency to start the swap from|
|`path`|`PathKey[]`|the path of v4 Pools to swap through|
|`receiver`|`address`|the address to send the output tokens to|
|`deadline`|`uint256`|block.timestamp must be before this value, otherwise the transaction will revert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BalanceDelta`|Delta the balance changes from the swap|


### swapTokensForExactTokens

Exact Output Swap; swap as few input tokens as possible for the specified amount of output tokens, along the path


```solidity
function swapTokensForExactTokens(
    uint256 amountOut,
    uint256 amountInMax,
    Currency startCurrency,
    PathKey[] calldata path,
    address receiver,
    uint256 deadline
) external payable returns (BalanceDelta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amountOut`|`uint256`|the amount of output tokens to receive|
|`amountInMax`|`uint256`|the maximum amount of input tokens that can be spent for the transaction not to revert. reverts on equal to|
|`startCurrency`|`Currency`|the currency to start the swap from|
|`path`|`PathKey[]`|the path of v4 Pools to swap through|
|`receiver`|`address`|the address to send the output tokens to|
|`deadline`|`uint256`|block.timestamp must be before this value, otherwise the transaction will revert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BalanceDelta`|Delta the balance changes from the swap|


### swap

General-purpose swap interface for Uniswap v4 that handles all types of swaps


```solidity
function swap(
    int256 amountSpecified,
    uint256 amountLimit,
    Currency startCurrency,
    PathKey[] calldata path,
    address receiver,
    uint256 deadline
) external payable returns (BalanceDelta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amountSpecified`|`int256`|the amount of tokens to be swapped, negative for exact input swaps and positive for exact output swaps|
|`amountLimit`|`uint256`|the minimum amount of output tokens for exact input swaps, the maximum amount of input tokens for exact output swaps|
|`startCurrency`|`Currency`|the currency to start the swap from|
|`path`|`PathKey[]`|the path of v4 Pools to swap through|
|`receiver`|`address`|the address to send the output tokens to|
|`deadline`|`uint256`|block.timestamp must be before this value, otherwise the transaction will revert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BalanceDelta`|Delta the balance changes from the swap|


### swapExactTokensForTokens

================ SINGLE POOL SWAPS ================ ///

Single pool, exact input swap - swap the specified amount of input tokens for as many output tokens as possible, on a single pool


```solidity
function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    bool zeroForOne,
    PoolKey calldata poolKey,
    bytes calldata hookData,
    address receiver,
    uint256 deadline
) external payable returns (BalanceDelta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amountIn`|`uint256`|the amount of input tokens to swap|
|`amountOutMin`|`uint256`|the minimum amount of output tokens that must be received for the transaction not to revert|
|`zeroForOne`|`bool`|the direction of the swap, true if currency0 is being swapped for currency1|
|`poolKey`|`PoolKey`|the pool to swap through|
|`hookData`|`bytes`|the data to be passed to the hook|
|`receiver`|`address`|the address to send the output tokens to|
|`deadline`|`uint256`|block.timestamp must be before this value, otherwise the transaction will revert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BalanceDelta`|Delta the balance changes from the swap|


### swapTokensForExactTokens

Singe pool, exact output swap; swap as few input tokens as possible for the specified amount of output tokens, on a single pool


```solidity
function swapTokensForExactTokens(
    uint256 amountOut,
    uint256 amountInMax,
    bool zeroForOne,
    PoolKey calldata poolKey,
    bytes calldata hookData,
    address receiver,
    uint256 deadline
) external payable returns (BalanceDelta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amountOut`|`uint256`|the amount of output tokens to receive|
|`amountInMax`|`uint256`|the maximum amount of input tokens that can be spent for the transaction not to revert|
|`zeroForOne`|`bool`|the direction of the swap, true if currency0 is being swapped for currency1|
|`poolKey`|`PoolKey`|the pool to swap through|
|`hookData`|`bytes`|the data to be passed to the hook|
|`receiver`|`address`|the address to send the output tokens to|
|`deadline`|`uint256`|block.timestamp must be before this value, otherwise the transaction will revert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BalanceDelta`|Delta the balance changes from the swap|


### swap

General-purpose single-pool swap interface


```solidity
function swap(
    int256 amountSpecified,
    uint256 amountLimit,
    bool zeroForOne,
    PoolKey calldata poolKey,
    bytes calldata hookData,
    address receiver,
    uint256 deadline
) external payable returns (BalanceDelta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amountSpecified`|`int256`|the amount of tokens to be swapped, negative for exact input swaps and positive for exact output swaps|
|`amountLimit`|`uint256`|the minimum amount of output tokens for exact input swaps, the maximum amount of input tokens for exact output swaps|
|`zeroForOne`|`bool`|the direction of the swap, true if currency0 is being swapped for currency1|
|`poolKey`|`PoolKey`|the pool to swap through|
|`hookData`|`bytes`|the data to be passed to the hook|
|`receiver`|`address`|the address to send the output tokens to|
|`deadline`|`uint256`|block.timestamp must be before this value, otherwise the transaction will revert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BalanceDelta`|Delta the balance changes from the swap|


### swap

================ OPTIMIZED ================ ///

Generic multi-pool swap function that accepts pre-encoded calldata

*Minor optimization to reduce the number of onchain abi.encode calls*


```solidity
function swap(bytes calldata data, uint256 deadline) external payable returns (BalanceDelta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`bytes`|Pre-encoded swap data in one of the following formats: 1. For single-pool swaps: abi.encode( BaseData baseData,             // struct containing swap parameters bool zeroForOne,               // direction of swap PoolKey poolKey,               // key of the pool to swap through bytes hookData                 // data to pass to hooks ) 2. For multi-pool swaps: abi.encode( BaseData baseData,             // struct containing swap parameters Currency startCurrency,        // initial currency in the swap PathKey[] path                 // array of path keys defining the route ) PERMIT2 EXTENSION: 1. For single pool swaps: abi.encode( BaseData baseData,             // struct containing swap parameters bool zeroForOne,               // direction of swap PoolKey poolKey,               // key of the pool to swap through bytes hookData,                // data to pass to hooks PermitPayload permitPayload    // permit2 signature payload ) 2. For multi-pool swaps: abi.encode( BaseData baseData,             // struct containing swap parameters Currency startCurrency,        // initial currency in the swap PathKey[] path,                // array of path keys defining the route PermitPayload permitPayload    // permit2 signature payload ) Where BaseData.flags contains permit2 flag, and PermitPayload contains: - permit: ISignatureTransfer.PermitTransferFrom - signature: bytes|
|`deadline`|`uint256`|block.timestamp must be before this value, otherwise the transaction will revert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BalanceDelta`|Delta the balance changes from the swap|


### fallback

Provides calldata compression fallback


```solidity
fallback() external payable;
```

### receive

Provides ETH receipts locked to Pool Manager


```solidity
receive() external payable;
```

### msgSender

================ GETTERS ================ ///

Public view function to be used instead of msg.sender, as the contract performs self-reentrancy and at
times msg.sender == address(this). Instead msgSender() returns the initiator of the lock


```solidity
function msgSender() external view returns (address);
```

