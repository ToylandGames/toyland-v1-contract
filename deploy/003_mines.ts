import { DeployFunction, DeployResult } from "hardhat-deploy/types";
import params from "../config/params";
import { BankrollFacet } from "../typechain-types";

// bsc: 0x74FD0Cf7Dde5279792Ba5CCEBa4411F711861Ba2
const func: DeployFunction = async function ({ ethers, deployments }) {
  const { deploy, getNetworkName } = deployments;
  const [deployer] = await ethers.getSigners();
  const networkName = getNetworkName();
  const bankrollDeployment = await deployments.get("Diamond");
  const bankrollFactory = await ethers.getContractFactory("BankrollFacet");
  const bankroll = bankrollFactory.attach(bankrollDeployment.address) as BankrollFacet;
  const constructorParam = params[networkName];
  let contractName = "ToylandMines";
  const result = await deploy(contractName, {
    from: deployer.address,
    args: [
      constructorParam.vrfCoordinator,
      bankrollDeployment.address,
      constructorParam.vrfKeyhash,
      constructorParam.vrfSubId,
      constructorParam.vrfMinConfirmations,
      constructorParam.minesVrfGasLimit,
    ],
  });
  if (result.newlyDeployed) {
    console.log(`Mines deployed to ${result.address}`);
    const tx1 = await bankroll.whitelistGame(result.address, true);
    await tx1.wait();
    console.log(`Mines activated`);
  } else {
    console.log("No changes, skipped Mines deployment");
  }
};
export default func;
