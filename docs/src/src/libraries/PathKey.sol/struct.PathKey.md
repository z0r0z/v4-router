# PathKey
[Git Source](https://github.com/z0r0z/v4-router/blob/f6f4cdd1451f5c32efafd920cd6b078aa2408be7/src/libraries/PathKey.sol)


```solidity
struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
    bytes hookData;
}
```

