// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./common/ToylandGames.sol";

contract ToylandDice is ToylandGames {
    using SafeERC20 for IERC20;

    constructor(
        address _vrfCoordinator,
        IBankroll _bankroll,
        bytes32 _vrfKeyHash,
        uint256 _vrfSubId,
        uint16 _vrfMinConfirmations,
        uint32 _vrfGasLimit
    ) ToylandGames(_vrfCoordinator, _bankroll, _vrfKeyHash, _vrfSubId, _vrfMinConfirmations, _vrfGasLimit) {}

    struct DiceGame {
        uint256 wager;
        uint256 stopGain;
        uint256 stopLoss;
        uint256 vrfId;
        address tokenAddress;
        uint64 blockNumber;
        uint32 numBets;
        uint32 multiplier;
        bool isOver;
    }

    mapping(address => DiceGame) diceGames;
    mapping(uint256 => address) vrfPendingPlayer;
    event DiceFulfilled(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        uint32 multiplier,
        bool isOver,
        uint256[] diceOutcomes,
        uint256[] payouts,
        uint32 numGames,
        uint256 rewardAmount
    );
    event DiceRefund(address indexed player, uint256 wager, address tokenAddress);

    function getCurrentUserState(address player) external view returns (DiceGame memory) {
        return (diceGames[player]);
    }

    function play(
        uint256 wager,
        uint32 multiplier,
        address tokenAddress,
        bool isOver,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss
    ) external payable nonReentrant {
        address msgSender = _msgSender();
        require(10421 <= multiplier && multiplier <= 9900000, "Invalid multiplier");
        require(diceGames[msgSender].vrfId == 0, "Waiting VRF request");
        require(0 < numBets && numBets <= 100, "Invalid numBets");

        _checkMaxWager(wager, tokenAddress, multiplier);
        _processWager(tokenAddress, wager * numBets);

        uint256 id = _requestRandomWords(numBets);

        diceGames[msgSender] = DiceGame(
            wager,
            stopGain,
            stopLoss,
            id,
            tokenAddress,
            uint64(block.number),
            numBets,
            multiplier,
            isOver
        );
        vrfPendingPlayer[id] = msgSender;
    }

    /**
     * @dev Function to refund user in case of VRF request failling
     */
    function refund() external nonReentrant {
        address msgSender = _msgSender();
        DiceGame storage game = diceGames[msgSender];
        require(diceGames[msgSender].vrfId != 0, "Not waiting VRF request");
        require(game.blockNumber + BLOCK_REFUND_COOLDOWN + 10 <= block.number, "Too early");

        uint256 wager = game.wager * game.numBets;
        address tokenAddress = game.tokenAddress;

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msgSender).call{value: wager}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }
        emit DiceRefund(msgSender, wager, tokenAddress);

        delete (vrfPendingPlayer[game.vrfId]);
        delete (diceGames[msgSender]);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address playerAddress = vrfPendingPlayer[requestId];
        if (playerAddress == address(0)) return;
        DiceGame storage game = diceGames[playerAddress];
        if (block.number > game.blockNumber + BLOCK_REFUND_COOLDOWN) return;

        int256 totalValue;
        uint256 payout;
        uint32 gamePlayed;
        uint256[] memory diceOutcomes = new uint256[](game.numBets);
        uint256[] memory payouts = new uint256[](game.numBets);

        uint256 winChance = 99000000000 / game.multiplier;
        uint256 numberToRollOver = 10000000 - winChance;
        uint256 gamePayout = (game.multiplier * game.wager) / 10000;

        address tokenAddress = game.tokenAddress;

        for (gamePlayed = 0; gamePlayed < game.numBets; gamePlayed++) {
            if (totalValue >= int256(game.stopGain)) {
                break;
            }
            if (totalValue <= -int256(game.stopLoss)) {
                break;
            }

            diceOutcomes[gamePlayed] = randomWords[gamePlayed] % 10000000;
            if (diceOutcomes[gamePlayed] >= numberToRollOver && game.isOver == true) {
                totalValue += int256(gamePayout - game.wager);
                payout += gamePayout;
                payouts[gamePlayed] = gamePayout;
                continue;
            }

            if (diceOutcomes[gamePlayed] <= winChance && game.isOver == false) {
                totalValue += int256(gamePayout - game.wager);
                payout += gamePayout;
                payouts[gamePlayed] = gamePayout;
                continue;
            }

            totalValue -= int256(game.wager);
        }

        payout += (game.numBets - gamePlayed) * game.wager;

        _transferToBankroll(tokenAddress, game.wager * game.numBets);
        if (payout != 0) {
            _payoutBankrollToPlayer(playerAddress, payout, tokenAddress);
        }
        uint256 rewardMultiplier = (int256(payout) - int256(game.wager * game.numBets)) > 0 ? 1000 : 100000; // win: 1%, lose: 100%
        uint256 rewardAmount = _payoutReward(playerAddress, tokenAddress, game.wager * game.numBets, rewardMultiplier);

        emit DiceFulfilled(
            playerAddress,
            game.wager,
            payout,
            tokenAddress,
            game.multiplier,
            game.isOver,
            diceOutcomes,
            payouts,
            gamePlayed,
            rewardAmount
        );

        delete (vrfPendingPlayer[requestId]);
        delete (diceGames[playerAddress]);
    }

    /**
     * @dev calculates the maximum wager allowed based on the bankroll size
     */
    function _checkMaxWager(uint256 wager, address tokenAddress, uint256 multiplier) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(bankroll));
        }
        uint256 maxWager = (balance * (11000 - 10890)) / (multiplier - 10000);
        require(wager <= maxWager, "Too many wager");
    }
}
