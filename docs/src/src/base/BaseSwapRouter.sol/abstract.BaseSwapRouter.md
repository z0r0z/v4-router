# BaseSwapRouter
[Git Source](https://github.com/z0r0z/v4-router/blob/2136c4940d470a172e9d496b4ec339d98f9187ae/src/base/BaseSwapRouter.sol)

**Inherits:**
SafeCallback

Template for data parsing and callback swap handling in Uniswap V4

*Fee-on-transfer tokens are not supported - these swaps might not pass*


## State Variables
### permit2

```solidity
ISignatureTransfer public immutable permit2;
```


### MIN
========================= CONSTANTS ========================= ///

*The minimum sqrt price limit for the swap.*


```solidity
uint160 internal constant MIN = TickMath.MIN_SQRT_PRICE + 1;
```


### MAX
*The maximum sqrt price limit for the swap.*


```solidity
uint160 internal constant MAX = TickMath.MAX_SQRT_PRICE - 1;
```


## Functions
### constructor

======================== CONSTRUCTOR ======================== ///


```solidity
constructor(IPoolManager manager, ISignatureTransfer _permit2) SafeCallback(manager);
```

### _unlockCallback

===================== SWAP EXECUTION ===================== ///


```solidity
function _unlockCallback(bytes calldata callbackData)
    internal
    virtual
    override(SafeCallback)
    returns (bytes memory);
```

### _parseAndSwap


```solidity
function _parseAndSwap(
    bool singleSwap,
    bool exactOutput,
    uint256 amount,
    bytes calldata callbackData
) internal virtual returns (Currency inputCurrency, Currency outputCurrency, BalanceDelta delta);
```

### _exactInputMultiSwap


```solidity
function _exactInputMultiSwap(Currency inputCurrency, PathKey[] memory path, uint256 amount)
    internal
    virtual
    returns (BalanceDelta delta);
```

### _exactOutputMultiSwap


```solidity
function _exactOutputMultiSwap(Currency startCurrency, PathKey[] memory path, uint256 amount)
    internal
    virtual
    returns (BalanceDelta delta);
```

### _swap


```solidity
function _swap(
    PoolKey memory poolKey,
    bool zeroForOne,
    int256 amountSpecified,
    bytes memory hookData
) internal virtual returns (BalanceDelta);
```

### _unlockAndDecode


```solidity
function _unlockAndDecode(bytes memory data) internal virtual returns (BalanceDelta);
```

### checkDeadline


```solidity
modifier checkDeadline(uint256 deadline) virtual;
```

### _refundETH

*Note: This function forwards all remaining gas to the receiver.
If the receiver is contract, it could maliciously consume excess gas
in its fallback function, significantly increasing transaction costs.*


```solidity
function _refundETH(address receiver, uint256 amount) internal virtual;
```

## Errors
### EmptyPath
======================= CUSTOM ERRORS ======================= ///

*No path.*


```solidity
error EmptyPath();
```

### Unauthorized
*Auth check.*


```solidity
error Unauthorized();
```

### SlippageExceeded
*Slippage check.*


```solidity
error SlippageExceeded();
```

### ETHTransferFailed
*ETH refund fail.*


```solidity
error ETHTransferFailed();
```

### DeadlinePassed
*Swap `block.timestamp` check.*


```solidity
error DeadlinePassed(uint256 deadline);
```

