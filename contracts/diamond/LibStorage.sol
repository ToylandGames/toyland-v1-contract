// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct BankrollStorage {
    mapping(address => bool) isGame;
    mapping(address => bool) isTokenAllowed;
    address[] allowedTokens;
}

struct RewardStorage {
    address rewardToken;
}

library LibStorage {
    bytes32 constant BANKROLL_STORAGE_POSITION = keccak256("luckybit.storage.bankroll"); // TODO
    bytes32 constant REWARD_STORAGE_POSITION = keccak256("toyland.storage.reward");

    function bankrollStorage() internal pure returns (BankrollStorage storage bs) {
        bytes32 position = BANKROLL_STORAGE_POSITION;
        assembly {
            bs.slot := position
        }
    }

    function rewardStorage() internal pure returns (RewardStorage storage rs) {
        bytes32 position = REWARD_STORAGE_POSITION;
        assembly {
            rs.slot := position
        }
    }
}

contract WithStorage {
    function bs() internal pure returns (BankrollStorage storage) {
        return LibStorage.bankrollStorage();
    }

    function rs() internal pure returns (RewardStorage storage) {
        return LibStorage.rewardStorage();
    }
}
