# Swap
[Git Source](https://github.com/z0r0z/v4-router/blob/c527d235b3c39fc8a223c2459527adade0c283d0/src/V4SwapRouter.sol)

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

