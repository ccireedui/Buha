import { ethers, upgrades } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
  const BuhaToken = await ethers.getContractFactory("BuhaToken");

  const instance = await upgrades.deployProxy(BuhaToken);

  await instance.deployed();
  console.log("BuhaToken deployed to:", instance.address);

  const content = {
    BuhaToken: instance.address,
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
