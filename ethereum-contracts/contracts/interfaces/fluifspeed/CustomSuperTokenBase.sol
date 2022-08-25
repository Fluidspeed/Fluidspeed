// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.8.0;

import {
    ISuperToken
} from "../../interfaces/fluifspeed/IToken.sol";


abstract contract CustomSuperTokenBase {
    // This (32) is the hard-coded number of storage slots used by the super token
    uint256[32] internal _storagePaddings;
}
