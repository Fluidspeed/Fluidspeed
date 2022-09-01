// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.14;

import {
    IFluidspeed,
    IFluidspeedToken
} from "../interfaces/fluidspeed/IFluidspeed.sol";
import { FluidspeedGovernanceBase } from "../gov/FluidspeedGovernanceBase.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title Test governance contract
 * @author Fluidspeed
 * @dev A initializable version of the governance for testing purpose
 */
contract TestGovernance is
    Ownable,
    FluidspeedGovernanceBase
{
    IFluidspeed private _host;

    function initialize(
        IFluidspeed host,
        address rewardAddress,
        uint256 liquidationPeriod,
        uint256 patricianPeriod,
        address[] memory trustedForwarders
    )
        external
    {
        // can initialize only once
        assert(address(host) != address(0));
        assert(address(_host) == address(0));

        _host = host;

        setRewardAddress(_host, IFluidspeedToken(address(0)), rewardAddress);

        setPPPConfig(host, IFluidspeedToken(address(0)), liquidationPeriod, patricianPeriod);

        for (uint i = 0; i < trustedForwarders.length; ++i) {
            enableTrustedForwarder(_host, IFluidspeedToken(address(0)), trustedForwarders[i]);
        }
    }

    function _requireAuthorised(IFluidspeed host)
        internal view override
    {
        assert(host == _host);
        assert(owner() == _msgSender());
    }
}
