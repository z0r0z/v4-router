# V4SwapRouter
[Git Source](https://github.com/z0r0z/v4-router/blob/3606343f28d74227fb063fdd3faaccf818af5167/src/V4SwapRouter.sol)

Router for stateless execution of swaps against Uniswap V4.


## State Variables
### UNISWAP_V4_POOL_MANAGER
========================= CONSTANTS ========================= ///

*The address of the Uniswap V4 pool manager singleton.
note: This is made `internal` to save gas. PoolManager
will be a canonical deployment, so address is known.*


```solidity
IPoolManager internal immutable UNISWAP_V4_POOL_MANAGER;
```


### MIN
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

*Create with Uniswap V4 pool manager.*


```solidity
constructor(IPoolManager manager) payable;
```

### swap

===================== SWAP EXECUTION ===================== ///

*Call into the PoolManager with Swap struct and path of keys.*


```solidity
function swap(Swap calldata swaps) public payable returns (BalanceDelta);
```

### unlockCallback

*Handle PoolManager Swap instructions and perform any swaps in their key sequence.*


```solidity
function unlockCallback(bytes calldata callbackData) public payable returns (bytes memory);
```

### _swapSingle


```solidity
function _swapSingle(address swapper, Swap memory swaps) internal returns (bytes memory);
```

### _swapFirst


```solidity
function _swapFirst(address swapper, Swap memory swaps) internal returns (Currency, int256);
```

### _swapMid


```solidity
function _swapMid(Currency fromCurrency, int256 takeIn, Key memory key)
    internal
    returns (Currency, int256);
```

### _swapLast


```solidity
function _swapLast(
    Currency fromCurrency,
    int256 takeIn,
    Key memory key,
    address receiver,
    uint256 amountOutMin
) internal returns (bytes memory);
```

### _swap


```solidity
function _swap(Currency fromCurrency, int256 amountSpecified, Key memory key)
    internal
    returns (bool zeroForOne, Currency toCurrency, BalanceDelta delta);
```

### receive


```solidity
receive() external payable;
```

## Errors
### Unauthorized
======================= CUSTOM ERRORS ======================= ///

*Pool authority check.*


```solidity
error Unauthorized();
```

### InsufficientOutput
*Insufficient swap output.*


```solidity
error InsufficientOutput();
```

