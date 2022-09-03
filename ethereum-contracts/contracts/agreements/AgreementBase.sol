// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.16;

import { UUPSProxiable } from "../upgradability/UUPSProxiable.sol";
import { ISuperAgreement } from "../interfaces/fluidspeed/ISuperAgreement.sol";
import { FluidspeedErrors } from "../interfaces/fluidspeed/Definitions.sol";

/**
 * @title Fluidspeed agreement base boilerplate contract
 * @author Fluidspeed
 */
abstract contract AgreementBase is
    UUPSProxiable,
    ISuperAgreement
{
    address immutable internal _host;

    constructor(address host)
    {
        _host = host;
    }

    function proxiableUUID()
        public view override
        returns (bytes32)
    {
        return ISuperAgreement(this).agreementType();
    }

    function updateCode(address newAddress)
        external override
    {
        if (msg.sender != _host) revert FluidspeedErrors.ONLY_HOST(FluidspeedErrors.AGREEMENT_BASE_ONLY_HOST);
        return _updateCodeAddress(newAddress);
    }

}
