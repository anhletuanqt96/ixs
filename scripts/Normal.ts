import {ethers, run} from "hardhat";

async function main() {
  const Normal = await ethers.getContractFactory("Normal");
  const contract = await Normal.deploy();
  await contract.waitForDeployment();
  console.log("contract deployed to:", contract.target);
  await run("verify:verify", {
    address: contract.target,
    constructorArguments: [],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
