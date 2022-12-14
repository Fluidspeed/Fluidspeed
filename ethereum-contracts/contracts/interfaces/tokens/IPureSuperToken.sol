// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.8.0;

import { ISuperToken } from "../superfluid/ISuperToken.sol";

interface IPureSuperTokenCustom {
    function initialize(string calldata name, string calldata symbol, uint256 initialSupply) external;
}

/**
 * @title Pure Super Token interface
 * @author Fluidspeed
 */
interface IPureSuperToken is IPureSuperTokenCustom, ISuperToken {}
