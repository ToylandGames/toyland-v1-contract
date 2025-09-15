// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../interfaces/IBankroll.sol";
import "../../../interfaces/IArbGasInfo.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

abstract contract ToylandGames is ReentrancyGuard, VRFConsumerBaseV2Plus {
    using SafeERC20 for IERC20;

    uint256 public claimableVRFFee;

    IBankroll public bankroll;

    bytes32 vrfKeyHash;
    uint64 constant BLOCK_REFUND_COOLDOWN = 1000;
    uint16 vrfMinConfirmations;
    uint32 vrfGasLimit;
    uint256 vrfSubId;

    constructor(
        address _vrfCoordinator,
        IBankroll _bankroll,
        bytes32 _vrfKeyHash,
        uint256 _vrfSubId,
        uint16 _vrfMinConfirmations,
        uint32 _vrfGasLimit
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        bankroll = _bankroll;
        vrfKeyHash = _vrfKeyHash;
        vrfSubId = _vrfSubId;
        vrfMinConfirmations = _vrfMinConfirmations;
        vrfGasLimit = _vrfGasLimit;
    }

    function _msgSender() internal view returns (address sender) {
        return msg.sender;
    }

    function _shouldStop(int256 value, uint256 stopGain, uint256 stopLoss) internal pure returns (bool) {
        return value >= int256(stopGain) || value <= -int256(stopLoss);
    }

    function _processWager(address tokenAddress, uint256 wager) internal {
        require(bankroll.getIsValidWager(address(this), tokenAddress), "Token not approved");
        require(wager != 0, "Wager must be greater than 0");
        if (tokenAddress == address(0)) {
            _chargeVRFFee(msg.value - wager);
        } else {
            _chargeVRFFee(msg.value);
            IERC20(tokenAddress).safeTransferFrom(_msgSender(), address(this), wager);
        }
    }

    function _payoutReward(
        address player,
        address tokenAddress,
        uint256 wager,
        uint256 multiplier
    ) internal returns (uint256) {
        uint256 _price = 0;
        //BNB
        if (tokenAddress == address(0)) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);
            (, int256 price, , , ) = priceFeed.latestRoundData();
            _price = uint256(price);
        }
        // USDT
        if (tokenAddress == address(0x55d398326f99059fF775485246999027B3197955)) {
            _price = 100000000;
        }
        // USD1
        if (tokenAddress == address(0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d)) {
            _price = 100000000;
        }
        uint256 rewardAmount = (wager * multiplier) / 100000;
        uint256 usdAmount = (rewardAmount * _price) / 10 ** 8;
        if (rewardAmount > 0) {
            bankroll.payoutReward(player, usdAmount);
        }
        return usdAmount;
    }

    function _transferToBankroll(address tokenAddress, uint256 amount) internal {
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(address(bankroll)).call{value: amount}("");
            require(success, "refund failed");
        } else {
            IERC20(tokenAddress).safeTransfer(address(bankroll), amount);
        }
    }

    function getVRFFee(uint256 _gasPrice) public view returns (uint256 fee) {
        uint256 maxVerificationGas = 115000;
        uint256 premium = 60;
        uint256 totalGas = _gasPrice * (maxVerificationGas + vrfGasLimit);
        fee = (totalGas * (100 + premium)) / 100;
    }

    function _refundVRFFee(uint256 refundableAmount) internal {
        if (refundableAmount > 0) {
            (bool success, ) = payable(msg.sender).call{value: refundableAmount}("");
            require(success, "refund failed");
        }
    }

    function _chargeVRFFee(uint256 vrfFeeProvided) internal {
        uint256 _vrfFee = getVRFFee(tx.gasprice);
        require(vrfFeeProvided >= _vrfFee, "Insufficient vrf fee");
        _refundVRFFee(vrfFeeProvided - _vrfFee);
        claimableVRFFee += _vrfFee;
    }

    function _payoutBankrollToPlayer(address player, uint256 payout, address tokenAddress) internal {
        bankroll.transferPayout(player, payout, tokenAddress);
    }

    function _requestRandomWords(uint32 numWords) internal returns (uint256 s_requestId) {
        s_requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubId,
                requestConfirmations: vrfMinConfirmations,
                callbackGasLimit: vrfGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
            })
        );
    }

    function collectVrfFee() external nonReentrant onlyOwner {
        uint256 fee = claimableVRFFee;
        claimableVRFFee = 0;
        (bool success, ) = payable(address(msg.sender)).call{value: fee}("");
        require(success, "transfer failed");
    }

    receive() external payable {}
}
