# UniswapV4Router04
[Git Source](https://github.com/z0r0z/v4-router/blob/2136c4940d470a172e9d496b4ec339d98f9187ae/src/UniswapV4Router04.sol)

**Inherits:**
[IUniswapV4Router04](/src/interfaces/IUniswapV4Router04.sol/interface.IUniswapV4Router04.md), [BaseSwapRouter](/src/base/BaseSwapRouter.sol/abstract.BaseSwapRouter.md), Multicallable


## Functions
### setMsgSender


```solidity
modifier setMsgSender();
```

### constructor


```solidity
constructor(IPoolManager manager, ISignatureTransfer _permit2)
    payable
    BaseSwapRouter(manager, _permit2);
```

### swapExactTokensForTokens

-----------------------


```solidity
function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    Currency startCurrency,
    PathKey[] calldata path,
    address receiver,
    uint256 deadline
)
    public
    payable
    virtual
    override(IUniswapV4Router04)
    checkDeadline(deadline)
    setMsgSender
    returns (BalanceDelta);
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
)
    public
    payable
    virtual
    override(IUniswapV4Router04)
    checkDeadline(deadline)
    setMsgSender
    returns (BalanceDelta);
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
)
    public
    payable
    virtual
    override(IUniswapV4Router04)
    checkDeadline(deadline)
    setMsgSender
    returns (BalanceDelta);
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

-----------------------


```solidity
function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    bool zeroForOne,
    PoolKey calldata poolKey,
    bytes calldata hookData,
    address receiver,
    uint256 deadline
)
    public
    payable
    virtual
    override(IUniswapV4Router04)
    checkDeadline(deadline)
    setMsgSender
    returns (BalanceDelta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amountIn`|`uint256`|the amount of input tokens to swap|
|`amountOutMin`|`uint256`|the minimum amount of output tokens that must be received for the transaction not to revert. reverts on equals to|
|`zeroForOne`|`bool`||
|`poolKey`|`PoolKey`||
|`hookData`|`bytes`||
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
    bool zeroForOne,
    PoolKey calldata poolKey,
    bytes calldata hookData,
    address receiver,
    uint256 deadline
)
    public
    payable
    virtual
    override(IUniswapV4Router04)
    checkDeadline(deadline)
    setMsgSender
    returns (BalanceDelta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amountOut`|`uint256`|the amount of output tokens to receive|
|`amountInMax`|`uint256`|the maximum amount of input tokens that can be spent for the transaction not to revert. reverts on equal to|
|`zeroForOne`|`bool`||
|`poolKey`|`PoolKey`||
|`hookData`|`bytes`||
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
    bool zeroForOne,
    PoolKey calldata poolKey,
    bytes calldata hookData,
    address receiver,
    uint256 deadline
)
    public
    payable
    virtual
    override(IUniswapV4Router04)
    checkDeadline(deadline)
    setMsgSender
    returns (BalanceDelta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amountSpecified`|`int256`|the amount of tokens to be swapped, negative for exact input swaps and positive for exact output swaps|
|`amountLimit`|`uint256`|the minimum amount of output tokens for exact input swaps, the maximum amount of input tokens for exact output swaps|
|`zeroForOne`|`bool`||
|`poolKey`|`PoolKey`||
|`hookData`|`bytes`||
|`receiver`|`address`|the address to send the output tokens to|
|`deadline`|`uint256`|block.timestamp must be before this value, otherwise the transaction will revert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BalanceDelta`|Delta the balance changes from the swap|


### swap

-----------------------


```solidity
function swap(bytes calldata data, uint256 deadline)
    public
    payable
    virtual
    override(IUniswapV4Router04)
    checkDeadline(deadline)
    setMsgSender
    returns (BalanceDelta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`bytes`||
|`deadline`|`uint256`|block.timestamp must be before this value, otherwise the transaction will revert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BalanceDelta`|Delta the balance changes from the swap|


### msgSender

-----------------------


```solidity
function msgSender() public view virtual returns (address);
```

### fallback

Provides calldata compression fallback


```solidity
fallback() external payable virtual;
```

### receive

Provides ETH receipts locked to Pool Manager


```solidity
receive() external payable virtual;
```

