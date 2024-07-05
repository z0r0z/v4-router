# Swap
[Git Source](https://github.com/z0r0z/v4-router/blob/9c91d5ee278185c656d5983b3c07b8004a248d0c/src/V4SwapRouter.sol)

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

