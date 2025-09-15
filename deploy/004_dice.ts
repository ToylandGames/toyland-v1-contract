import { DeployFunction, DeployResult } from "hardhat-deploy/types";
import params from "../config/params";
import { BankrollFacet } from "../typechain-types";

// dice: 0xa6A8EFbbcAFAfc30c0E944d9e8732fAfa6353eeF
const func: DeployFunction = async function ({ ethers, deployments }) {
  const { deploy, getNetworkName } = deployments;
  const [deployer] = await ethers.getSigners();
  const networkName = getNetworkName();
  const bankrollDeployment = await deployments.get("Diamond");
  const bankrollFactory = await ethers.getContractFactory("BankrollFacet");
  const bankroll = bankrollFactory.attach(bankrollDeployment.address) as BankrollFacet;
  const constructorParam = params[networkName];
  let contractName = "ToylandDice";
  const result = await deploy(contractName, {
    from: deployer.address,
    args: [
      constructorParam.vrfCoordinator,
      bankrollDeployment.address,
      constructorParam.vrfKeyhash,
      constructorParam.vrfSubId,
      constructorParam.vrfMinConfirmations,
      constructorParam.diceVrfGasLimit,
    ],
  });
  if (result.newlyDeployed) {
    console.log(`Dice deployed to ${result.address}`);
    const tx1 = await bankroll.whitelistGame(result.address, true);
    await tx1.wait();
    console.log(`Dice activated`);
  } else {
    console.log("No changes, skipped Dice deployment");
  }
};
export default func;
