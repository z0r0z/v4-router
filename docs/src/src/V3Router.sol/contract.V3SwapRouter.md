# V3SwapRouter
[Git Source](https://github.com/z0r0z/v4-router/blob/c527d235b3c39fc8a223c2459527adade0c283d0/src/V3Router.sol)

**Author:**
z0r0z.eth

*A hyper-optimized single-swap router for UniswapV3.*


## State Variables
### WETH
========================= CONSTANTS ========================= ///

*The canonical wrapped ETH address on Arbitrum.*


```solidity
address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
```


### UNISWAP_V3_FACTORY
*The address of the Uniswap V3 Factory.*


```solidity
address internal constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
```


### UNISWAP_V3_POOL_INIT_CODE_HASH
*The Uniswap V3 Pool `initcodehash`.*


```solidity
bytes32 internal constant UNISWAP_V3_POOL_INIT_CODE_HASH =
    0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
```


### MIN_SQRT_RATIO_PLUS_ONE
*The minimum value that can be returned from `getSqrtRatioAtTick` (plus one).*


```solidity
uint160 internal constant MIN_SQRT_RATIO_PLUS_ONE = 4295128740;
```


### MAX_SQRT_RATIO_MINUS_ONE
*The maximum value that can be returned from `getSqrtRatioAtTick` (minus one).*


```solidity
uint160 internal constant MAX_SQRT_RATIO_MINUS_ONE =
    1461446703485210103287273052203988822378723970341;
```


## Functions
### swap

===================== SWAP EXECUTION ===================== ///

*Executes a single-swap.*


```solidity
function swap(
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenIn,
    address tokenOut,
    uint24 fee
) public payable;
```

### fallback

*Fallback `uniswapV3SwapCallback`.
If ETH is swapped, WETH is forwarded.*


```solidity
fallback() external payable;
```

### _computePoolAddress

*Computes the create2 address for given token pair and pool fee.*


```solidity
function _computePoolAddress(address tokenA, address tokenB, uint24 fee)
    internal
    pure
    returns (address pool, bool zeroForOne);
```

### _computePairHash

*Computes the create2 deployment hash for a given token pair.*


```solidity
function _computePairHash(address token0, address token1, uint24 fee)
    internal
    pure
    returns (address pool);
```

### _wrapETH

*Wraps an `amount` of ETH to WETH and funds pool caller for swap.*


```solidity
function _wrapETH(uint256 amount) internal;
```

### _unwrapETH

*Unwraps an `amount` of ETH from WETH for return.*


```solidity
function _unwrapETH(uint256 amount) internal;
```

### receive

*ETH receiver fallback.
Only canonical WETH can call.*


```solidity
receive() external payable;
```

## Errors
### Overflow
======================= CUSTOM ERRORS ======================= ///

*Bad math.*


```solidity
error Overflow();
```

### InvalidSwap
*0-liquidity.*


```solidity
error InvalidSwap();
```

### InsufficientSwap
*Insufficient swap output.*


```solidity
error InsufficientSwap();
```

