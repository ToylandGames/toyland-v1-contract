import { DeployFunction } from "hardhat-deploy/types";

// bnb: 0x1ea54114aee90F1Ab6d05418d33917143286Fe58
const func: DeployFunction = async function ({ ethers, deployments }) {
  const { diamond } = deployments;
  const [deployer] = await ethers.getSigners();
  const result = await diamond.deploy("Diamond", {
    from: deployer.address,
    owner: deployer.address,
    facets: ["BankrollFacet", "RewardFacet", "NicknameRegistryFacet"],
    log: true,
  });

  if (result.newlyDeployed) {
    console.log(`Diamond deployed to ${result.address}`);
  }
};
export default func;
