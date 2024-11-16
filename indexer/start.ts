import { ExtractAbiEventNames } from "abitype";
import { appendFileSync } from "node:fs";
import { Address, Log, createPublicClient, getAddress, http } from "viem";

import { mainnet } from "viem/chains";

import { V3PoolABI } from "./abis";

type UniV3PoolScannedEvent = Log<
  bigint,
  number,
  false,
  undefined,
  false,
  typeof V3PoolABI,
  ExtractAbiEventNames<typeof V3PoolABI>
>;

const BLOCK_CHUNK_SIZE = 10000;
const TARGET_POOL = "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640";
const TARGET_POOL_NAME = "usdc-eth-005";
const TARGET_POOL_DEPLOYMENT_BLOCK = 12376729;

// Global state to track progress
const state = {
  lastCompletedBlock: TARGET_POOL_DEPLOYMENT_BLOCK,
  pool: getAddress(TARGET_POOL),
};

const viemClient = createPublicClient({
  chain: mainnet,
  transport: http("https://rpc.ankr.com/eth"),
});

async function writeEvents(events: UniV3PoolScannedEvent[]) {
  for (const event of events) {
    // We only care about events that change state
    if (!["Mint", "Burn", "Swap"].includes(event.eventName)) {
      continue;
    }

    // I'm lazy to write paths lol
    const args = event.args as any;
    appendFileSync(
      `./data/univ3-${TARGET_POOL_NAME}-events.csv`,
      `${event.eventName},${event.blockNumber},${event.eventName === "Burn" ? -args.amount : args.amount ?? "0"},${
        args.tickLower ?? "0"
      },${args.tickUpper ?? "0"},${args.amount0 ?? "0"},${args.amount1 ?? ""}\n`,
    );
  }
}

async function getContractEvents(pool: Address, fromBlock: bigint, desiredToBlock: bigint) {
  try {
    const events = await viemClient.getContractEvents({
      address: pool,
      abi: V3PoolABI,
      fromBlock: fromBlock,
      toBlock: desiredToBlock,
    });

    return {
      events,
      actualToBlock: desiredToBlock,
    };
  } catch (err) {
    if (desiredToBlock - fromBlock <= 2n) {
      throw err;
    }

    const reducedRangeToBlock = fromBlock + (desiredToBlock - fromBlock) / 2n;

    // RPC sucks
    await new Promise((resolve) => setTimeout(resolve, 250));

    return await getContractEvents(pool, fromBlock, reducedRangeToBlock);
  }
}

async function startFetchingEvents() {
  const fromBlock = BigInt(state.lastCompletedBlock + 1);

  const latestBlock = Number(await viemClient.getBlockNumber());
  const targetBlock = Math.min(latestBlock, state.lastCompletedBlock + BLOCK_CHUNK_SIZE);

  const { events, actualToBlock } = await getContractEvents(state.pool, fromBlock, BigInt(targetBlock));

  console.info(`Fetched ${events.length} events from block ${fromBlock} to ${actualToBlock}.`);

  await writeEvents(events);

  // Update state.
  state.lastCompletedBlock = Number(actualToBlock);

  // Stop when done
  if (latestBlock !== undefined && actualToBlock === BigInt(latestBlock)) {
    throw Error("Done!"); // It's an error only to break it.
  }
}

async function fetchUniV3PoolEvents() {
  while (true) {
    await startFetchingEvents();
  }
}

fetchUniV3PoolEvents();
