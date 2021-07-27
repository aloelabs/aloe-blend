import fs from "fs";

import web3 from "web3";

import hackathonWinners from "./winners_hackathon.json";
import quizWinners from "./winners_quiz.json";

const quizWinnerSet = new Set(quizWinners);
if (quizWinnerSet.size !== 100) process.exit();

const merkleMap: any = {};
let totalReward = 0;

Object.entries(hackathonWinners).forEach((entry) => {
  const address = web3.utils.toChecksumAddress(entry[0]);
  let reward = entry[1];
  let reasons = "hackathon";

  if (quizWinnerSet.has(address)) {
    reward += 10;
    reasons = "hackathon,quiz";
    quizWinnerSet.delete(address);

    console.log(`${address.slice(0, 6)} did both hackathon and quiz`);
  }

  reward *= 1e18;

  merkleMap[address] = web3.utils.toHex(Math.floor(reward)).slice(2);
  totalReward += reward;
});

quizWinnerSet.forEach((address) => {
  merkleMap[address] = web3.utils.toHex(10e18).slice(2);
  totalReward += 10e18;
});

if (Math.round(totalReward / 1e18) !== 10000) process.exit();

fs.writeFile("scripts/merkle_map.json", JSON.stringify(merkleMap), (e) => {
  console.error(e);
});
