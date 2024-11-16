import converter from "convert-csv-to-json";
import { writeFileSync } from "node:fs";

const rawEvents = converter.fieldDelimiter(",").getJsonFromCsv("./data/univ3-usdc-eth-005-events.csv");
const processedEvents = rawEvents.map((event) => ({
  amount: Number(event.amount),
  amount0: Number(event.amount0),
  amount1: Number(event.amount1),
  blockNumber: Number(event.blockNumber),
  eventType: event.eventName === "Swap" ? 1 : 0,
  tickLower: Number(event.tickLower),
  tickUpper: Number(event.tickUpper),
}));

writeFileSync("./data/univ3-usdc-eth-005-events.json", JSON.stringify(processedEvents));
