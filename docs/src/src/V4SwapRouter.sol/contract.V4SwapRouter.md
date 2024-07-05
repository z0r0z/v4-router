# V4SwapRouter
[Git Source](https://github.com/z0r0z/v4-router/blob/9c91d5ee278185c656d5983b3c07b8004a248d0c/src/V4SwapRouter.sol)

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

*Handle PoolManager Swap instructions and perform swaps in their key sequence.*


```solidity
function unlockCallback(bytes calldata callbackData) public payable returns (bytes memory);
```

### _swapSingle


```solidity
function _swapSingle(address swapper, Swap memory swaps) internal returns (bytes memory);
```

### _swapInitial


```solidity
function _swapInitial(address swapper, Swap memory swaps) internal returns (Currency, int256);
```

### _swapIntermediate


```solidity
function _swapIntermediate(Currency fromCurrency, int256 takeIn, Key memory key)
    internal
    returns (Currency, int256);
```

### _swapFinal


```solidity
function _swapFinal(
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

