// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract NicknameRegistryFacet {
    event NewNickname(address indexed user, string nickname);

    // Function to set nickname
    function setNickname(string calldata _nickname) external {
        require(bytes(_nickname).length > 0, "Nickname cannot be empty");
        require(bytes(_nickname).length <= 16, "Nickname too long");

        // Emit the event
        emit NewNickname(msg.sender, _nickname);
    }
}
