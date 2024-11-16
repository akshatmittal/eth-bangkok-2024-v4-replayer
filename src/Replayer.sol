// SPDX-License-Identifier: MIT
// $ forge script UniV4Backtester --fork-url https://eth-sepolia.g.alchemy.com/v2/0123456789ABCDEFGHIJKLMNOPQRSTUV --fork-block-number 6907299
pragma solidity >=0.8.0;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Test, console, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";

import { PoolManager } from "@uniswap/v4-core/src/PoolManager.sol";
import { PositionManager, IWETH9, IPositionDescriptor, IAllowanceTransfer } from "@uniswap/v4-periphery/src/PositionManager.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import { BasicHook, IHooks } from "./BasicHook.sol";

contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

struct SinglEvent {
    int256 amount;
    int256 amount0;
    int256 amount1;
    int256 blockNumber;
    int256 eventType; // 0: Liquidity Op, 1: Other Op (swap)
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
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address constant HOOK_ADDRESS = 0x4444000000000000000000000000000000000000; // The flags must be right

    // Instead of replicating by the same tokenId, we'll use unique tick pairs as the keys
    mapping(string => bool) private isTicksExist;
    mapping(string => uint256) private ticksToTokenId;

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
        PositionManager positionManager = new PositionManager(
            poolManager,
            IAllowanceTransfer(PERMIT2),
            200000,
            IPositionDescriptor(address(0)),
            IWETH9(address(0x4200000000000000000000000000000000000006))
        );

        PoolKey memory poolKey = PoolKey(currency0, currency1, 500, 10, IHooks(address(0)));
        poolManager.initialize(poolKey, 1350174849792634181862360983626536); // This is the initial value that was used to setup the original pool

        vm.startPrank(WHALE);
        token0.approve(address(poolManager), type(uint256).max);
        token1.approve(address(poolManager), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        console.log("OONONONON");
        SinglEvent[] memory poolEvents = getPoolEvents();
        console.log("Running %d events", poolEvents.length);

        for (uint256 i = 0; i < poolEvents.length; i++) {
            // Alright, somehow need to figure out how to replicate each action
            SinglEvent memory poolEvent = poolEvents[i];

            console2.log("---");
            console2.logInt(poolEvent.amount);
            console2.logInt(poolEvent.amount0);
            console2.logInt(poolEvent.amount1);
            console2.logInt(poolEvent.blockNumber);
            console2.logInt(poolEvent.eventType);
            console2.logInt(poolEvent.tickLower);
            console2.logInt(poolEvent.tickUpper);
            console2.log("---");

            // eventType = 0, a Liquidity Operation
            if (poolEvent.eventType == 0) {
                string memory ticks = string.concat(
                    Strings.toStringSigned(poolEvent.tickLower),
                    Strings.toStringSigned(poolEvent.tickUpper)
                );

                if (!isTicksExist[ticks]) {
                    // There are two situations which can happen here:
                    // 1. Minting a new position
                    // 2. We have bad replay data
                    // Either way, we correct it.
                    uint256 tokenId = positionManager.nextTokenId();

                    isTicksExist[ticks] = true;
                    ticksToTokenId[ticks] = tokenId;

                    // Code below from v4-template
                    bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
                    bytes[] memory params = new bytes[](2);
                    params[0] = abi.encode(
                        poolKey,
                        int24(poolEvent.tickLower),
                        int24(poolEvent.tickUpper),
                        uint256(poolEvent.amount < 0 ? -poolEvent.amount : poolEvent.amount),
                        type(uint128).max,
                        type(uint128).max,
                        WHALE,
                        ""
                    );
                    params[1] = abi.encode(currency0, currency1);
                    vm.prank(WHALE);
                    positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 1);
                } else {
                    // This position, or a similar one, is already known.
                    // Since positions in the same ticks are fungible,
                    // we can just use the same tokenId to increase liquidity.
                    uint256 tokenId = ticksToTokenId[ticks];

                    if (poolEvent.amount > 0) {
                        // Code below from v4-template
                        bytes memory actions = abi.encodePacked(
                            uint8(Actions.INCREASE_LIQUIDITY),
                            uint8(Actions.SETTLE_PAIR)
                        );
                        bytes[] memory params = new bytes[](2);
                        params[0] = abi.encode(
                            tokenId,
                            uint256(poolEvent.amount),
                            type(uint128).max,
                            type(uint128).max,
                            ""
                        );
                        params[1] = abi.encode(currency0, currency1);
                        vm.prank(WHALE);
                        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 1);
                    } else {
                        // Code below from v4-template
                        bytes memory actions = abi.encodePacked(
                            uint8(Actions.DECREASE_LIQUIDITY),
                            uint8(Actions.TAKE_PAIR)
                        );
                        bytes[] memory params = new bytes[](2);
                        params[0] = abi.encode(
                            tokenId,
                            uint256(-poolEvent.amount),
                            type(uint128).max,
                            type(uint128).max,
                            ""
                        );
                        params[1] = abi.encode(currency0, currency1, WHALE);
                        vm.prank(WHALE);
                        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 1);
                    }
                }
            }
        }
    }
}
