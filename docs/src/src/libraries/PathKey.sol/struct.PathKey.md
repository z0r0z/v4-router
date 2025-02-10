# PathKey
[Git Source](https://github.com/z0r0z/v4-router/blob/3ca8e002a9f3fc72b979853144fa3c49aa37eb54/src/libraries/PathKey.sol)


```solidity
struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
    bytes hookData;
}
```

