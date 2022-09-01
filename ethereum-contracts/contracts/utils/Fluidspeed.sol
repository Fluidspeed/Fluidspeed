// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.14;

import { IResolver } from "../interfaces/utils/IResolver.sol";
import {
    IFluidspeed,
    ISuperTokenFactory,
    ISuperAgreement
} from "../interfaces/fluidspeed/IFluidspeed.sol";

/**
 * @title Fluidspeed loader contract
 * @author Fluidspeed
 * @dev A on-chain utility contract for loading framework objects in one view function.
 *
 * NOTE:
 * Q: Why don't we just use https://www.npmjs.com/package/ethereum-multicall?
 * A: Well, no strong reason other than also allowing on-chain one view function loading.
 */
contract FluidspeedLoader {

    IResolver private immutable _resolver;

    struct Framework {
        IFluidspeed fluidspeed;
        ISuperTokenFactory superTokenFactory;
        ISuperAgreement agreementCFAv1;
        ISuperAgreement agreementIDAv1;
    }

    constructor(IResolver resolver) {
        _resolver = resolver;
    }

    
}
