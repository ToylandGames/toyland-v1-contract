// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {WithStorage} from "../../LibStorage.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RewardFacet is WithStorage {
    using SafeERC20 for IERC20;

    event PayoutReward(address indexed to, uint256 amount);

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    function setRewardToken(address tokenAddress) external onlyOwner {
        rs().rewardToken = tokenAddress;
    }

    function getRewardToken() external view returns (address) {
        return rs().rewardToken;
    }

    function payoutReward(address to, uint256 amount) external {
        require(bs().isGame[msg.sender], "Not authorized");
        IERC20(rs().rewardToken).safeTransfer(to, amount);
        emit PayoutReward(to, amount);
    }
}
