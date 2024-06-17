import { BigNumber } from "@ethersproject/bignumber";
import { Contract } from "@ethersproject/contracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import * as chai from "chai";
import { expect } from "chai";
const chaiAsPromised = require("chai-as-promised");
import { ethers } from "hardhat";
const fs = require("fs");
import dotenv from "dotenv";
dotenv.config();
//dotenv.config({ path: __dirname + "/.env" });

chai.use(chaiAsPromised);

function parseEther(amount: Number) {
  return ethers.utils.parseUnits(amount.toString(), 18);
}

describe("AuctionHouse Contract", () => {
  let owner: SignerWithAddress;
  let alice: SignerWithAddress,
    bob: SignerWithAddress,
    carol: SignerWithAddress,
    dave: SignerWithAddress;
  let artwork: Contract, auctionHouse: Contract;
  beforeEach(async () => {
    // define MAX_UINT256
    const MAX_UINT256 = BigNumber.from(2).pow(256).sub(1);
    //await ethers.provider.send("hardhat_reset", []);
    [owner, alice, bob, carol, dave] = await ethers.getSigners();
    const wbnbABI = fs.readFileSync("./abi/wbnb-abi.json", "utf8");
    const WBNB_ADDRESS = "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd";
    //console.log("wbnb abi: ", wbnbABI);
    const wbnb = new ethers.Contract(WBNB_ADDRESS, wbnbABI, owner);
    console.log("wbnb address: ", wbnb.address);
    // deploy artwork contract
    const Artwork = await ethers.getContractFactory("ArtworkV2");
    artwork = await Artwork.deploy();
    console.log("artwork address: ", artwork.address);
    // deploy auctionHouse contract
    const AuctionHouse = await ethers.getContractFactory(
      "AuctionHouseV2",
      owner
    );
    auctionHouse = await AuctionHouse.deploy(WBNB_ADDRESS, artwork.address);
    console.log("auctionHouse address: ", auctionHouse.address);

    // deposit 0.2 WBNB to alice, bob
    const depositByAlice = await wbnb
      .connect(alice)
      .deposit({ value: parseEther(0.01) });
    // wait for transaction to be executed
    await depositByAlice.wait();
    const depositByBob = await wbnb
      .connect(bob)
      .deposit({ value: parseEther(0.01) });
    // wait for transaction to be executed
    await depositByBob.wait();
    // check alice balance of wbnb
    const aliceBalance = await wbnb.balanceOf(alice.address);
    console.log("alice balance: ", aliceBalance);
    // approve WBNB to auctionHouse
    await wbnb.connect(alice).approve(auctionHouse.address, MAX_UINT256);
    await wbnb.connect(bob).approve(auctionHouse.address, MAX_UINT256);
    // set blindbox price
    await artwork.setBlindBoxPrice(parseEther(0.001));
    // set blindbox open fee
    await artwork.setBlindBoxOpenFee(parseEther(0.001));
    // set blindbox buy limit
    await artwork.setBlindBoxBuyLimit(3);
    // add artist
    const addArtiestAlice = await artwork.addArtist(alice.address);
    await addArtiestAlice.wait();
    // mint 3 artworks
    for (let i = 0; i < 3; i++) {
      const mintArt = await artwork.connect(alice).mintArtwork();
      await mintArt.wait(); // wait for transaction to be executed
    }
    // buy blindbox
    const buyBlindBoxByAlice = await artwork
      .connect(alice)
      .buyBlindBox(2, { value: parseEther(0.002) });
    await buyBlindBoxByAlice.wait();
    const buyBlindBoxByBob = await artwork
      .connect(bob)
      .buyBlindBox(1, { value: parseEther(0.001) });
    await buyBlindBoxByBob.wait();
    // open blindbox
    const openBlindBoxByAlice = await artwork
      .connect(alice)
      .openBlindBox(2, { value: parseEther(0.002) });
    await openBlindBoxByAlice.wait();
    const openBlindBoxByBob = await artwork
      .connect(bob)
      .openBlindBox(1, { value: parseEther(0.001) });
    await openBlindBoxByBob.wait();
    // approve artwork to auctionHouse
    // const approveFromAlice = await artwork
    //   .connect(alice)
    //   .setApprovalForAll(auctionHouse.address, true);
    // await approveFromAlice.wait();
    // const approveFromBob = await artwork
    //   .connect(bob)
    //   .setApprovalForAll(auctionHouse.address, true);
    // await approveFromBob.wait();
    const approveFromAlice = await artwork
      .connect(alice)
      .approve(
        auctionHouse.address,
        artwork.tokenOfOwnerByIndex(alice.address, 0)
      );
    await approveFromAlice.wait();
    const approveFromBob = await artwork
      .connect(bob)
      .approve(
        auctionHouse.address,
        artwork.tokenOfOwnerByIndex(bob.address, 0)
      );
    await approveFromBob.wait();
  });

  it("should create an auction!", async () => {
    console.log("owner address: ", owner.address);
    //console.log("auctionHouse address: ", auctionHouse.address);
    const aliceNft = await artwork.getNftListByAddress(alice.address);
    console.log("alice nft: ", aliceNft);
    const startTime = Math.round(Date.now() / 1000) + 60;
    console.log("start time: ", startTime);
    const endTime = Math.round(Date.now() / 1000) + 24 * 60 * 60;
    console.log("end time: ", endTime);
    const auction = await auctionHouse
      .connect(alice)
      .createAuction(aliceNft[0], parseEther(0.001), startTime, endTime);
    await auction.wait();
    console.log(await auctionHouse.getAllAuction());
  });
  it("should join an auction!", async () => {
    const aliceNft = await artwork.getNftListByAddress(alice.address);
    console.log("alice nft: ", aliceNft);
    const startTime = Math.round(Date.now() / 1000) + 1;
    console.log("start time: ", startTime);
    const endTime = Math.round(Date.now() / 1000) + 24 * 60 * 60;
    console.log("end time: ", endTime);
    const auction = await auctionHouse
      .connect(alice)
      .createAuction(aliceNft[0], parseEther(0.001), startTime, endTime);
    await auction.wait();
    // get auction id from alice
    const auctionId = await auctionHouse.getAuctionIdByTokenId(aliceNft[0]);
    console.log("auction id: ", auctionId);
    //Bob can join auction with bid price WBNB
    const joinAuctionByBob = await auctionHouse
      .connect(bob)
      .joinAuction(parseInt(auctionId), parseEther(0.002));
    await joinAuctionByBob.wait();
    console.log("join auction by bob: ", joinAuctionByBob);
    const auctionDetail = await auctionHouse.auction(parseInt(auctionId));
    console.log("auction detail: ", auctionDetail);
    // last bidder should be bob
    expect(auctionDetail.lastBidder).to.equal(bob.address);
  });
  it("should finish auction", async () => {
    const aliceNft = await artwork.getNftListByAddress(alice.address);
    console.log("alice nft: ", aliceNft);
    const startTime = Math.round(Date.now() / 1000) + 3;
    console.log("start time: ", startTime);
    const endTime = Math.round(Date.now() / 1000) + 24 * 60 * 60;
    console.log("end time: ", endTime);
    const auction = await auctionHouse
      .connect(alice)
      .createAuction(aliceNft[0], parseEther(0.001), startTime, endTime);
    await auction.wait();
    // get auction id from alice
    const auctionId = await auctionHouse.getAuctionIdByTokenId(aliceNft[0]);
    console.log("auction id: ", auctionId);
    //Bob can join auction with bid price WBNB
    const joinAuctionByBob = await auctionHouse
      .connect(bob)
      .joinAuction(parseInt(auctionId), parseEther(0.002));
    await joinAuctionByBob.wait();
    // finish auction by alice
    const finishAuction = await auctionHouse
      .connect(alice)
      .finishAuction(auctionId);
    await finishAuction.wait();
    // owner should be bob
    const ownerOfNft = await artwork.ownerOf(aliceNft[0]);
    expect(ownerOfNft).to.equal(bob.address);
  });
  it("should cancel auction", async () => {
    const aliceNft = await artwork.getNftListByAddress(alice.address);
    console.log("alice nft: ", aliceNft);
    const startTime = Math.round(Date.now() / 1000) + 3;
    console.log("start time: ", startTime);
    const endTime = Math.round(Date.now() / 1000) + 24 * 60 * 60;
    console.log("end time: ", endTime);
    const auction = await auctionHouse
      .connect(alice)
      .createAuction(aliceNft[0], parseEther(0.001), startTime, endTime);
    await auction.wait();
    // get auction id from alice
    const auctionId = await auctionHouse.getAuctionIdByTokenId(aliceNft[0]);
    console.log("auction id: ", auctionId);
    //Bob can join auction with bid price WBNB
    const joinAuctionByBob = await auctionHouse
      .connect(bob)
      .joinAuction(parseInt(auctionId), parseEther(0.002));
    await joinAuctionByBob.wait();
    // cancel auction by alice
    const cancelAuction = await auctionHouse
      .connect(alice)
      .cancelAuction(auctionId);
    await cancelAuction.wait();
    // completed should be true
    const auctionDetail = await auctionHouse.auction(parseInt(auctionId));
    expect(auctionDetail.completed).to.equal(true);
  });
});
