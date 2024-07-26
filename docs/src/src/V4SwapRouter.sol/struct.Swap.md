# Swap
[Git Source](https://github.com/z0r0z/v4-router/blob/5a1e320034f5e0745f06fd9f2e80920d8eaaa019/src/V4SwapRouter.sol)

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

