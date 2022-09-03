// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.16;

import { UUPSUtils } from "./UUPSUtils.sol";
import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";


contract UUPSProxy is Proxy {

   
    function initializeProxy(address initialAddress) external {
        require(initialAddress != address(0), "UUPSProxy: zero address");
        require(UUPSUtils.implementation() == address(0), "UUPSProxy: already initialized");
        UUPSUtils.setImplementation(initialAddress);
    }

    function _implementation() internal virtual override view returns (address)
    {
        return UUPSUtils.implementation();
    }

}
