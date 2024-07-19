# V4 Swap Router

A simple and optimized reference implementation for swapping on Uniswap V4.

## Design

The Uniswap V4 Swap Router (Swap Router) supports the following features:

- Exact-in
- Exact-out
- Multi-hop
- Hook calls

Regardless of swap pool routes, all swaps can be made with hook data included.

## Optimizations

The code is mostly high-level for readability but uses audited [*Solady* snippets](https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol) in low-level assembly code to reduce costs for routine operations, such as token handling. Further, based on the length of a path, each swap step is particularly optimized and contained as its own internal function (see, `_swapSingle()`, `_swapFirst()`, `_swapMid()`, and `_swapLast()`). Additional efficiency decisions also include reusing memory space for multi-hop swaps (overwriting `fromCurrency` and `amountSpecified` at each step with outputs) and practical use of unchecked blocks and custom errors.

## Using Swap Router

Swap Router and its interface is designed to closely resemble the `swap()` method of the V4 [Pool Manager](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol). Thus it only has two public functions, `swap()` and `unlockCallback()` to clearly place its role as a peripheral contract to the Pool Manager to receive a swap callback, and nothing more.

Some parameter additions have been made to simplify complex swaps, and the single argument made to `swap()` on Swap Router is just the following struct:

```solidity
struct Swap {
    address receiver;
    Currency fromCurrency;
    int256 amountSpecified;
    uint256 amountOutMin;
    Key[] keys;
}
```

Where the `receiver` is the end-recipient of the swap output and currency. 

`fromCurrency` is the initial currency used to make the swap from (`address(0)` is ETH).

`amountSpecified` is the amount initially paid (if negative `-`) or required as output.

Note: In cases where a multi-hop swap is made, this flag will guarantee the output of the first pool only.
`amountOutMin` is therefore used to enforce the end-output of the final pool included in the `keys` array of structs, more generally. However, the ability to include exact outputs in this fashion should still yield some precision benefits.

More specifically, `keys` include the following information (and are provided in the order of the pools to cross):

```solidity
struct Key {
    PoolKey key;
    bytes hookData;
}
```

Where `key` is the Uniswap V4 [`PoolKey`](https://github.com/Uniswap/v4-core/blob/main/src/types/PoolKey.sol) struct, and `hookData` is a dynamic field for any hook interactions included in the swap.

## Single Swap

A single swap for a given pool key can be made like so:

```solidity
function testSingleSwapExactInputZeroForOne() public payable {
    Key[] memory keys = new Key[](1);
    keys[0].key = keyNoHook; // Basic no-hook pool.
    Swap memory swap;
    swap.receiver = aliceSwapper;
    swap.fromCurrency = keyNoHook.currency0; // zeroForOne.
    swap.amountSpecified = -(0.1 ether); // Exact-in.
    swap.keys = keys;
    vm.prank(aliceSwapper);
    router.swap(swap);
}
```

## Multi-hop Swap

A three-hop swap can be made like so within the keys path:

```solidity
function testMultihopSwapExactInputThreeHops() public payable {
    Key[] memory keys = new Key[](3);
    keys[0].key = keyNoHook; // 0 for 1.
    keys[1].key = keyNoHook4; // 1 for 2.
    keys[2].key = keyNoHook2; // 2 for 3.
    Swap memory swap;
    swap.receiver = aliceSwapper;
    swap.fromCurrency = keyNoHook.currency0; // zeroForOne.
    swap.amountSpecified = -(0.1 ether);
    swap.keys = keys;
    vm.prank(aliceSwapper);
    router.swap(swap); // 0 for 3.
}
```

Additional examples are provided in foundry tests [here](./test/V4SwapRouter.t.sol), and will serve the basis for more complex pool simulations.

## Getting Started

Run: `curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup`

Build the foundry project with `forge build`. Run tests with `forge test`. Measure gas with `forge snapshot`. Format with `forge fmt`.

## Disclaimer

*These smart contracts and testing suite are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of anything provided herein or through related user interfaces. This repository and related code have not been audited and as such there can be no assurance anything will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk.*

## License

See [LICENSE](./LICENSE) for more details.
