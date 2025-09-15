import { DeployFunction } from "hardhat-deploy/types";

// bnb: 0x12cBbCb702aCA9C3bAE28AF85F5349c13bce35a6
const func: DeployFunction = async function ({ ethers, deployments }) {
  const { deploy, getNetworkName } = deployments;
  const [deployer] = await ethers.getSigners();

  const result = await deploy("MultiSend", {
    from: deployer.address,
    args: [],
  });

  if (result.newlyDeployed) {
    console.log(`Utils-MultiSend deployed to ${result.address}`);
  } else {
    console.log("No changes, skipped Utils-MultiSend deployment");
  }
};
export default func;
