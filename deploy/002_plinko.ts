import { DeployFunction } from "hardhat-deploy/types";
import params from "../config/params";
import { BankrollFacet } from "../typechain-types";

// bnb: 0xB8117461D0bB3CdE8B9cEb20c3EB047597BC8691
const func: DeployFunction = async function ({ ethers, deployments }) {
  const { deploy, getNetworkName } = deployments;
  const [deployer] = await ethers.getSigners();
  const networkName = getNetworkName();
  const bankrollDeployment = await deployments.get("Diamond");
  const bankrollFactory = await ethers.getContractFactory("BankrollFacet");
  const bankroll = bankrollFactory.attach(bankrollDeployment.address) as BankrollFacet;
  const constructorParam = params[networkName];
  let contractName = "ToylandPlinko";
  const result = await deploy(contractName, {
    from: deployer.address,
    args: [
      constructorParam.vrfCoordinator,
      bankrollDeployment.address,
      constructorParam.vrfKeyhash,
      constructorParam.vrfSubId,
      constructorParam.vrfMinConfirmations,
      constructorParam.plinkoVrfGasLimit,
    ],
  });
  if (result.newlyDeployed) {
    console.log(`Plinko deployed to ${result.address}`);
    const tx1 = await bankroll.whitelistGame(result.address, true);
    await tx1.wait();
    console.log(`Plinko activated`);
  } else {
    console.log("No changes, skipped Plinko deployment");
  }
};
export default func;
