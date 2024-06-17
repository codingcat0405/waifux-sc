import { BigNumber } from "@ethersproject/bignumber";
import { Contract } from "@ethersproject/contracts";
import * as chai from "chai";
import { expect } from "chai";
const chaiAsPromised = require("chai-as-promised");
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";

chai.use(chaiAsPromised);

function parseEther(amount: Number) {
  return ethers.utils.parseUnits(amount.toString(), 18);
}

describe("Artwork Contract V2", async () => {
  let owner: SignerWithAddress;
  let alice: SignerWithAddress,
    bob: SignerWithAddress,
    carol: SignerWithAddress,
    dave: SignerWithAddress;
  let artwork: Contract;

  beforeEach(async () => {
    //await ethers.provider.send("hardhat_reset", []);

    [owner, alice, bob, carol, dave] = await ethers.getSigners();
    console.log("owner address = ", owner.address);
    console.log("alice address = ", alice.address);

    const Artwork = await ethers.getContractFactory("ArtworkV2", owner);
    artwork = await Artwork.deploy();

    await artwork.setBlindBoxPrice(parseEther(0.005));
    await artwork.setBlindBoxOpenFee(parseEther(0.001));
    await artwork.setBlindBoxBuyLimit(3);
  });
  //test shoud revert if call mintArtwork is not artists
  it("should revert if call mintArtwork is not artists", async () => {
    console.log("alice address = ", alice.address);
    await expect(artwork.connect(alice).mintArtwork()).to.be.revertedWith(
      "Only artists can mint"
    );
  });
  it("should add and remove artist", async () => {
    await artwork.connect(owner).addArtist(alice.address);
    await artwork.connect(owner).removeArtist(alice.address);
    await artwork.connect(owner).removeArtist(bob.address);
  });
  //test should mintArtwork
  it("should mintArtwork", async () => {
    const _addArtist = await artwork.connect(owner).addArtist(alice.address);
    // wait for transaction to be executed
    await _addArtist.wait();
    // get artist list
    const artists = await artwork.getArtists();
    console.log("artists = ", artists);
    const resultMint = await artwork.connect(alice).mintArtwork();
    // get token id from hash of transaction
    const mintTxReceipt = await resultMint.wait();
    const transferEvent = artwork.interface.parseLog(mintTxReceipt.events[0]);
    const tokenId = transferEvent.args.tokenId;
    console.log("token id = ", tokenId.toString());
    //first token id should be 0
    expect(tokenId).to.be.equal(BigNumber.from(0));
  });

  it("should revert if removed", async () => {
    const addArtist = await artwork.connect(owner).addArtist(alice.address);
    await addArtist.wait(); // wait for transaction to be executed
    const resultMint = await artwork.connect(alice).mintArtwork();
    await resultMint.wait(); // wait for transaction to be executed
    console.log(await artwork.getArtists());

    const resultRemove = await artwork
      .connect(owner)
      .removeArtist(alice.address);
    await resultRemove.wait(); // wait for transaction to be executed
    console.log(await artwork.getArtists());
    await expect(artwork.connect(alice).mintArtwork()).revertedWith(
      "Only artists can mint"
    );
  });

  it("should open blind box", async () => {
    await artwork.connect(owner).addArtist(alice.address);
    await artwork.connect(owner).addArtist(bob.address);
    const _addArtist = await artwork.connect(owner).addArtist(carol.address);
    // wait for transaction to be executed
    await _addArtist.wait();
    // get artist list
    const artists = await artwork.getArtists();
    console.log("artists = ", artists);
    for (let i = 0; i < 3; i++) {
      await artwork.connect(alice).mintArtwork();
      await artwork.connect(bob).mintArtwork();
      await artwork.connect(carol).mintArtwork();
    }
    await expect(
      artwork.connect(dave).openBlindBox(3, { value: parseEther(0.001 * 3) })
    ).revertedWith("Not enough blind boxes to open");

    const resultBuy = await artwork
      .connect(dave)
      .buyBlindBox(2, { value: parseEther(0.005 * 2) });
    await resultBuy.wait(); // wait for transaction to be executed
    //console.log("resultBuy =", resultBuy);
    // //for loop 3 times
    for (let i = 0; i < 2; i++) {
      const openBox = await artwork
        .connect(dave)
        .openBlindBox(1, { value: parseEther(0.001) });
      await openBox.wait(); // wait for transaction to be executed
      const tokenid = await artwork.list(dave.address);
      console.log("token id = ", parseInt(tokenid[i].toString()));
    }

    // //await artwork.connect(dave).openBlindBox(3, { value: parseEther(0.01 * 3) });

    console.log("token id list = ", await artwork.list(dave.address));

    console.log(await artwork.getArtists());
  });
  it("withdraw all balance of the contract to owner", async () => {
    await artwork.connect(owner).addArtist(alice.address);
    await artwork.connect(owner).addArtist(bob.address);
    const _addArtist = await artwork.connect(owner).addArtist(carol.address);
    // wait for transaction to be executed
    await _addArtist.wait();
    // get artist list
    const artists = await artwork.getArtists();
    console.log("artists = ", artists);
    for (let i = 0; i < 2; i++) {
      await artwork.connect(alice).mintArtwork();
      await artwork.connect(bob).mintArtwork();
      await artwork.connect(carol).mintArtwork();
    }
    const resultBuy = await artwork
      .connect(dave)
      .buyBlindBox(2, { value: parseEther(0.005 * 2) });
    await resultBuy.wait(); // wait for transaction to be executed
    const resultWithdraw = await artwork.connect(owner).withdraw();
    await resultWithdraw.wait(); // wait for transaction to be executed
    //console.log("resultWithdraw =", resultWithdraw);
    // console.log(
    //   "owner balance = ",
    //   await ethers.provider.getBalance(owner.address)
    // );
  });
});
