// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.14;


library EventsEmitter {
    event Transfer(address indexed from, address indexed to, uint256 value);

    function emitTransfer(address from, address to, uint256 value) internal {
        emit Transfer(from, to, value);
    }
}
