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

    /**
     * @dev Load framework objects
     * @param releaseVersion Protocol release version of the deployment
     */
    function loadFramework(string calldata releaseVersion)
        external view
        returns (Framework memory result)
    {
        // load fluidspeed host contract
        result.fluidspeed = IFluidspeed(_resolver.get(
            string.concat("Fluidspeed.", releaseVersion)
        ));
        result.superTokenFactory = result.fluidspeed.getSuperTokenFactory();
        result.agreementCFAv1 = result.fluidspeed.getAgreementClass(
            keccak256("org.fluidspeed-finance.agreements.ConstantFlowAgreement.v1")
        );
        result.agreementIDAv1 = result.fluidspeed.getAgreementClass(
            keccak256("org.fluidspeed-finance.agreements.InstantDistributionAgreement.v1")
        );
    }
}
