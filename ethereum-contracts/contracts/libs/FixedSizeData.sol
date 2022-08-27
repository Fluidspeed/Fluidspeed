// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.14;


library FixedSizeData {

    /**
     * @dev Store data to the slot at `slot`
     */
    function storeData(bytes32 slot, bytes32[] memory data) internal {
        for (uint j = 0; j < data.length; ++j) {
            bytes32 d = data[j];
            assembly { sstore(add(slot, j), d) }
        }
    }

    function hasData(bytes32 slot, uint dataLength) internal view returns (bool) {
        for (uint j = 0; j < dataLength; ++j) {
            bytes32 d;
            assembly { d := sload(add(slot, j)) }
            if (uint256(d) > 0) return true;
        }
        return false;
    }

    /**
     * @dev Load data of size `dataLength` from the slot at `slot`
     */
    function loadData(bytes32 slot, uint dataLength) internal view returns (bytes32[] memory data) {
        data = new bytes32[](dataLength);
        for (uint j = 0; j < dataLength; ++j) {
            bytes32 d;
            assembly { d := sload(add(slot, j)) }
            data[j] = d;
        }
    }

    /**
     * @dev Erase data of size `dataLength` from the slot at `slot`
     */
    function eraseData(bytes32 slot, uint dataLength) internal {
        for (uint j = 0; j < dataLength; ++j) {
            assembly { sstore(add(slot, j), 0) }
        }
    }

}
