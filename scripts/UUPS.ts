import {ethers, run, upgrades} from "hardhat";

async function main() {
  const Example = await ethers.getContractFactory("L2VICBridge");
  const contract = await upgrades.deployProxy(Example, [
    "0x44ac20FaB5201c25D2074D84B0830F398C28A143",
    "0xE897F7A6AC22a86399C3D0d31886Ae5d073da374",
  ]);
  await contract.waitForDeployment();
  console.log("contract deployed to:", await contract.target);
  const impl = await upgrades.erc1967.getImplementationAddress(
    contract.target.toString()
  );
  console.log("implAddress deployed to:", impl);

  const verifyResult = await run("verify:verify", {
    address: contract.target,
    constructorArguments: [],
  });
  console.log("verifyResult:", verifyResult);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
