import { BigNumber } from "@ethersproject/bignumber";
import { Contract } from "@ethersproject/contracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import * as chai from "chai";
import { expect } from "chai";
const chaiAsPromised = require("chai-as-promised");
import { ethers } from "hardhat";

chai.use(chaiAsPromised);

function parseEther(amount: Number) {
  return ethers.utils.parseUnits(amount.toString(), 18);
}

describe("MarketPlace Contract", () => {
  let owner: SignerWithAddress;
  let alice: SignerWithAddress,
    bob: SignerWithAddress,
    carol: SignerWithAddress,
    dave: SignerWithAddress;
  let artwork: Contract, marketplace: Contract;

  beforeEach(async () => {
    //await ethers.provider.send("hardhat_reset", []);

    [owner, alice, bob, carol, dave] = await ethers.getSigners();

    const Artwork = await ethers.getContractFactory("ArtworkV2", owner);
    artwork = await Artwork.deploy();

    const Marketplace = await ethers.getContractFactory("MarketplaceV2", owner);
    marketplace = await Marketplace.deploy(artwork.address);

    await artwork.setBlindBoxPrice(parseEther(0.005));
    await artwork.setBlindBoxOpenFee(parseEther(0.001));
    await artwork.setBlindBoxBuyLimit(3);
    // add artist for minting
    const _addArtist = await artwork.addArtist(alice.address);
    await artwork.addArtist(bob.address);
    //await _addArtist.wait(); // wait for transaction to be mined
    // mint 9 artworks
    let mintArt;
    for (let i = 0; i < 3; i++) {
      mintArt = await artwork.connect(alice).mintArtwork();
    }
    // await mintArt.wait(); // wait for transaction to be mined
    // await mintArt.wait();
    // await mintArt.wait();
    // wait for transaction to be mined

    //buy 3 blind boxes for each user - alice, bob, carol
    const buyFromAlice = await artwork
      .connect(alice)
      .buyBlindBox(3, { value: parseEther(0.005 * 3) });
    //await buyFromAlice.wait(15); // wait for transaction to be mined
    const openBoxAlice = await artwork
      .connect(alice)
      .openBlindBox(3, { value: parseEther(0.001 * 3) });

    // approve marketplace to transfer NFTs
    const approveFromAlice = await artwork
      .connect(alice)
      .setApprovalForAll(marketplace.address, true);
    //await approveFromAlice.wait(); // wait for transaction to be approved
    const approveFromBob = await artwork
      .connect(bob)
      .setApprovalForAll(marketplace.address, true);
    //await approveFromBob.wait(); // wait for transaction to be approved
  });

  it("should list NFT", async () => {
    const marketBalanceBefore = await artwork.balanceOf(marketplace.address);
    console.log("marketBalance =", marketBalanceBefore.toString());
    // List 2 NFTs to marketplace
    const listNFT = await marketplace
      .connect(alice)
      .listNft(
        artwork.tokenOfOwnerByIndex(alice.address, 0),
        parseEther(0.002)
      );
    await listNFT.wait(); // wait for transaction to be listed
    const marketBalanceAfter = await artwork.balanceOf(marketplace.address);
    console.log("marketBalance after = ", marketBalanceAfter.toString());
    const expected = BigNumber.from(1);
    expect(await marketBalanceAfter.sub(marketBalanceBefore)).equal(expected);
  });

  it("should unlist NFT", async () => {
    // Alice list 2 NFTs to marketplace
    // get balance of alice before listing
    const aliceBalanceBefore = await artwork.balanceOf(alice.address);
    console.log("aliceBalanceBefore = ", aliceBalanceBefore.toString());
    const aliceFirstNFT = await artwork.tokenOfOwnerByIndex(alice.address, 0);
    const aliceSecondNFT = await artwork.tokenOfOwnerByIndex(alice.address, 1);
    console.log("aliceFirstNFT = ", aliceFirstNFT.toString());
    console.log("aliceSecondNFT = ", aliceSecondNFT.toString());
    const listNFT1 = await marketplace
      .connect(alice)
      .listNft(
        artwork.tokenOfOwnerByIndex(alice.address, 0),
        parseEther(0.002)
      );
    await listNFT1.wait(); // wait for transaction to be listed
    console.log("listNFT1 = ", listNFT1);
    console.log("OK");
    const listNFT2 = await marketplace
      .connect(alice)
      .listNft(
        artwork.tokenOfOwnerByIndex(alice.address, 1),
        parseEther(0.002)
      );
    await listNFT2.wait(); // wait for transaction to be listed
    console.log("listNFT2 = ", listNFT2);
    // // Bob list 1 NFT to marketplace
    // const bobFirstNFT = await artwork.tokenOfOwnerByIndex(bob.address, 0);
    // await marketplace
    //   .connect(bob)
    //   .listNft(artwork.tokenOfOwnerByIndex(bob.address, 0), 1);

    // Bob unlist Alice's NFT
    await expect(
      marketplace.connect(bob).unlistNft(aliceFirstNFT)
    ).revertedWith("You are not the owner of this NFT");

    // Alice unlist 1 NFT 2 times
    const unlistNFT = await marketplace.connect(alice).unlistNft(aliceFirstNFT);
    await unlistNFT.wait(); // wait for transaction to be mined
    console.log("unlistNFT = ", unlistNFT);
    await expect(
      marketplace.connect(alice).unlistNft(aliceFirstNFT)
    ).revertedWith("You are not the owner of this NFT");

    expect(await artwork.balanceOf(alice.address)).equal(2);
    expect(await artwork.balanceOf(marketplace.address)).equal(1);
  });

  it("should buy NFT", async () => {
    //const initBalance = await wbnb.balanceOf(alice.address);
    //const marketInitBalance = await wbnb.balanceOf(marketplace.address);
    const bobFirstNFT = await artwork.tokenOfOwnerByIndex(bob.address, 0);
    //console.log("bobFirstNFT = ", bobFirstNFT.toString());
    // console.log("bobFirstNFT = ", bobFirstNFT.toString());
    // Alice list 2 NFTs to marketplace with price 5000
    const aliceFirstNFT = await artwork.tokenOfOwnerByIndex(alice.address, 0);
    console.log("aliceFirstNFT = ", aliceFirstNFT.toString());
    const aliceSecondNFT = await artwork.tokenOfOwnerByIndex(alice.address, 1);
    console.log("aliceSecondNFT = ", aliceSecondNFT.toString());
    const aliceThirdNFT = await artwork.tokenOfOwnerByIndex(alice.address, 2);
    console.log("aliceThirdNFT = ", aliceThirdNFT.toString());
    const listNFT1 = await marketplace
      .connect(alice)
      .listNft(aliceFirstNFT, parseEther(0.002));
    // list second NFT
    const listNFT2 = await marketplace
      .connect(alice)
      .listNft(aliceSecondNFT, parseEther(0.002));

    const listed = await marketplace.listDetail(aliceFirstNFT);
    console.log("listed = ", listed);
    //await listNFT1.wait(); // wait for transaction to be listed
    //await listNFT2.wait(); // wait for transaction to be listed
    // console.log(await marketplace.functions['getListedNft(address)'](player.address));
    //Bob buy Alice's NFT on marketplace
    await expect(
      marketplace
        .connect(bob)
        .buyNft(aliceFirstNFT, parseEther(0.002), { value: parseEther(0.001) })
    ).revertedWith("Dont have enough money to buy this NFT!");

    await expect(
      marketplace.connect(alice).buyNft(bobFirstNFT, parseEther(0.002), {
        value: parseEther(0.002),
        from: alice.address,
      })
    ).revertedWith("This NFT does not exist in Marketplace to buy!");
    //transfer alice second nft to marketplace contract
    await artwork
      .connect(alice)
      .safeTransferFrom(alice.address, marketplace.address, aliceSecondNFT);
    await expect(
      marketplace.connect(bob).buyNft(aliceSecondNFT, parseEther(0.002), {
        value: parseEther(0.002),
      })
    ).revertedWith("This NFT is not listed");

    await expect(
      marketplace.connect(alice).buyNft(aliceFirstNFT, parseEther(0.002), {
        value: parseEther(0.002),
      })
    ).revertedWith("You are the owner of this NFT");
    await expect(
      marketplace.connect(alice).buyNft(aliceFirstNFT, parseEther(0.001), {
        value: parseEther(0.002),
      })
    ).revertedWith("You need to pay more money to buy this NFT");
    //buy alice's NFT
    await marketplace.connect(bob).buyNft(aliceFirstNFT, parseEther(0.002), {
      value: parseEther(0.002),
    });
    expect(await artwork.balanceOf(alice.address)).equal(2);
    expect(await artwork.balanceOf(bob.address)).equal(4);
    // remove alice's NFT from marketplace
    await marketplace.connect(alice).unlistNft(aliceFirstNFT);
    // get list bob's NFT
    const listNFT = await marketplace.getListedNft(alice.address);
    console.log("listNFT = ", listNFT);
  });
});
