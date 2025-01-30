# BaseSwapRouter
[Git Source](https://github.com/z0r0z/v4-router/blob/9825503402f4ebdeecdea34d1747e68d7f05f281/src/base/BaseSwapRouter.sol)

**Inherits:**
SafeCallback

Template for data parsing and callback swap handling in Uniswap V4


## State Variables
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
constructor(IPoolManager manager) SafeCallback(manager);
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
    bool isSingleSwap,
    bool isExactOutput,
    uint256 amount,
    bytes calldata callbackData
) internal virtual returns (Currency inputCurrency, Currency outputCurrency, BalanceDelta delta);
```

### _exactInputMultiSwap


```solidity
function _exactInputMultiSwap(Currency inputCurrency, PathKey[] memory path, uint256 amount)
    internal
    virtual
    returns (BalanceDelta finalDelta);
```

### _exactOutputMultiSwap


```solidity
function _exactOutputMultiSwap(Currency startCurrency, PathKey[] memory path, uint256 amount)
    internal
    virtual
    returns (BalanceDelta finalDelta);
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

### receive


```solidity
receive() external payable virtual;
```

### _refundETH


```solidity
function _refundETH(address to, uint256 amount) internal virtual;
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

