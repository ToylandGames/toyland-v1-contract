import { DeployFunction, DeployResult } from "hardhat-deploy/types";
import params from "../config/params";
import { BankrollFacet } from "../typechain-types";

// bnb: 0x810f29a0c16a2a8c196951056A2009857ae9BaEc
const func: DeployFunction = async function ({ ethers, deployments }) {
  const { deploy, getNetworkName } = deployments;
  const [deployer] = await ethers.getSigners();
  const networkName = getNetworkName();

  const bankrollDeployment = await deployments.get("Diamond");
  const bankrollFactory = await ethers.getContractFactory("BankrollFacet");
  const bankroll = bankrollFactory.attach(bankrollDeployment.address) as BankrollFacet;

  const constructorParam = params[networkName];

  let contractName = "ToylandCoinflip";

  const result = await deploy(contractName, {
    from: deployer.address,
    args: [
      constructorParam.vrfCoordinator,
      bankrollDeployment.address,
      constructorParam.vrfKeyhash,
      constructorParam.vrfSubId,
      constructorParam.vrfMinConfirmations,
      constructorParam.coinflipVrfGasLimit,
    ],
  });

  if (result.newlyDeployed) {
    console.log(`CoinFlip deployed to ${result.address}`);
    const tx1 = await bankroll.whitelistGame(result.address, true);
    await tx1.wait(2);
    console.log(`CoinFlip activated`);
  } else {
    console.log("No changes, skipped Coinflip deployment");
  }
};
export default func;
