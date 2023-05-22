import { ethers, upgrades } from "hardhat";
import fs from "fs";
import path from "path";
import { BuhaToken, BuhaGuardian } from "../genAddresses.json";

async function main() {
  const NewBuhaToken = await ethers.getContractFactory("BuhaTokenV2");
  const NewBuhaGuardian = await ethers.getContractFactory("BuhaGuardianV2");

  const upgradedBuha = await upgrades.upgradeProxy(BuhaToken, NewBuhaToken);
  const upgradedGuardian = await upgrades.upgradeProxy(BuhaGuardian, NewBuhaGuardian);

  console.log("BuhaToken upgraded to:", upgradedBuha.address);
  console.log("BuhaGuardian upgraded to:", upgradedGuardian.address);

  const content = {
    BuhaToken: upgradedBuha.address,
    BuhaGuardian: upgradedGuardian.address,
  };
  createAddressJson(
    path.join(__dirname, "./genAddresses.json"),
    JSON.stringify(content)
  );
}

function createAddressJson(path: string,content: string) {
  try {
    fs.writeFileSync(path, content);
    console.log("Created Contract Address JSON");
  } catch (err) {
    console.error(err);
    return;
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
