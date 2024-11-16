// SPDX-License-Identifier: MIT
// $ forge script UniV4Backtester --fork-url https://eth-sepolia.g.alchemy.com/v2/0123456789ABCDEFGHIJKLMNOPQRSTUV --fork-block-number 6907299
pragma solidity >=0.8.0;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Test, console, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";

import { PoolManager } from "@uniswap/v4-core/src/PoolManager.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";

import { BasicHook, IHooks } from "./BasicHook.sol";

contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

struct SinglEvent {
    uint256 eventType; // 0: Liquidity Op, 1: Other Op (swap)
    uint256 blockNumber;
    int256 amount0;
    int256 amount1;
    int256 amount;
    int256 tickLower;
    int256 tickUpper;
}

contract Replayer is Test, Script {
    address WHALE = makeAddr("WHALE");
    address OWNER = makeAddr("OWNER");

    // These are all Unichain Sepolia Addresses
    address constant POOL_MANAGER = 0xC81462Fec8B23319F288047f8A03A57682a35C1A;
    address constant POSITION_MANAGER = 0x5Cd9D2Ae2BBbF59599d92fF57621d257be371639;
    address constant POOLSWAP = 0xd51ccB81De8426637f7b6fA8405B1990a3B81648;

    address constant HOOK_ADDRESS = 0x4444000000000000000000000000000000000000; // The flags must be right

    function getPoolEvents() internal view returns (SinglEvent[] memory events) {
        string memory json = vm.readFile("data/univ3-usdc-eth-005-events.json");
        bytes memory data = vm.parseJson(json);

        SinglEvent[] memory manyEvents = abi.decode(data, (SinglEvent[]));

        // Take first 10 for now
        events = new SinglEvent[](10);
        for (uint256 i = 0; i < 10; i++) {
            events[i] = manyEvents[i];
        }
    }

    function run() public {
        MockERC20 token0 = new MockERC20("T0", "T0");
        MockERC20 token1 = new MockERC20("T1", "T1");

        token0.mint(WHALE, type(uint128).max);
        token1.mint(WHALE, type(uint128).max);

        Currency currency0 = Currency.wrap(address(token0));
        Currency currency1 = Currency.wrap(address(token1));

        deployCodeTo("BasicHook.sol", abi.encode(POOL_MANAGER), HOOK_ADDRESS);

        BasicHook hook = BasicHook(HOOK_ADDRESS);

        PoolManager poolManager = new PoolManager(OWNER);
        PoolSwapTest swapRouter = new PoolSwapTest(poolManager);

        PoolKey memory poolKey = PoolKey(currency0, currency1, 500, 10, IHooks(address(0)));
        poolManager.initialize(poolKey, 1350174849792634181862360983626536); // This is the initial value that was used to setup the original pool

        console.log("OONONONON");
        SinglEvent[] memory poolEvents = getPoolEvents();
        console.log("Running %d events", poolEvents.length);
    }
}
