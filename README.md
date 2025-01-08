# V4 Swap Router

A simple and optimized router for swapping on Uniswap V4. ABI inspired by [`UniswapV2Router02`](https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol).

## Design

The Uniswap V4 Swap Router supports the following features:

- Exact input swaps
- Exact output swaps
- Multi-hop swaps
- Native token (ETH) swaps
- Hook interactions
- Custom swap curves

## Architecture

The router is implemented in two main contracts:

1. `BaseSwapRouter`: Contains core swap logic and handles callbacks from the Pool Manager
2. `V4SwapRouter`: Inherits from BaseSwapRouter and implements the user-facing interface

## Optimizations

The implementation prioritizes gas efficiency through:

- Minimal state changes
- Optimized memory usage in multi-hop swaps
- Single-swap vs multi-swap specific codepaths
- Efficient native token handling
- Reuse of Pool Manager callbacks

## Interface

The router provides three categories of swap functions:

### Multi-pool Swaps
- `swapExactTokensForTokens`: Swap exact input amount through multiple pools
- `swapTokensForExactTokens`: Receive exact output amount through multiple pools
- `swap`: Generic multi-pool swap interface

### Single-pool Swaps
- `swapExactTokensForTokens`: Swap exact input in a single pool
- `swapTokensForExactTokens`: Receive exact output from a single pool
- `swap`: Generic single-pool swap interface

### Optimized Swaps
- `swap(bytes, uint256)`: Pre-encoded swap data for reduced gas costs

## Path Construction

Multi-hop swaps are defined using the `PathKey` struct:
```solidity
struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
    bytes hookData;
}
```

## Getting Started

Run: `curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup`

Build the foundry project with `forge build`. Run tests with `forge test`. Measure gas with `forge snapshot`. Format with `forge fmt`.

## Disclaimer

*These smart contracts and testing suite are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of anything provided herein or through related user interfaces. This repository and related code have not been audited and as such there can be no assurance anything will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk.*

## License

See [LICENSE](./LICENSE) for more details.
