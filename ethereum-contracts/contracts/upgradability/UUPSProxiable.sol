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

    function setImplementation(address codeAddress) internal {
        assembly {
            // solium-disable-line
            sstore(
                _IMPLEMENTATION_SLOT,
                codeAddress
            )
        }
    }
    
    event CodeUpdated(bytes32 uuid, address codeAddress);

}
