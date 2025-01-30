# PathKey
[Git Source](https://github.com/z0r0z/v4-router/blob/9825503402f4ebdeecdea34d1747e68d7f05f281/src/libraries/PathKey.sol)


```solidity
struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
    bytes hookData;
}
```

