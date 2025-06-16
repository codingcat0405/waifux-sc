import {loadFixture} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {describe} from "mocha";


describe("Lottery Game", function () {

    async function deployContracts() {
        const [deployer, alice, bob] = await ethers.getSigners();
        console.log("Deploying contracts with the account:", deployer.address);
        const address0 = '0x0000000000000000000000000000000000000000';
        // deploy usdt token
        const usdtTokenFactory = await ethers.getContractFactory("USDT");
        const usdtToken = await usdtTokenFactory.deploy();
        await usdtToken.waitForDeployment();
        console.log("1. USDT Token address to:", usdtToken.target);
        // deploy Fish token
        const fishTokenFactory = await ethers.getContractFactory("xFish");
        const fishToken = await fishTokenFactory.deploy();
        await fishToken.waitForDeployment();
        console.log("2. Fish Token address to:", fishToken.target);
        // deploy Fishing game contract
        const fishingGameFactory = await ethers.getContractFactory("FishingGame");
        const fishingGame = await fishingGameFactory.deploy(usdtToken.target, fishToken.target, deployer.address);
        await fishingGame.waitForDeployment();
        console.log("3. Fishing Game address to:", fishingGame.target);
        return { usdtToken, fishToken, fishingGame, deployer, alice, bob, address0 };
    }

    describe("Deployment", function () {
        it.skip("Should user can buy items", async function () {
            const { deployer, address0, usdtToken, fishToken, fishingGame, alice } = await loadFixture(deployContracts);
            // approve usdt token to fishing game
            await usdtToken.connect(deployer).approve(fishingGame.target, ethers.parseEther("100000000"));
            // approve fish token to fishing game
            await fishToken.connect(deployer).approve(fishingGame.target, ethers.parseEther("100000000"));
            // buy item with usdt token - 10$ per bait items
            await fishingGame.connect(deployer).buyItems(usdtToken.target, 0, 10, ethers.parseEther("100"));
            // check balance of deployer of bait
            const baitDeployerBalance = await fishingGame.balanceOf(deployer.address, 0);
            expect(baitDeployerBalance).to.equal(10);
            console.log("Bait balance of deployer:", baitDeployerBalance.toString());

            // buy item with fish token - 1000 per bait items
            await fishingGame.connect(deployer).buyItems(fishToken.target, 0, 1, ethers.parseEther("1000"));
            // check balance of deployer of bait
            const baitDeployerBalance2 = await fishingGame.balanceOf(deployer.address, 0);
            expect(baitDeployerBalance2).to.equal(11);
            console.log("Bait balance of deployer 2:", baitDeployerBalance2.toString());
            // buy with native token
            await fishingGame.connect(deployer).buyItems(address0, 0, 10, 0, {
                value: ethers.parseEther("0.1")
            });
            // check balance of deployer of bait
            const baitDeployerBalance3 = await fishingGame.balanceOf(deployer.address, 0);
            expect(baitDeployerBalance3).to.equal(21);
            console.log("Bait balance of deployer 3:", baitDeployerBalance3.toString());
        });

        it("Should allow owner to burn items", async function () {
            const { deployer, address0, usdtToken, fishToken, fishingGame, alice, bob } = await loadFixture(deployContracts);
            // transfer 1000 usdt to alice
            await usdtToken.connect(deployer).transfer(alice.address, ethers.parseEther("1000"));
            // approve usdt token to fishing game
            await usdtToken.connect(alice).approve(fishingGame.target, ethers.parseEther("100000000"));
            // buy item with usdt token - 10$ per bait items
            await fishingGame.connect(alice).buyItems(usdtToken.target, 0, 10, ethers.parseEther("100"));
            // check balance of alice of bait
            const baitAliceBalance = await fishingGame.balanceOf(alice.address, 0);
            expect(baitAliceBalance).to.equal(10);
            console.log("Bait balance of alice:", baitAliceBalance.toString());
            // alice can burn bait of alice
            await fishingGame.connect(alice).burn(alice.address, 0, 3);
            // check balance of alice of bait
            const baitAliceBalance2 = await fishingGame.balanceOf(alice.address, 0);
            expect(baitAliceBalance2).to.equal(7);
            console.log("Bait balance of alice 2:", baitAliceBalance2.toString());
            // alice can burn batch bait of alice
            await fishingGame.connect(alice).burnBatch(alice.address, [0, 0, 0], [1, 2, 3]);
            const baitAliceBalance3 = await fishingGame.balanceOf(alice.address, 0);
            expect(baitAliceBalance3).to.equal(1);
        });
    });

});