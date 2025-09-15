// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./common/ToylandGames.sol";

contract ToylandMines is ToylandGames {
    using SafeERC20 for IERC20;

    struct MinesGame {
        address tokenAddress;
        uint256 wager;
        uint256 requestID;
        uint64 blockNumber;
        uint64 currentMultiplier;
        uint8 numMines;
        bool[25] revealedTiles;
        bool[25] tilesPicked;
        bool isCashout;
    }

    mapping(address => MinesGame) minesGames;
    mapping(uint256 => address) vrfPendingPlayer;
    mapping(uint256 => mapping(uint256 => uint256)) minesMultipliers;
    mapping(uint256 => uint256) minesMaxReveal;

    event MinesReveal(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        bool[25] minesTiles,
        bool[25] revealedTiles,
        uint256 multiplier,
        uint256 rewardAmount
    );
    event MinesRevealCashout(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        bool[25] minesTiles,
        bool[25] revealedTiles,
        uint256 multiplier,
        uint256 rewardAmount
    );
    event MinesEnd(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        uint256 multiplier,
        uint256 rewardAmount
    );
    event MinesRefund(address indexed player, uint256 wager, address tokenAddress);

    constructor(
        address _vrfCoordinator,
        IBankroll _bankroll,
        bytes32 _vrfKeyHash,
        uint256 _vrfSubId,
        uint16 _vrfMinConfirmations,
        uint32 _vrfGasLimit
    ) ToylandGames(_vrfCoordinator, _bankroll, _vrfKeyHash, _vrfSubId, _vrfMinConfirmations, _vrfGasLimit) {
        _setMaxReveal([24, 21, 17, 14, 12, 10, 9, 8, 7, 6, 5, 5, 4, 4, 3, 3, 3, 2, 2, 2, 2, 1, 1, 1]);
        for (uint256 i = 1; i <= 24; i++) {
            _setMinesMultipliers(i);
        }
    }

    function getMultipliers(uint256 numMines, uint256 numRevealed) public view returns (uint256 multiplier) {
        multiplier = minesMultipliers[numMines][numRevealed];
        return multiplier;
    }

    function getMaxReveal() external view returns (uint256[24] memory maxReveal) {
        for (uint256 i = 0; i < 24; i++) {
            maxReveal[i] = minesMaxReveal[i + 1];
        }
    }

    function getCurrentUserState(address player) external view returns (MinesGame memory minesState) {
        minesState = minesGames[player];
        return minesState;
    }

    function play(
        uint256 wager,
        address tokenAddress,
        uint8 numMines,
        bool[25] calldata tiles,
        bool isCashout
    ) external payable nonReentrant {
        address msgSender = _msgSender();
        require(1 <= numMines && numMines <= 24, "numMines must be between 8 and 16");
        require(minesGames[msgSender].requestID == 0, "Waiting VRF request");
        require(minesGames[msgSender].numMines == 0, "Already playing");

        uint32 revealedTiles;
        for (uint8 i = 0; i < tiles.length; i++) {
            if (tiles[i]) {
                revealedTiles++;
            }
        }
        uint256 _minesMaxReveal = minesMaxReveal[numMines];
        require(!(revealedTiles == 0 || revealedTiles > _minesMaxReveal), "Invalid to reveal");

        _checkMaxWager(wager, tokenAddress, _minesMaxReveal, numMines);
        _processWager(tokenAddress, wager);
        uint256 id = _requestRandomWords(revealedTiles);
        vrfPendingPlayer[id] = msgSender;
        MinesGame storage game = minesGames[msgSender];
        game.numMines = numMines;
        game.wager = wager;
        game.tokenAddress = tokenAddress;
        game.isCashout = isCashout;
        game.tilesPicked = tiles;
        game.requestID = id;
        game.blockNumber = uint64(block.number);
    }

    function reveal(bool[25] calldata tiles, bool isCashout) external payable nonReentrant {
        MinesGame storage game = minesGames[msg.sender];
        require(game.numMines != 0, "Not playing");
        require(game.requestID == 0, "Waiting VRF request");

        uint32 numTilesRevealed;
        uint32 numTilesToReveal;
        bool isTileAlreadyRevealed = false;
        for (uint8 i = 0; i < tiles.length; i++) {
            if (tiles[i]) {
                if (game.revealedTiles[i]) {
                    isTileAlreadyRevealed = true;
                    break;
                }
                numTilesToReveal++;
            }
            if (game.revealedTiles[i]) {
                numTilesRevealed++;
            }
        }
        require(!isTileAlreadyRevealed, "Tile already revealed");
        require(
            !(numTilesToReveal == 0 || numTilesToReveal + numTilesRevealed > minesMaxReveal[game.numMines]),
            "Invalid to reveal"
        );
        _chargeVRFFee(msg.value);

        uint256 id = _requestRandomWords(numTilesToReveal);
        vrfPendingPlayer[id] = msg.sender;
        game.tilesPicked = tiles;
        game.isCashout = isCashout;
        game.requestID = id;
        game.blockNumber = uint64(block.number);
    }

    function end() external nonReentrant {
        MinesGame storage game = minesGames[msg.sender];
        require(game.numMines != 0, "Not playing");
        require(game.requestID == 0, "Waiting VRF request");

        uint256 multiplier = game.currentMultiplier;
        uint256 wager = game.wager;
        uint256 payout = (multiplier * wager) / 10000;
        address tokenAddress = game.tokenAddress;
        _transferToBankroll(tokenAddress, wager);
        _payoutBankrollToPlayer(msg.sender, payout, tokenAddress);
        uint256 rewardMultiplier = (int256(payout) - int256(game.wager)) > 0 ? 1000 : 100000; // win: 1%, lose: 100%
        uint256 rewardAmount = _payoutReward(msg.sender, tokenAddress, game.wager, rewardMultiplier);
        emit MinesEnd(msg.sender, wager, payout, tokenAddress, multiplier, rewardAmount);

        delete (minesGames[msg.sender]);
    }

    function refund() external nonReentrant {
        address msgSender = _msgSender();
        MinesGame storage game = minesGames[msgSender];
        require(game.numMines != 0, "Not playing");
        require(game.requestID != 0, "Not waiting VRF request");
        require(game.blockNumber + BLOCK_REFUND_COOLDOWN + 10 <= block.number, "Too early");

        uint256 wager = game.wager;
        address tokenAddress = minesGames[msg.sender].tokenAddress;

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: wager}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, wager);
        }
        emit MinesRefund(msg.sender, wager, tokenAddress);

        delete (minesGames[msg.sender]);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override {
        address player = vrfPendingPlayer[_requestId];
        if (player == address(0)) revert();
        delete (vrfPendingPlayer[_requestId]);
        MinesGame storage game = minesGames[player];

        uint256 numberOfRevealedTiles;
        for (uint32 tile = 0; tile < game.revealedTiles.length; tile++) {
            if (game.revealedTiles[tile]) {
                numberOfRevealedTiles += 1;
            }
        }

        uint256 numberOfMinesLeft = game.numMines;
        bool[25] memory mines;
        bool won = true;
        uint8 randomCounter;

        for (uint32 tileIdx = 0; tileIdx < game.tilesPicked.length; tileIdx++) {
            if (numberOfMinesLeft == 0 || 25 - numberOfRevealedTiles == numberOfMinesLeft) {
                if (game.tilesPicked[tileIdx]) {
                    game.revealedTiles[tileIdx] = true;
                }
                continue;
            }
            if (game.tilesPicked[tileIdx]) {
                minesGames[player].revealedTiles[tileIdx] = true;
                bool isBomb = _isBomb(25 - numberOfRevealedTiles, numberOfMinesLeft, _randomWords[randomCounter]);
                if (isBomb) {
                    numberOfMinesLeft -= 1;
                    mines[tileIdx] = true;
                    won = false;
                }
                numberOfRevealedTiles += 1;
                randomCounter += 1;
            }
        }

        if (!won) {
            _transferToBankroll(game.tokenAddress, game.wager);
            uint256 rewardMultiplier = 100000; //lose: 100%
            uint256 rewardAmount = _payoutReward(player, game.tokenAddress, game.wager, rewardMultiplier);
            if (game.isCashout == false) {
                emit MinesReveal(player, game.wager, 0, game.tokenAddress, mines, game.revealedTiles, 0, rewardAmount);
            } else {
                emit MinesRevealCashout(
                    player,
                    game.wager,
                    0,
                    game.tokenAddress,
                    mines,
                    game.revealedTiles,
                    0,
                    rewardAmount
                );
            }
            delete (minesGames[player]);
            return;
        }

        uint256 multiplier = minesMultipliers[numberOfMinesLeft][numberOfRevealedTiles];

        if (game.isCashout == false) {
            game.currentMultiplier = uint64(multiplier);
            game.requestID = 0;
            emit MinesReveal(
                player,
                game.wager,
                (multiplier * game.wager) / 10000,
                game.tokenAddress,
                mines,
                game.revealedTiles,
                multiplier,
                0
            );
        } else {
            uint256 wager = game.wager;
            address tokenAddress = game.tokenAddress;
            uint256 payout = (multiplier * wager) / 10000;
            uint256 rewardMultiplier = 1000; // win: 1%
            uint256 rewardAmount = _payoutReward(player, tokenAddress, game.wager, rewardMultiplier);
            _transferToBankroll(tokenAddress, game.wager);
            _payoutBankrollToPlayer(player, payout, tokenAddress);
            emit MinesRevealCashout(
                player,
                wager,
                payout,
                tokenAddress,
                mines,
                game.revealedTiles,
                multiplier,
                rewardAmount
            );
            delete (minesGames[player]);
        }
    }

    function _isBomb(uint256 numberTilesLeft, uint256 numberOfMinesLeft, uint256 rng) internal pure returns (bool) {
        uint256 winThreshold = 10000 - (numberOfMinesLeft * 10000) / numberTilesLeft;
        return rng % 10000 > winThreshold;
    }

    function _setMaxReveal(uint8[24] memory maxReveal) internal {
        for (uint256 i = 0; i < maxReveal.length; i++) {
            minesMaxReveal[i + 1] = maxReveal[i];
        }
    }

    function _setMinesMultipliers(uint256 numMines) internal {
        for (uint256 g = 1; g <= 25 - numMines; g++) {
            uint256 multiplier = 1;
            uint256 divisor = 1;
            for (uint256 f = 0; f < g; f++) {
                multiplier *= (25 - numMines - f);
                divisor *= (25 - f);
            }
            minesMultipliers[numMines][g] = (9900 * (10 ** 9)) / ((multiplier * (10 ** 9)) / divisor);
        }
    }

    function _checkMaxWager(uint256 wager, address tokenAddress, uint256 maxReveal, uint256 numMines) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(bankroll));
        }
        uint256 maxWager = (balance * (11000 - 10890)) / (minesMultipliers[numMines][maxReveal] - 10000);
        require(wager <= maxWager, "Too many wager");
    }
}
