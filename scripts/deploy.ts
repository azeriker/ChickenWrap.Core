import { ethers } from "hardhat";

async function main() {
  const Contract = await ethers.getContractFactory("ChickenWrap");
  const contract = await Contract.deploy(unlockTime, { value: lockedAmount });

  await contract.deployed();

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
