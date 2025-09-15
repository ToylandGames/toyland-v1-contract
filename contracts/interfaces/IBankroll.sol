// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBankroll {
    function getIsGame(address game) external view returns (bool);

    function getIsValidWager(address game, address tokenAddress) external view returns (bool);

    function transferPayout(address player, uint256 payout, address token) external;

    function owner() external view returns (address);

    function getVRFFeeArbitrum(
        address tokenAddress,
        uint256 vrfGasLimit,
        uint256 gasPrice
    ) external view returns (uint256 fee);

    function payoutReward(address to, uint256 amount) external;
}
