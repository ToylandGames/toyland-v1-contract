import { DeployFunction, DeployResult } from "hardhat-deploy/types";
import params from "../config/params";
import { BankrollFacet } from "../typechain-types";

// 0x4BC5bE8Fe26b7FE21751f9E7F94306d7f2179342
const func: DeployFunction = async function ({ ethers, deployments }) {
  const { deploy, getNetworkName } = deployments;
  const [deployer] = await ethers.getSigners();
  const networkName = getNetworkName();
  const bankrollDeployment = await deployments.get("Diamond");
  const bankrollFactory = await ethers.getContractFactory("BankrollFacet");
  const bankroll = bankrollFactory.attach(bankrollDeployment.address) as BankrollFacet;
  const constructorParam = params[networkName];
  let result: DeployResult;
  result = await deploy("ToylandHorseRace", {
    from: deployer.address,
    args: [
      constructorParam.vrfCoordinator,
      bankrollDeployment.address,
      constructorParam.vrfKeyhash,
      constructorParam.vrfSubId,
      constructorParam.vrfMinConfirmations,
      constructorParam.horseraceVrfGasLimit,
    ],
  });
  if (result.newlyDeployed) {
    console.log(`HorseRace deployed to ${result.address}`);
    const tx1 = await bankroll.whitelistGame(result.address, true);
    await tx1.wait();
    console.log(`HorseRace activated`);
  } else {
    console.log("No changes, skipped HorseRace deployment");
  }
};
export default func;
