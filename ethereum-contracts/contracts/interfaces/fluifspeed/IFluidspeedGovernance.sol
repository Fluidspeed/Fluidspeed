// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.8.0;

import { ISuperAgreement } from "./ISuperAgreement.sol";
import { ISuperToken } from "./ISuperToken.sol";
import { IFluidspeedToken  } from "./IFluidspeedToken.sol";
import { IFluidspeed } from "./IFluidspeed.sol";


/**
 * @title Fluidspeed governance interface
 * @author Fluidspeed
 */
interface IFluidspeedGovernance {

    /**
     * @dev Replace the current governance with a new governance
     */
    function replaceGovernance(
        IFluidspeed host,
        address newGov) external;

    /**
     * @dev Register a new agreement class
     */
    function registerAgreementClass(
        IFluidspeed host,
        address agreementClass) external;

    /**
     * @dev Update logics of the contracts
     *
     * @custom:note 
     * - Because they might have inter-dependencies, it is good to have one single function to update them all
     */
    function updateContracts(
        IFluidspeed host,
        address hostNewLogic,
        address[] calldata agreementClassNewLogics,
        address superTokenFactoryNewLogic
    ) external;

    /**
     * @dev Update supertoken logic contract to the latest that is managed by the super token factory
     */
    function batchUpdateSuperTokenLogic(
        IFluidspeed host,
        ISuperToken[] calldata tokens) external;
    
    /**
     * @dev Set configuration as address value
     */
    function setConfig(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key,
        address value
    ) external;
    
    /**
     * @dev Set configuration as uint256 value
     */
    function setConfig(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key,
        uint256 value
    ) external;

    /**
     * @dev Clear configuration
     */
    function clearConfig(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key
    ) external;

    /**
     * @dev Get configuration as address value
     */
    function getConfigAsAddress(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key) external view returns (address value);

    /**
     * @dev Get configuration as uint256 value
     */
    function getConfigAsUint256(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key) external view returns (uint256 value);

}
