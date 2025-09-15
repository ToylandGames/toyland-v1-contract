import { DeployFunction, DeployResult } from "hardhat-deploy/types";
import params from "../config/params";
import { BankrollFacet } from "../typechain-types";

// bnb: 0xe9217bd6Edfa0D65CB32a172fd71d1C6EA1c7Ba4
const func: DeployFunction = async function ({ ethers, deployments }) {
  const { deploy, getNetworkName } = deployments;
  const [deployer] = await ethers.getSigners();
  const networkName = getNetworkName();

  const bankrollDeployment = await deployments.get("Diamond");
  const bankrollFactory = await ethers.getContractFactory("BankrollFacet");
  const bankroll = bankrollFactory.attach(bankrollDeployment.address) as BankrollFacet;

  const constructorParam = params[networkName];

  let result: DeployResult;
  result = await deploy("ToylandSlots", {
    from: deployer.address,
    args: [
      constructorParam.vrfCoordinator,
      bankrollDeployment.address,
      constructorParam.vrfKeyhash,
      constructorParam.vrfSubId,
      constructorParam.vrfMinConfirmations,
      constructorParam.slotsVrfGasLimit,
    ],
  });

  if (result.newlyDeployed) {
    console.log(`Slots deployed to ${result.address}`);
    const tx1 = await bankroll.whitelistGame(result.address, true);
    await tx1.wait(2);
    console.log(`Slots activated`);
  } else {
    console.log("No changes, skipped Slots deployment");
  }
};
export default func;
