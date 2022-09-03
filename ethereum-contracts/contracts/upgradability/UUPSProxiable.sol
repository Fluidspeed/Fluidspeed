// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.16;

import { UUPSUtils } from "./UUPSUtils.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";


abstract contract UUPSProxiable is Initializable {

   
    function getCodeAddress() public view returns (address codeAddress)
    {
        return UUPSUtils.implementation();
    }

    function updateCode(address newAddress) external virtual;

   
    function castrate() external initializer { }

   
    function proxiableUUID() public view virtual returns (bytes32);

    
    function _updateCodeAddress(address newAddress) internal
    {
        // require UUPSProxy.initializeProxy first
        require(UUPSUtils.implementation() != address(0), "UUPSProxiable: not upgradable");
        require(
            proxiableUUID() == UUPSProxiable(newAddress).proxiableUUID(),
            "UUPSProxiable: not compatible logic"
        );
        require(
            address(this) != newAddress,
            "UUPSProxiable: proxy loop"
        );
        UUPSUtils.setImplementation(newAddress);
        emit CodeUpdated(proxiableUUID(), newAddress);
    }
    
    event CodeUpdated(bytes32 uuid, address codeAddress);

}
