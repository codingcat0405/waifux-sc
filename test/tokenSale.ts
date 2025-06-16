import { BigNumber } from "@ethersproject/bignumber";
import { Contract } from "@ethersproject/contracts";
import * as chai from "chai";
import { expect } from "chai";
const chaiAsPromised = require("chai-as-promised");
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";

chai.use(chaiAsPromised);

function parseEther(amount: Number) {
  return ethers.utils.parseUnits(amount.toString(), 18);
}

function parseUsdt(amount: Number) {
  return ethers.utils.parseUnits(amount.toString(), 6);
}

describe("TokenSale Contract", async () => {
  let owner: SignerWithAddress;
  let alice: SignerWithAddress,
    bob: SignerWithAddress,
    carol: SignerWithAddress,
    dave: SignerWithAddress;
  let tokenSale: Contract;
  let xfishToken: Contract;
  
  const USDT_PRICE = 10000; // 1 USDT = 10,000 XFISH
  const ETH_PRICE = 2500;   // 1 ETH = 2,500 USDT
  const MONTH_DURATION = 30 * 24 * 60 * 60; // 30 days in seconds
  
  beforeEach(async () => {
    [owner, alice, bob, carol, dave] = await ethers.getSigners();
    
    // Deploy XFISH token (mock ERC20)
    const MockERC20 = await ethers.getContractFactory("xFish");
    xfishToken = await MockERC20.deploy();
    await xfishToken.deployed();
    
    // Deploy TokenSale contract
    const TokenSale = await ethers.getContractFactory("TokenSale", owner);
    tokenSale = await TokenSale.deploy(
      xfishToken.address,
      USDT_PRICE,
      ETH_PRICE
    );
    await tokenSale.deployed();
    
    // Mint and transfer tokens to TokenSale contract
    const tokenAmount = parseEther(100000000); // 100M tokens
    await xfishToken.mint(owner.address, tokenAmount);
    await xfishToken.transfer(tokenSale.address, tokenAmount);
  });
  
  describe("Deployment", () => {
    it("should set correct initial values", async () => {
      expect(await tokenSale.xfishToken()).to.equal(xfishToken.address);
      expect(await tokenSale.usdtPrice()).to.equal(USDT_PRICE);
      expect(await tokenSale.ethPrice()).to.equal(ETH_PRICE);
      expect(await tokenSale.saleActive()).to.equal(false);
      expect(await tokenSale.owner()).to.equal(owner.address);
    });
    
    it("should revert deployment with invalid parameters", async () => {
      const TokenSale = await ethers.getContractFactory("TokenSale");
      
      await expect(
        TokenSale.deploy(ethers.constants.AddressZero, USDT_PRICE, ETH_PRICE)
      ).to.be.reverted;
      
      await expect(
        TokenSale.deploy(xfishToken.address, 0, ETH_PRICE)
      ).to.be.reverted;
      
      await expect(
        TokenSale.deploy(xfishToken.address, USDT_PRICE, 0)
      ).to.be.reverted;
    });
  });
  
  describe("Sale Management", () => {
    it("should allow owner to start sale", async () => {
      await expect(tokenSale.connect(owner).startSale())
        .to.emit(tokenSale, "SaleStarted");
      expect(await tokenSale.saleActive()).to.equal(true);
    });
    
    it("should revert if non-owner tries to start sale", async () => {
      await expect(
        tokenSale.connect(alice).startSale()
      ).to.be.revertedWith("OwnableUnauthorizedAccount");
    });
    
    it("should revert if sale already active", async () => {
      await tokenSale.startSale();
      await expect(tokenSale.startSale()).to.be.reverted;
    });
    
    it("should allow owner to end sale", async () => {
      await tokenSale.startSale();
      await expect(tokenSale.connect(owner).endSale())
        .to.emit(tokenSale, "SaleEnded");
      expect(await tokenSale.saleActive()).to.equal(false);
    });
    
    it("should revert ending sale if not active", async () => {
      await expect(tokenSale.endSale()).to.be.reverted;
    });
  });
  
  describe("Price Updates", () => {
    it("should allow owner to update prices", async () => {
      const newUsdtPrice = 20000;
      const newEthPrice = 3000;
      
      await expect(
        tokenSale.connect(owner).updatePrices(newUsdtPrice, newEthPrice)
      ).to.emit(tokenSale, "PricesUpdated")
        .withArgs(newUsdtPrice, newEthPrice);
      
      expect(await tokenSale.usdtPrice()).to.equal(newUsdtPrice);
      expect(await tokenSale.ethPrice()).to.equal(newEthPrice);
    });
    
    it("should revert with zero prices", async () => {
      await expect(
        tokenSale.updatePrices(0, ETH_PRICE)
      ).to.be.reverted;
      
      await expect(
        tokenSale.updatePrices(USDT_PRICE, 0)
      ).to.be.reverted;
    });
  });
  
  describe("Token Purchase", () => {
    beforeEach(async () => {
      await tokenSale.startSale();
    });
    
    it("should calculate correct token amount", async () => {
      const ethAmount = parseEther(1);
      const expectedTokens = ethAmount.mul(ETH_PRICE).mul(USDT_PRICE);
      
      const calculatedAmount = await tokenSale.calculateTokenAmount(ethAmount);
      expect(calculatedAmount).to.equal(expectedTokens);
    });
    
    it("should allow users to buy tokens", async () => {
      const ethAmount = parseEther(0.1);
      const expectedTokens = ethAmount.mul(ETH_PRICE).mul(USDT_PRICE);
      const immediateTokens = expectedTokens.mul(10).div(100);
      
      const initialBalance = await xfishToken.balanceOf(alice.address);
      
      await expect(
        tokenSale.connect(alice).buyTokens({ value: ethAmount })
      ).to.emit(tokenSale, "TokensPurchased")
        .withArgs(alice.address, ethAmount, expectedTokens);
      
      // Check immediate 10% transfer
      const newBalance = await xfishToken.balanceOf(alice.address);
      expect(newBalance.sub(initialBalance)).to.equal(immediateTokens);
      
      // Check vesting info
      const vestingInfo = await tokenSale.vestingInfo(alice.address);
      expect(vestingInfo.totalAmount).to.equal(expectedTokens);
      expect(vestingInfo.claimedAmount).to.equal(immediateTokens);
      
      // Check global stats
      expect(await tokenSale.totalEthRaised()).to.equal(ethAmount);
      expect(await tokenSale.totalTokensSold()).to.equal(expectedTokens);
    });
    
    it("should track participants correctly", async () => {
      await tokenSale.connect(alice).buyTokens({ value: parseEther(0.1) });
      await tokenSale.connect(bob).buyTokens({ value: parseEther(0.2) });
      
      expect(await tokenSale.getParticipantCount()).to.equal(2);
      expect(await tokenSale.getParticipant(0)).to.equal(alice.address);
      expect(await tokenSale.getParticipant(1)).to.equal(bob.address);
      expect(await tokenSale.hasParticipated(alice.address)).to.equal(true);
      expect(await tokenSale.hasParticipated(carol.address)).to.equal(false);
    });
    
    it("should handle multiple purchases from same user", async () => {
      const firstPurchase = parseEther(0.1);
      const secondPurchase = parseEther(0.2);
      
      await tokenSale.connect(alice).buyTokens({ value: firstPurchase });
      await tokenSale.connect(alice).buyTokens({ value: secondPurchase });
      
      const vestingInfo = await tokenSale.vestingInfo(alice.address);
      const totalExpected = firstPurchase.add(secondPurchase).mul(ETH_PRICE).mul(USDT_PRICE);
      
      expect(vestingInfo.totalAmount).to.equal(totalExpected);
      expect(await tokenSale.getParticipantCount()).to.equal(1); // Still one participant
    });
    
    it("should revert if sale not active", async () => {
      await tokenSale.endSale();
      await expect(
        tokenSale.connect(alice).buyTokens({ value: parseEther(0.1) })
      ).to.be.reverted;
    });
    
    it("should revert with zero ETH", async () => {
      await expect(
        tokenSale.connect(alice).buyTokens({ value: 0 })
      ).to.be.reverted;
    });
    
    it("should revert if contract has insufficient balance", async () => {
      // Calculate how much ETH would buy all available tokens
      const contractBalance = await xfishToken.balanceOf(tokenSale.address);
      
      // Since we multiply ETH * ETH_PRICE * USDT_PRICE to get tokens,
      // we need ETH = tokens / (ETH_PRICE * USDT_PRICE)
      // But we need a bit more to trigger the insufficient balance
      const ethNeededForAllTokens = contractBalance.div(ETH_PRICE).div(USDT_PRICE);
      const ethToSpend = ethNeededForAllTokens.add(parseEther(0.001)); // Add a bit more
      
      // This should fail because we're trying to buy more tokens than available
      await expect(
        tokenSale.connect(alice).buyTokens({ value: ethToSpend })
      ).to.be.revertedWithCustomError(tokenSale, "InsufficientContractBalance");
    });
  });
  
  describe("Vesting and Claims", () => {
    beforeEach(async () => {
      await tokenSale.startSale();
      // Alice buys tokens
      await tokenSale.connect(alice).buyTokens({ value: parseEther(0.1) });
    });
    
    it("should show correct vesting details initially", async () => {
      const details = await tokenSale.getUserVestingDetails(alice.address);
      const expectedTotal = parseEther(0.1).mul(ETH_PRICE).mul(USDT_PRICE);
      const expectedClaimed = expectedTotal.mul(10).div(100);
      
      expect(details.total).to.equal(expectedTotal);
      expect(details.claimed).to.equal(expectedClaimed);
      expect(details.claimable).to.equal(0);
      expect(details.locked).to.equal(expectedTotal.sub(expectedClaimed));
    });
    
    it("should allow claiming after 1 month", async () => {
      // Fast forward 1 month
      await time.increase(MONTH_DURATION);
      
      const claimable = await tokenSale.getClaimableAmount(alice.address);
      const expectedMonthly = parseEther(0.1).mul(ETH_PRICE).mul(USDT_PRICE).mul(10).div(100);
      
      expect(claimable).to.equal(expectedMonthly);
      
      await expect(
        tokenSale.connect(alice).claimTokens()
      ).to.emit(tokenSale, "TokensClaimed")
        .withArgs(alice.address, expectedMonthly);
    });
    
    it("should handle multiple months correctly", async () => {
      const totalAmount = parseEther(0.1).mul(ETH_PRICE).mul(USDT_PRICE);
      const monthlyAmount = totalAmount.mul(10).div(100);
      
      // Fast forward 3 months
      await time.increase(MONTH_DURATION * 3);
      
      const claimable = await tokenSale.getClaimableAmount(alice.address);
      expect(claimable).to.equal(monthlyAmount.mul(3)); // 3 months * 10%
      
      await tokenSale.connect(alice).claimTokens();
      
      // Check claimed amount (10% immediate + 30% claimed)
      const vestingInfo = await tokenSale.vestingInfo(alice.address);
      expect(vestingInfo.claimedAmount).to.equal(monthlyAmount.mul(4));
    });
    
    it("should handle complete vesting after 9 months", async () => {
      const totalAmount = parseEther(0.1).mul(ETH_PRICE).mul(USDT_PRICE);
      
      // Fast forward 9 months
      await time.increase(MONTH_DURATION * 9);
      
      const claimable = await tokenSale.getClaimableAmount(alice.address);
      const alreadyClaimed = totalAmount.mul(10).div(100); // 10% immediate
      
      expect(claimable).to.equal(totalAmount.sub(alreadyClaimed)); // 90% remaining
      
      await tokenSale.connect(alice).claimTokens();
      
      // All tokens should be claimed
      const vestingInfo = await tokenSale.vestingInfo(alice.address);
      expect(vestingInfo.claimedAmount).to.equal(totalAmount);
      
      // No more claimable
      expect(await tokenSale.getClaimableAmount(alice.address)).to.equal(0);
    });
    
    it("should show correct next release info", async () => {
      const info = await tokenSale.getNextReleaseInfo(alice.address);
      const vestingInfo = await tokenSale.vestingInfo(alice.address);
      const monthlyAmount = vestingInfo.totalAmount.mul(10).div(100);
      
      expect(info.nextReleaseTime).to.equal(vestingInfo.purchaseTime.add(MONTH_DURATION));
      expect(info.nextReleaseAmount).to.equal(monthlyAmount);
    });
    
    it("should revert claim if nothing to claim", async () => {
      await expect(
        tokenSale.connect(bob).claimTokens()
      ).to.be.reverted;
      
      // Alice claims everything available
      await time.increase(MONTH_DURATION * 9);
      await tokenSale.connect(alice).claimTokens();
      
      // Try to claim again
      await expect(
        tokenSale.connect(alice).claimTokens()
      ).to.be.reverted;
    });
  });
  
  describe("Referral Bonus", () => {
    it("should allow owner to transfer referral bonus", async () => {
      const bonusAmount = parseEther(1000);
      const reason = "Level 1 Referral";
      
      await expect(
        tokenSale.connect(owner).transferReferralBonus(alice.address, bonusAmount, reason)
      ).to.emit(tokenSale, "ReferralBonusTransferred")
        .withArgs(alice.address, bonusAmount, reason);
      
      expect(await xfishToken.balanceOf(alice.address)).to.equal(bonusAmount);
    });
    
    it("should revert if non-owner tries to transfer bonus", async () => {
      await expect(
        tokenSale.connect(alice).transferReferralBonus(bob.address, parseEther(100), "test")
      ).to.be.revertedWith("OwnableUnauthorizedAccount");
    });
    
    it("should revert with invalid parameters", async () => {
      await expect(
        tokenSale.transferReferralBonus(ethers.constants.AddressZero, parseEther(100), "test")
      ).to.be.reverted;
      
      await expect(
        tokenSale.transferReferralBonus(alice.address, 0, "test")
      ).to.be.reverted;
    });
    
    it("should revert if insufficient balance", async () => {
      const hugeAmount = parseEther(999999999);
      await expect(
        tokenSale.transferReferralBonus(alice.address, hugeAmount, "test")
      ).to.be.reverted;
    });
  });
  
  describe("Withdrawals", () => {
    beforeEach(async () => {
      await tokenSale.startSale();
      await tokenSale.connect(alice).buyTokens({ value: parseEther(1) });
      await tokenSale.connect(bob).buyTokens({ value: parseEther(2) });
    });
    
    it("should allow owner to withdraw ETH", async () => {
      const contractBalance = await ethers.provider.getBalance(tokenSale.address);
      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);
      
      await tokenSale.connect(owner).withdrawETH();
      
      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);
      const contractBalanceAfter = await ethers.provider.getBalance(tokenSale.address);
      
      expect(contractBalanceAfter).to.equal(0);
      expect(ownerBalanceAfter.sub(ownerBalanceBefore)).to.be.closeTo(
        contractBalance,
        parseEther(0.01) // Account for gas
      );
    });
    
    it("should allow emergency withdraw of tokens", async () => {
      const withdrawAmount = parseEther(10000);
      
      // Get owner balance before withdrawal (which includes initial mint)
      const ownerBalanceBefore = await xfishToken.balanceOf(owner.address);
      
      await expect(
        tokenSale.connect(owner).emergencyWithdraw(xfishToken.address, withdrawAmount)
      ).to.emit(tokenSale, "EmergencyWithdraw")
        .withArgs(xfishToken.address, withdrawAmount);
      
      // Check that owner balance increased by exactly the withdrawn amount
      const ownerBalanceAfter = await xfishToken.balanceOf(owner.address);
      expect(ownerBalanceAfter.sub(ownerBalanceBefore)).to.equal(withdrawAmount);
    });
    
    it("should allow emergency withdraw of ETH", async () => {
      const withdrawAmount = parseEther(1);
      
      await expect(
        tokenSale.connect(owner).emergencyWithdraw(ethers.constants.AddressZero, withdrawAmount)
      ).to.emit(tokenSale, "EmergencyWithdraw")
        .withArgs(ethers.constants.AddressZero, withdrawAmount);
    });
    
    it("should revert if non-owner tries to withdraw", async () => {
      await expect(
        tokenSale.connect(alice).withdrawETH()
      ).to.be.revertedWith("OwnableUnauthorizedAccount");
      
      await expect(
        tokenSale.connect(alice).emergencyWithdraw(xfishToken.address, parseEther(100))
      ).to.be.revertedWith("OwnableUnauthorizedAccount");
    });
  });
  
  describe("Pause Functionality", () => {
    beforeEach(async () => {
      await tokenSale.startSale();
    });
    
    it("should allow owner to pause and unpause", async () => {
      await tokenSale.connect(owner).pause();
      
      // Should revert when paused
      await expect(
        tokenSale.connect(alice).buyTokens({ value: parseEther(0.1) })
      ).to.be.revertedWith("EnforcedPause");
      
      await tokenSale.connect(owner).unpause();
      
      // Should work after unpause
      await expect(
        tokenSale.connect(alice).buyTokens({ value: parseEther(0.1) })
      ).to.not.be.reverted;
    });
    
    it("should block claims when paused", async () => {
      await tokenSale.connect(alice).buyTokens({ value: parseEther(0.1) });
      await time.increase(MONTH_DURATION);
      
      await tokenSale.pause();
      
      await expect(
        tokenSale.connect(alice).claimTokens()
      ).to.be.revertedWith("EnforcedPause");
    });
  });
  
  describe("View Functions", () => {
    beforeEach(async () => {
      await tokenSale.startSale();
      await tokenSale.connect(alice).buyTokens({ value: parseEther(0.5) });
      await tokenSale.connect(bob).buyTokens({ value: parseEther(0.3) });
    });
    
    it("should return correct contract balance", async () => {
      const balance = await tokenSale.getContractXFISHBalance();
      const actualBalance = await xfishToken.balanceOf(tokenSale.address);
      expect(balance).to.equal(actualBalance);
    });
    
    it("should check sufficient balance correctly", async () => {
      const smallAmount = parseEther(1000);
      const hugeAmount = parseEther(999999999);
      
      expect(await tokenSale.hasSufficientBalance(smallAmount)).to.equal(true);
      expect(await tokenSale.hasSufficientBalance(hugeAmount)).to.equal(false);
    });
    
    it("should return correct participant info", async () => {
      expect(await tokenSale.getParticipantCount()).to.equal(2);
      expect(await tokenSale.hasParticipated(alice.address)).to.equal(true);
      expect(await tokenSale.hasParticipated(carol.address)).to.equal(false);
    });
  });
  
  describe("Edge Cases", () => {
    it("should reject direct ETH transfers", async () => {
      await expect(
        owner.sendTransaction({
          to: tokenSale.address,
          value: parseEther(1)
        })
      ).to.be.revertedWith("Use buyTokens function");
    });
    
    it("should handle very small purchases", async () => {
      await tokenSale.startSale();
      
      // Very small amount that still results in tokens
      const tinyAmount = BigNumber.from("1000000000"); // 1 gwei
      const expectedTokens = tinyAmount.mul(ETH_PRICE).mul(USDT_PRICE);
      
      if (expectedTokens.gt(0)) {
        await expect(
          tokenSale.connect(alice).buyTokens({ value: tinyAmount })
        ).to.not.be.reverted;
      }
    });
    
    it("should handle price changes correctly", async () => {
      await tokenSale.startSale();
      
      // Buy with initial prices
      const amount1 = parseEther(0.1);
      await tokenSale.connect(alice).buyTokens({ value: amount1 });
      
      // Change prices
      await tokenSale.updatePrices(20000, 3000);
      
      // Buy with new prices
      const amount2 = parseEther(0.1);
      await tokenSale.connect(bob).buyTokens({ value: amount2 });
      
      // Check different token amounts
      const aliceInfo = await tokenSale.vestingInfo(alice.address);
      const bobInfo = await tokenSale.vestingInfo(bob.address);
      
      expect(aliceInfo.totalAmount).to.not.equal(bobInfo.totalAmount);
    });
  });
  
  describe("Integration Test", () => {
    it("should handle complete user journey", async () => {
      // Start sale
      await tokenSale.startSale();
      
      // Alice buys tokens
      const purchaseAmount = parseEther(1);
      await tokenSale.connect(alice).buyTokens({ value: purchaseAmount });
      
      // Alice receives referral bonus
      await tokenSale.transferReferralBonus(alice.address, parseEther(5000), "Friend referral");
      
      // Fast forward and claim monthly
      for (let i = 1; i <= 9; i++) {
        await time.increase(MONTH_DURATION);
        
        const claimable = await tokenSale.getClaimableAmount(alice.address);
        if (claimable.gt(0)) {
          await tokenSale.connect(alice).claimTokens();
        }
      }
      
      // Check final state
      const vestingInfo = await tokenSale.vestingInfo(alice.address);
      expect(vestingInfo.claimedAmount).to.equal(vestingInfo.totalAmount);
      
      // Owner withdraws funds
      await tokenSale.withdrawETH();
      
      // End sale
      await tokenSale.endSale();
    });
  });
});