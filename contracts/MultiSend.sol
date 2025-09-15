// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MultiSend is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    function depositETH() external payable {
        require(msg.value > 0, "NO_ETH");
    }

    function depositERC20(address token, uint256 amount) external {
        require(amount > 0, "NO_AMOUNT");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function ethBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function tokenBalance(address token) public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function ownerMultiSendETH(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner nonReentrant {
        uint256 len = recipients.length;
        require(len == amounts.length, "LEN");

        uint256 total = 0;
        for (uint256 i = 0; i < len; ) {
            total += amounts[i];
            unchecked {
                ++i;
            }
        }
        require(address(this).balance >= total, "INSUF_ETH");

        for (uint256 i = 0; i < len; ) {
            (bool ok, ) = payable(recipients[i]).call{value: amounts[i]}("");
            require(ok, "SEND_FAIL");
            unchecked {
                ++i;
            }
        }
    }

    function ownerMultiSendETHEqual(address[] calldata recipients, uint256 amountEach) external onlyOwner nonReentrant {
        uint256 len = recipients.length;
        require(len > 0, "NO_RECIPIENTS");
        uint256 total = amountEach * len;
        require(address(this).balance >= total, "INSUF_ETH");

        for (uint256 i = 0; i < len; ) {
            (bool ok, ) = payable(recipients[i]).call{value: amountEach}("");
            require(ok, "SEND_FAIL");
            unchecked {
                ++i;
            }
        }
    }

    function ownerMultiSendERC20(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        uint256 len = recipients.length;
        require(len == amounts.length, "LEN");

        IERC20 erc20 = IERC20(token);
        uint256 total = 0;
        for (uint256 i = 0; i < len; ) {
            total += amounts[i];
            unchecked {
                ++i;
            }
        }
        require(erc20.balanceOf(address(this)) >= total, "INSUF_TOKEN");

        for (uint256 i = 0; i < len; ) {
            erc20.safeTransfer(recipients[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    function ownerMultiSendERC20Equal(
        address token,
        address[] calldata recipients,
        uint256 amountEach
    ) external onlyOwner {
        uint256 len = recipients.length;
        require(len > 0, "NO_RECIPIENTS");

        IERC20 erc20 = IERC20(token);
        uint256 total = amountEach * len;
        require(erc20.balanceOf(address(this)) >= total, "INSUF_TOKEN");

        for (uint256 i = 0; i < len; ) {
            erc20.safeTransfer(recipients[i], amountEach);
            unchecked {
                ++i;
            }
        }
    }

    function ownerWithdrawETH(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "TO_0");
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "WITHDRAW_FAIL");
    }

    function ownerWithdrawERC20(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "TO_0");
        IERC20(token).safeTransfer(to, amount);
    }
}
