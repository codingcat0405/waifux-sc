import { ethers, hardhatArguments } from "hardhat";
import * as Config from "./config";

async function main() {
  await Config.initConfig();
  const network = hardhatArguments.network
    ? hardhatArguments.network
    : "bsctest";
  const [deployer] = await ethers.getSigners();
  console.log("deploy from address: ", deployer.address);

  const xFishContract = await ethers.getContractFactory("xFish");
  const xfish = await xFishContract.deploy();
  console.log("xFish address: ", xfish.address);

  const fishContract = await ethers.getContractFactory("Fish");
  const fish = await fishContract.deploy(deployer.address, xfish.address);
  console.log("Fish address: ", fish.address);
  //sleep 5 seconds
  await new Promise((resolve) => setTimeout(resolve, 5000));
  const fishingGameContract = await ethers.getContractFactory("FishingGame");
  const fishingGame = await fishingGameContract.deploy(xfish.address, xfish.address, deployer.address);
  console.log("FishingGame address: ", fishingGame.address);

  const fishTankContract = await ethers.getContractFactory("FishTank");
  const fishTank = await fishTankContract.deploy(xfish.address);
  console.log("FishTank address: ", fishTank.address);

  const stakingContract = await ethers.getContractFactory("Staking");
  const staking = await stakingContract.deploy(xfish.address);
  console.log("Staking address: ", staking.address);

  const tokenSaleContract = await ethers.getContractFactory("TokenSale");
  const tokenSale = await tokenSaleContract.deploy(xfish.address, 10000, 2500);
  console.log("TokenSale address: ", tokenSale.address);

  console.log("xFish address: ", xfish.address);
  console.log("Fish address: ", fish.address);
  console.log("FishingGame address: ", fishingGame.address);
  console.log("FishTank address: ", fishTank.address);
  console.log("Staking address: ", staking.address);
  console.log("TokenSale address: ", tokenSale.address);

  Config.setConfig(network + ".xFish", xfish.address);
  Config.setConfig(network + ".Fish", fish.address);
  Config.setConfig(network + ".FishingGame", fishingGame.address);
  Config.setConfig(network + ".FishTank", fishTank.address);
  Config.setConfig(network + ".Staking", staking.address);
  Config.setConfig(network + ".TokenSale", tokenSale.address);

  await Config.updateConfig();
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
