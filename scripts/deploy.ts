import { ethers, hardhatArguments } from "hardhat";
import * as Config from "./config";

async function main() {
  await Config.initConfig();
  const network = hardhatArguments.network
    ? hardhatArguments.network
    : "bsctest";
  const [deployer] = await ethers.getSigners();
  console.log("deploy from address: ", deployer.address);

  const Artwork = await ethers.getContractFactory("Artwork");
  const artwork = await Artwork.deploy();

  const WBNB = await ethers.getContractFactory("WBNBMock");
  const wbnb = await WBNB.deploy();

  const Marketplace = await ethers.getContractFactory("Marketplace");
  const marketplace = await Marketplace.deploy(wbnb.address, artwork.address);

  const AuctionHouse = await ethers.getContractFactory("AuctionHouse");
  const auctionHouse = await AuctionHouse.deploy(wbnb.address, artwork.address);

  console.log("Artwork address: ", artwork.address);
  console.log("WBNB address: ", wbnb.address);
  console.log("Marketplace address: ", marketplace.address);
  console.log("AuctionHouse address: ", auctionHouse.address);

  Config.setConfig(network + ".Artwork", artwork.address);
  Config.setConfig(network + ".WBNB", wbnb.address);
  Config.setConfig(network + ".Marketplace", marketplace.address);
  Config.setConfig(network + ".AuctionHouse", auctionHouse.address);

  await Config.updateConfig();
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
