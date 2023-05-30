import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";

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

        const BuhaToken = await ethers.getContractFactory("BuhaToken");
        this.buhaInstance = await upgrades.deployProxy(BuhaToken);
        await this.buhaInstance.deployed();
    });

    it("Should get upgraded", async function () {
        const BuhaTokenV2 = await ethers.getContractFactory("BuhaToken");
        const buhaInstanceUpgraded = await upgrades.upgradeProxy(this.buhaInstance.address, BuhaTokenV2);
        expect(await buhaInstanceUpgraded.name()).to.equal("Buha Token");
    });

    it("Shouldn't be able to upgrade if not owner", async function () {
        const BuhaTokenV2 = await ethers.getContractFactory("BuhaToken");
        await expect(upgrades.upgradeProxy(this.buhaInstance.address, BuhaTokenV2.connect(this.otherAccount))).to.be.revertedWith(`AccessControl: account ${this.otherAccount.address.toLowerCase()} is missing role ${await this.buhaInstance.UPGRADER_ROLE()}`);
    });

    it("Should check if the owner has UPGRADER_ROLE", async function () {
        expect(await this.buhaInstance.hasRole(await this.buhaInstance.UPGRADER_ROLE(), this.owner.address)).to.equal(true);
    });

    it("Should return the right name and symbol", async function () {
        expect(await this.buhaInstance.name()).to.equal("Buha Token");
        expect(await this.buhaInstance.symbol()).to.equal("BUHA");
    });

    it("Should return the right decimals", async function () {
        expect(await this.buhaInstance.decimals()).to.equal(18);
    });

    it("Should return the right totalSupply", async function () {
        expect(await this.buhaInstance.totalSupply()).to.equal(0);
    });
});