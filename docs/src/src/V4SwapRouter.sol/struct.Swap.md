# Swap
[Git Source](https://github.com/z0r0z/v4-router/blob/779a8b2993340f52f002b2d88b27d991b1468c66/src/V4SwapRouter.sol)

*The swap router params.*


```solidity
struct Swap {
    address receiver;
    Currency fromCurrency;
    int256 amountSpecified;
    uint256 amountOutMin;
    Key[] keys;
}
```

