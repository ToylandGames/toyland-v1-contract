// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./common/ToylandGames.sol";

contract ToylandCoinflip is ToylandGames {
    using SafeERC20 for IERC20;

    struct CoinFlipGame {
        uint256 wager;
        uint256 stopGain;
        uint256 stopLoss;
        uint256 vrfId;
        uint64 blockNumber;
        uint32 numBets;
        address tokenAddress;
        bool isHeads;
    }

    mapping(address => CoinFlipGame) coinFlipGames;
    mapping(uint256 => address) vrfPendingPlayer;

    event CoinFlipFulfilled(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        uint8[] coinOutcomes,
        uint256[] payouts,
        uint32 numGames,
        uint256 rewardAmount
    );
    event CoinFlipRefund(address indexed player, uint256 wager, address tokenAddress);

    constructor(
        address _vrfCoordinator,
        IBankroll _bankroll,
        bytes32 _vrfKeyHash,
        uint256 _vrfSubId,
        uint16 _vrfMinConfirmations,
        uint32 _vrfGasLimit
    ) ToylandGames(_vrfCoordinator, _bankroll, _vrfKeyHash, _vrfSubId, _vrfMinConfirmations, _vrfGasLimit) {}

    function getCurrentUserState(address player) external view returns (CoinFlipGame memory) {
        return (coinFlipGames[player]);
    }

    function isWon(bool choice, uint256 result) public pure returns (bool) {
        return (choice == true) ? (result == 1) : (result == 0);
    }

    function play(
        uint256 wager,
        address tokenAddress,
        bool isHeads,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss
    ) external payable nonReentrant {
        address msgSender = _msgSender();
        require(coinFlipGames[msgSender].vrfId == 0, "Waiting VRF request");
        require(0 < numBets && numBets <= 100, "Invalid numBets");

        _checkMaxWager(wager, tokenAddress);
        _processWager(tokenAddress, wager * numBets);
        uint256 id = _requestRandomWords(numBets);

        coinFlipGames[msgSender] = CoinFlipGame(
            wager,
            stopGain,
            stopLoss,
            id,
            uint64(block.number),
            numBets,
            tokenAddress,
            isHeads
        );
        vrfPendingPlayer[id] = msgSender;
    }

    function refund() external nonReentrant {
        address msgSender = _msgSender();
        CoinFlipGame storage game = coinFlipGames[msgSender];

        require(coinFlipGames[msgSender].vrfId != 0, "Not waiting VRF request");
        require(game.blockNumber + BLOCK_REFUND_COOLDOWN + 10 <= block.number, "Too early");

        uint256 wager = game.wager * game.numBets;
        address tokenAddress = game.tokenAddress;

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msgSender).call{value: wager}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }
        emit CoinFlipRefund(msgSender, wager, tokenAddress);

        delete (vrfPendingPlayer[game.vrfId]);
        delete (coinFlipGames[msgSender]);
    }

    function _checkMaxWager(uint256 wager, address tokenAddress) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(bankroll));
        }
        uint256 maxWager = (balance * 1122448) / 100000000;
        require(wager <= maxWager, "Too many wager");
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override {
        address playerAddress = vrfPendingPlayer[_requestId];
        if (playerAddress == address(0)) return;
        CoinFlipGame storage game = coinFlipGames[playerAddress];
        if (block.number > game.blockNumber + BLOCK_REFUND_COOLDOWN) return;

        int256 totalValue;
        uint256 payout;
        uint32 gamePlayed;
        uint8[] memory result = new uint8[](game.numBets);
        uint256[] memory payouts = new uint256[](game.numBets);
        address tokenAddress = game.tokenAddress;

        for (gamePlayed = 0; gamePlayed < game.numBets; gamePlayed++) {
            if (_shouldStop(totalValue, game.stopGain, game.stopLoss)) {
                break;
            }

            result[gamePlayed] = uint8(_randomWords[gamePlayed] % 2);
            if (isWon(game.isHeads, result[gamePlayed])) {
                totalValue += int256((game.wager * 9800) / 10000);
                payout += (game.wager * 19800) / 10000;
                payouts[gamePlayed] = (game.wager * 19800) / 10000;
            } else {
                totalValue -= int256(game.wager);
            }
        }

        payout += (game.numBets - gamePlayed) * game.wager;

        _transferToBankroll(tokenAddress, game.wager * game.numBets);
        if (payout != 0) {
            _payoutBankrollToPlayer(playerAddress, payout, tokenAddress);
        }

        uint256 rewardMultiplier = (int256(payout) - int256(game.wager * game.numBets)) > 0 ? 1000 : 100000; // win: 1%, lose: 100%
        uint256 rewardAmount = _payoutReward(playerAddress, tokenAddress, game.wager * game.numBets, rewardMultiplier);

        emit CoinFlipFulfilled(
            playerAddress,
            game.wager,
            payout,
            tokenAddress,
            result,
            payouts,
            gamePlayed,
            rewardAmount
        );

        delete (vrfPendingPlayer[_requestId]);
        delete (coinFlipGames[playerAddress]);
    }
}
