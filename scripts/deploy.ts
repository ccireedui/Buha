import { ethers, upgrades } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
  const BuhaToken = await ethers.getContractFactory("BuhaToken");
  const BuhaGuardian = await ethers.getContractFactory("BuhaGuardian");

  const buhaInstance = await upgrades.deployProxy(BuhaToken);
  const guardianInstance = await upgrades.deployProxy(BuhaGuardian);

  await buhaInstance.deployed();
  await guardianInstance.deployed();
  console.log("BuhaToken deployed to:", buhaInstance.address);
  console.log("BuhaGuardian deployed to:", guardianInstance.address);

  const content = {
    BuhaToken: buhaInstance.address,
    BuhaGuardian: guardianInstance.address,
  };
  createAddressJson(
    path.join(__dirname, "/../genAddresses.json"),
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
