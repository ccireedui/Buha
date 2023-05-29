import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";import { expect } from "chai";
import { ethers, upgrades } from "hardhat";


describe("BuhaToken", function () {

  this.beforeEach(async function () {
    const BuhaToken = await ethers.getContractFactory("BuhaToken");
    this.buhaInstance = await upgrades.deployProxy(BuhaToken);
    await this.buhaInstance.deployed();
  });

  it("Should return the right name and symbol", async function () {
    expect(await this.buhaInstance.name()).to.equal("BuhaToken");
    expect(await this.buhaInstance.symbol()).to.equal("BUHA");
  });

  it("Should return the right decimals", async function () {
    expect(await this.buhaInstance.decimals()).to.equal(18);
  });

  it("Should return the right totalSupply", async function () {
    expect(await this.buhaInstance.totalSupply()).to.equal(0);
  });
});