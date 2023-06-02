import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { BigNumber } from "ethers";
import { any } from "hardhat/internal/core/params/argumentTypes";

describe("BuhaToken", function () {
  async function deployBuhaTokenFixture() {
    const BuhaToken = await ethers.getContractFactory("BuhaToken");
    const buhaToken = await upgrades.deployProxy(BuhaToken);
    return { buhaToken };
  }

  this.beforeEach(async function () {
    const accounts = await ethers.getSigners();
    this.owner = accounts[0];
    this.otherAccount = accounts[1];
    this.mintingAccount = accounts[2];
    this.stakingAccount = accounts[3];

    const BuhaToken = await ethers.getContractFactory("BuhaToken");
    this.buhaInstance = await upgrades.deployProxy(BuhaToken);
    await this.buhaInstance.deployed();

    const days = ethers.utils.parseUnits("100", 0);
    await this.buhaInstance.connect(this.stakingAccount).startMinting(days);
    const mintInfo = await this.buhaInstance.userMints(
      this.stakingAccount.address
    );
    const maturityTs = ethers.utils.hexValue(mintInfo.maturityTs);
    await time.increaseTo(maturityTs);
    await this.buhaInstance.connect(this.stakingAccount).claim();

    await this.buhaInstance.connect(this.mintingAccount).startMinting(days);
  });

  it("Should get upgraded", async function () {
    const BuhaTokenV2 = await ethers.getContractFactory("BuhaToken");
    const buhaInstanceUpgraded = await upgrades.upgradeProxy(
      this.buhaInstance.address,
      BuhaTokenV2
    );
    expect(await buhaInstanceUpgraded.name()).to.equal("Buha Token");
  });

  it("Shouldn't be able to upgrade if not owner", async function () {
    const BuhaTokenV2 = await ethers.getContractFactory("BuhaToken");
    await expect(
      upgrades.upgradeProxy(
        this.buhaInstance.address,
        BuhaTokenV2.connect(this.otherAccount)
      )
    ).to.be.revertedWith(
      `AccessControl: account ${this.otherAccount.address.toLowerCase()} is missing role ${await this.buhaInstance.UPGRADER_ROLE()}`
    );
  });

  it("Should check if the owner has UPGRADER_ROLE", async function () {
    expect(
      await this.buhaInstance.hasRole(
        await this.buhaInstance.UPGRADER_ROLE(),
        this.owner.address
      )
    ).to.equal(true);
  });

  it("Should return the right name and symbol", async function () {
    expect(await this.buhaInstance.name()).to.equal("Buha Token");
    expect(await this.buhaInstance.symbol()).to.equal("BUHA");
  });

  it("Should return the right decimals", async function () {
    expect(await this.buhaInstance.decimals()).to.equal(18);
  });

  it("Should emit MintStarted event when minting", async function () {
    const days = ethers.utils.parseUnits("100", 0);
    const activeMintersCount = await this.buhaInstance.activeMinters();
    await expect(
      this.buhaInstance.connect(this.otherAccount).startMinting(days)
    )
      .to.emit(this.buhaInstance, "MintStarted")
      .withArgs(this.otherAccount.address, days, anyValue);
    expect(await this.buhaInstance.activeMinters()).to.equal(
      activeMintersCount.add(1)
    );
  });

  it("Should revert term exceeds max value", async function () {
    const days = ethers.utils.parseUnits("100000", 0);
    await expect(
      this.buhaInstance.connect(this.otherAccount).startMinting(days)
    ).to.be.revertedWith("BUHA: Term more than current max term");
  });

  it("Should emit Claimed event upon claiming reward", async function () {
    const activeMintersCount = await this.buhaInstance.activeMinters();
    const mintInfo = await this.buhaInstance.userMints(
      this.mintingAccount.address
    );
    const maturityTs = ethers.utils.hexValue(mintInfo.maturityTs);
    await time.increaseTo(maturityTs);
    await expect(this.buhaInstance.connect(this.mintingAccount).claim())
      .to.emit(this.buhaInstance, "Claimed")
      .withArgs(this.mintingAccount.address, anyValue);
    expect(await this.buhaInstance.activeMinters()).to.equal(
      activeMintersCount.sub(1)
    );
    expect(
      await this.buhaInstance.userMints(this.mintingAccount.address)
    ).to.not.equal(mintInfo);
  });

  it("Should revert if claiming before maturity", async function () {
    await expect(
      this.buhaInstance.connect(this.mintingAccount).claim()
    ).to.be.revertedWith("BUHA: Mint maturity not reached");
  });

  it("Should be able to claim the mint early", async function () {
    const activeMintersCount = await this.buhaInstance.activeMinters();
    const mintInfo = await this.buhaInstance.userMints(
      this.mintingAccount.address
    );
    await expect(this.buhaInstance.connect(this.mintingAccount).claimEarly())
      .to.emit(this.buhaInstance, "Claimed")
      .withArgs(this.mintingAccount.address, anyValue);
    expect(await this.buhaInstance.activeMinters()).to.equal(
      activeMintersCount.sub(1)
    );
    expect(
      await this.buhaInstance.userMints(this.mintingAccount.address)
    ).to.not.equal(mintInfo);
  });

  it("Should revert if earlyClaiming after maturity", async function () {
    const mintInfo = await this.buhaInstance.userMints(
      this.mintingAccount.address
    );
    const maturityTs = ethers.utils.hexValue(mintInfo.maturityTs);
    await time.increaseTo(maturityTs);
    await expect(
      this.buhaInstance.connect(this.mintingAccount).claimEarly()
    ).to.be.revertedWith("BUHA: Mint maturity reached");
  });

  it("Should emit Staked event", async function () {
    const preStakingBalance = await this.buhaInstance.balanceOf(
      this.stakingAccount.address
    );
    const preStakingCount = await this.buhaInstance.activeStakes();
    const preStakingAmount = await this.buhaInstance.totalBuhaStaked();
    const amount = ethers.utils.parseUnits("100", 18);
    const stakingTerm = ethers.utils.parseUnits("50", 0);
    await expect(
      this.buhaInstance.connect(this.stakingAccount).stake(amount, stakingTerm)
    )
      .to.emit(this.buhaInstance, "Staked")
      .withArgs(this.stakingAccount.address, amount, stakingTerm);
    expect(
      await this.buhaInstance.balanceOf(this.stakingAccount.address)
    ).to.equal(preStakingBalance.sub(amount));
    expect(await this.buhaInstance.activeStakes()).to.equal(
      preStakingCount.add(1)
    );
    expect(await this.buhaInstance.totalBuhaStaked()).to.equal(
      preStakingAmount.add(amount)
    );
  });

  it("Should revert if staking amount exceeds balance", async function () {
    const amount = ethers.utils.parseUnits("100000", 18);
    const stakingTerm = ethers.utils.parseUnits("50", 0);
    await expect(
      this.buhaInstance.connect(this.stakingAccount).stake(amount, stakingTerm)
    ).to.be.revertedWith("BUHA: Insufficient balance");
  });

  it("Should revert if staking amount is below minimum staking value", async function () {
    const amount = ethers.utils.parseUnits("0", 0);
    const stakingTerm = ethers.utils.parseUnits("50", 0);
    await expect(
      this.buhaInstance.connect(this.stakingAccount).stake(amount, stakingTerm)
    ).to.be.revertedWith("BUHA: Below min stake");
  });

  it("Should revert if staking term exceeds max value", async function () {
    const amount = ethers.utils.parseUnits("100", 18);
    const stakingTerm = ethers.utils.parseUnits("1001", 0);
    await expect(
      this.buhaInstance.connect(this.stakingAccount).stake(amount, stakingTerm)
    ).to.be.revertedWith("BUHA: Above max stake term");
  });

  it("Should revert if the account is already staking", async function () {
    const amount = ethers.utils.parseUnits("10", 18);
    const stakingTerm = ethers.utils.parseUnits("50", 0);
    await this.buhaInstance
      .connect(this.stakingAccount)
      .stake(amount, stakingTerm);
    await expect(
      this.buhaInstance.connect(this.stakingAccount).stake(amount, stakingTerm)
    ).to.be.revertedWith("BUHA: Stake exists");
  });

  it("Should emit Withdrawn event with zero reward amount", async function () {
    const amount = ethers.utils.parseUnits("100", 18);
    const stakingTerm = ethers.utils.parseUnits("50", 0);
    await this.buhaInstance
      .connect(this.stakingAccount)
      .stake(amount, stakingTerm);
    const preWithdrawCount = await this.buhaInstance.activeStakes();
    const preWithdrawAmount = await this.buhaInstance.totalBuhaStaked();
    await expect(this.buhaInstance.connect(this.stakingAccount).withdraw())
      .to.emit(this.buhaInstance, "Withdrawn")
      .withArgs(this.stakingAccount.address, amount, 0);
    expect(await this.buhaInstance.activeStakes()).to.equal(
      preWithdrawCount.sub(1)
    );
    expect(await this.buhaInstance.totalBuhaStaked()).to.equal(
      preWithdrawAmount.sub(amount)
    );
  });

  it("Should emit Withdrawn event with full reward amount", async function () {
    const amount = ethers.utils.parseUnits("100", 18);
    const stakingTerm = ethers.utils.parseUnits("50", 0);
    await this.buhaInstance
      .connect(this.stakingAccount)
      .stake(amount, stakingTerm);
    const stakingInfo = await this.buhaInstance.userStakes(
      this.stakingAccount.address
    );
    await time.increaseTo(ethers.utils.hexValue(stakingInfo.maturityTs));
    await expect(this.buhaInstance.connect(this.stakingAccount).withdraw())
      .to.emit(this.buhaInstance, "Withdrawn")
      .withArgs(this.stakingAccount.address, amount, anyValue);
  });

  it("Should emit Withdrawn event with partial reward amount", async function () {
    const amount = ethers.utils.parseUnits("100", 18);
    const stakingTerm = ethers.utils.parseUnits("50", 0);
    await this.buhaInstance
      .connect(this.stakingAccount)
      .stake(amount, stakingTerm);
    await expect(this.buhaInstance.connect(this.stakingAccount).withdrawEarly())
      .to.emit(this.buhaInstance, "Withdrawn")
      .withArgs(this.stakingAccount.address, amount, anyValue);
  });

  it("Should emit both Claimed and Staked events for claimAndStake function", async function () {
    const percentage = ethers.utils.parseUnits("20", 0);
    const stakingTerm = ethers.utils.parseUnits("50", 0);
    const mintInfo = await this.buhaInstance.userMints(
      this.mintingAccount.address
    );
    const maturityTs = ethers.utils.hexValue(mintInfo.maturityTs);
    await time.increaseTo(maturityTs);
    await expect(
      this.buhaInstance
        .connect(this.mintingAccount)
        .claimAndStake(percentage, stakingTerm)
    )
      .to.emit(this.buhaInstance, "Claimed")
      .to.emit(this.buhaInstance, "Staked");
  });

  it("Should burn user's tokens if the amount is equal or below user's balance", async function () {
    const amount = await this.buhaInstance.balanceOf(
      this.stakingAccount.address
    );
    await this.buhaInstance.connect(this.stakingAccount).burn(amount);

    const userBurns = await this.buhaInstance.userBurns(
      this.stakingAccount.address
    );
    expect(userBurns).to.equal(amount);

    const userBalance = await this.buhaInstance.balanceOf(
      this.stakingAccount.address
    );
    expect(userBalance).to.equal(0);
  });

  it("Should revert if the amount is more than user's balance", async function () {
    const amount = await this.buhaInstance.balanceOf(
      this.stakingAccount.address
    );
    await expect(
      this.buhaInstance.connect(this.stakingAccount).burn(amount.add(1))
    ).to.be.revertedWith("ERC20: burn amount exceeds balance");
    const userBurns = await this.buhaInstance.userBurns(
      this.stakingAccount.address
    );
    expect(userBurns).to.equal(0);

    const userBalance = await this.buhaInstance.balanceOf(
      this.stakingAccount.address
    );
    expect(userBalance).to.equal(amount);
  });
});
