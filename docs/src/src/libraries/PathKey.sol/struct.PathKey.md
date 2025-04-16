# PathKey
[Git Source](https://github.com/z0r0z/v4-router/blob/2136c4940d470a172e9d496b4ec339d98f9187ae/src/libraries/PathKey.sol)


```solidity
struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
    bytes hookData;
}
```

