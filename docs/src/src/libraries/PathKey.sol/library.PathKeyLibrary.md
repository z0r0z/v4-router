# PathKeyLibrary
[Git Source](https://github.com/z0r0z/v4-router/blob/9825503402f4ebdeecdea34d1747e68d7f05f281/src/libraries/PathKey.sol)

Memory-oriented version of v4-periphery/src/libraries/PathKeyLibrary.sol

*Handles PathKey operations in memory rather than calldata for router operations*


## Functions
### getPoolAndSwapDirection

Get the pool and swap direction for a given PathKey


```solidity
function getPoolAndSwapDirection(PathKey memory params, Currency currencyIn)
    internal
    pure
    returns (PoolKey memory poolKey, bool zeroForOne);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`PathKey`|the given PathKey|
|`currencyIn`|`Currency`|the input currency|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`poolKey`|`PoolKey`|the pool key of the swap|
|`zeroForOne`|`bool`|the direction of the swap, true if currency0 is being swapped for currency1|


