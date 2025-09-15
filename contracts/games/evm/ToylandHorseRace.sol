// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./common/ToylandGames.sol";

contract ToylandHorseRace is ToylandGames {
    using SafeERC20 for IERC20;

    struct HorseRaceGame {
        uint256 wager;
        uint256 vrfId;
        address tokenAddress;
        uint64 blockNumber;
        uint8 pickedHorseId;
    }

    mapping(address => HorseRaceGame) horseRaceGames;
    mapping(uint256 => address) vrfPendingPlayer;

    mapping(uint8 => uint64) public horseMultipliers;

    event HorseRaceFulfilled(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        uint8 winnerHorseId,
        uint64 multiplier,
        uint256 rewardAmount
    );
    event HorseRaceRefund(address indexed player, uint256 wager, address tokenAddress);

    constructor(
        address _vrfCoordinator,
        IBankroll _bankroll,
        bytes32 _vrfKeyHash,
        uint256 _vrfSubId,
        uint16 _vrfMinConfirmations,
        uint32 _vrfGasLimit
    ) ToylandGames(_vrfCoordinator, _bankroll, _vrfKeyHash, _vrfSubId, _vrfMinConfirmations, _vrfGasLimit) {
        horseMultipliers[1] = 19600;
        horseMultipliers[2] = 29600;
        horseMultipliers[3] = 79600;
        horseMultipliers[4] = 149600;
        horseMultipliers[5] = 599600;
    }

    function getCurrentUserState(address player) external view returns (HorseRaceGame memory) {
        return (horseRaceGames[player]);
    }

    function getMultipliers() external view returns (uint64[5] memory multipliers) {
        for (uint8 i = 1; i < 5; i++) {
            multipliers[i - 1] = horseMultipliers[i];
        }
        return multipliers;
    }

    function getWinner(uint256 randomWord) internal pure returns (uint8 horseId) {
        uint256 rand = randomWord % 10000;
        if (rand < 4800) {
            horseId = 1;
        } else if (rand < 8000) {
            horseId = 2;
        } else if (rand < 9200) {
            horseId = 3;
        } else if (rand < 9840) {
            horseId = 4;
        } else {
            horseId = 5;
        }
    }

    function play(uint256 wager, address tokenAddress, uint8 pickedHorseId) external payable nonReentrant {
        address msgSender = _msgSender();
        require(horseRaceGames[msgSender].vrfId == 0, "Waiting VRF request");

        _checkMaxWager(wager, tokenAddress, pickedHorseId);
        _processWager(tokenAddress, wager);
        uint256 id = _requestRandomWords(1);

        horseRaceGames[msgSender] = HorseRaceGame(wager, id, tokenAddress, uint64(block.number), pickedHorseId);
        vrfPendingPlayer[id] = msgSender;
    }

    function refund() external nonReentrant {
        address msgSender = _msgSender();
        HorseRaceGame storage game = horseRaceGames[msgSender];
        require(game.vrfId != 0, "Not waiting VRF request");
        require(game.blockNumber + BLOCK_REFUND_COOLDOWN + 10 <= block.number, "Too early");

        uint256 wager = game.wager;
        address tokenAddress = game.tokenAddress;

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msgSender).call{value: wager}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }
        emit HorseRaceRefund(msgSender, wager, tokenAddress);

        delete (vrfPendingPlayer[game.vrfId]);
        delete (horseRaceGames[msgSender]);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address playerAddress = vrfPendingPlayer[requestId];
        if (playerAddress == address(0)) return;
        HorseRaceGame storage game = horseRaceGames[playerAddress];
        if (block.number > game.blockNumber + BLOCK_REFUND_COOLDOWN) return;
        uint256 payout;

        uint8 winnerHorseId = getWinner(randomWords[0]);
        uint64 multiplier = horseMultipliers[winnerHorseId];
        bool isWon = winnerHorseId == game.pickedHorseId;

        uint64 userMultiplier;
        if (isWon) {
            payout += (game.wager * multiplier) / 10000;
            userMultiplier = multiplier;
        }
        _transferToBankroll(game.tokenAddress, game.wager);
        if (payout != 0) {
            _payoutBankrollToPlayer(playerAddress, payout, game.tokenAddress);
        }
        uint256 rewardMultiplier = (int256(payout) - int256(game.wager)) > 0 ? 4000 : 100000; // win: 4%, lose: 100%
        uint256 rewardAmount = _payoutReward(playerAddress, game.tokenAddress, game.wager, rewardMultiplier);

        emit HorseRaceFulfilled(
            playerAddress,
            game.wager,
            payout,
            game.tokenAddress,
            winnerHorseId,
            userMultiplier,
            rewardAmount
        );

        delete (vrfPendingPlayer[requestId]);
        delete (horseRaceGames[playerAddress]);
    }

    function _checkMaxWager(uint256 wager, address tokenAddress, uint8 horseId) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(bankroll));
        }
        uint256 maxWager = (balance * (11000 - 10890)) / (horseMultipliers[horseId] - 10000);
        require(wager <= maxWager, "Too many wager");
    }
}
