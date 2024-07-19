# Swap
[Git Source](https://github.com/z0r0z/v4-router/blob/3606343f28d74227fb063fdd3faaccf818af5167/src/V4SwapRouter.sol)

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

