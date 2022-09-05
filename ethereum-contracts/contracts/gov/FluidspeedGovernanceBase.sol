// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.16;

import {
    IFluidspeed,
    ISuperAgreement,
    IFluidspeedToken,
    ISuperToken,
    ISuperTokenFactory,
    IFluidspeedGovernance,
    FluidspeedErrors,
    FluidspeedGovernanceConfigs
} from "../interfaces/fluidspeed/IFluidspeed.sol";

import { UUPSProxiable } from "../upgradability/UUPSProxiable.sol";


/**
 * @title Base fluidspeed governance implementation
 * @author Fluidspeed
 */
abstract contract FluidspeedGovernanceBase is IFluidspeedGovernance
{
    struct Value {
        bool set;
        uint256 value;
    }

    // host => superToken => config
    mapping (address => mapping (address => mapping (bytes32 => Value))) internal _configs;

    /**************************************************************************
    /* IFluidspeedGovernance interface
    /*************************************************************************/

    function replaceGovernance(
        IFluidspeed host,
        address newGov
    )
        external override
        onlyAuthorized(host)
    {
        host.replaceGovernance(IFluidspeedGovernance(newGov));
    }

    function registerAgreementClass(
        IFluidspeed host,
        address agreementClass
    )
        external override
        onlyAuthorized(host)
    {
        host.registerAgreementClass(ISuperAgreement(agreementClass));
    }

    function updateContracts(
        IFluidspeed host,
        address hostNewLogic,
        address[] calldata agreementClassNewLogics,
        address superTokenFactoryNewLogic
    )
        external override
        onlyAuthorized(host)
    {
        if (hostNewLogic != address(0)) {
            UUPSProxiable(address(host)).updateCode(hostNewLogic);
            UUPSProxiable(address(hostNewLogic)).castrate();
        }
        for (uint i = 0; i < agreementClassNewLogics.length; ++i) {
            host.updateAgreementClass(ISuperAgreement(agreementClassNewLogics[i]));
            UUPSProxiable(address(agreementClassNewLogics[i])).castrate();
        }
        if (superTokenFactoryNewLogic != address(0)) {
            host.updateSuperTokenFactory(ISuperTokenFactory(superTokenFactoryNewLogic));

            // the factory logic can be updated for non-upgradable hosts too,
            // in this case it's used without proxy and already initialized.
            // solhint-disable-next-line no-empty-blocks
            try UUPSProxiable(address(superTokenFactoryNewLogic)).castrate() {}
            // solhint-disable-next-line no-empty-blocks
            catch {}
        }
    }

    function batchUpdateSuperTokenLogic(
        IFluidspeed host,
        ISuperToken[] calldata tokens
    )
        external override
        onlyAuthorized(host)
    {
        for (uint i = 0; i < tokens.length; ++i) {
            host.updateSuperTokenLogic(tokens[i]);
        }
    }

    function batchUpdateSuperTokenMinimumDeposit(
        IFluidspeed host,
        ISuperToken[] calldata tokens,
        uint256[] calldata minimumDeposits
    ) external {
        if (tokens.length != minimumDeposits.length) revert SF_GOV_ARRAYS_NOT_SAME_LENGTH();
        for (uint i = 0; i < minimumDeposits.length; ++i) {
            setSuperTokenMinimumDeposit(
                host,
                tokens[i],
                minimumDeposits[i]
            );
        }
    }

    event ConfigChanged(
        IFluidspeed indexed host,
        IFluidspeedToken indexed superToken,
        bytes32 key,
		bool isKeySet,
        uint256 value);

    function setConfig(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key,
        address value
    )
        external override
    {
        _setConfig(host, superToken, key, value);
    }

    function setConfig(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key,
        uint256 value
    )
        external override
    {
        _setConfig(host, superToken, key, value);
    }

    function clearConfig(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key
    )
        external override
    {
        _clearConfig(host, superToken, key);
    }

    function _setConfig(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key,
        address value
    )
        internal
        onlyAuthorized(host)
    {
        emit ConfigChanged(host, superToken, key, true, uint256(uint160(value)));
        _configs[address(host)][address(superToken)][key] = Value(true, uint256(uint160(value)));
    }

    function _setConfig(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key,
        uint256 value
    )
        internal
        onlyAuthorized(host)
    {
        emit ConfigChanged(host, superToken, key, true, value);
        _configs[address(host)][address(superToken)][key] = Value(true, value);
    }

    function _clearConfig(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key
    )
        internal
        onlyAuthorized(host)
    {
        emit ConfigChanged(host, superToken, key, false, 0);
        _configs[address(host)][address(superToken)][key] = Value(false, 0);
    }

    function getConfigAsAddress(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key
    )
        public view override
        returns(address value)
    {
        Value storage v = _configs[address(host)][address(superToken)][key];
        if (!v.set) {
            // fallback to default config
            v =  _configs[address(host)][address(0)][key];
        }
        return address(uint160(v.value));
    }

    function getConfigAsUint256(
        IFluidspeed host,
        IFluidspeedToken superToken,
        bytes32 key
    )
        public view override
        returns(uint256 period)
    {
        Value storage v = _configs[address(host)][address(superToken)][key];
        if (!v.set) {
            // fallback to default config
            v =  _configs[address(host)][address(0)][key];
        }
        return v.value;
    }

    /**************************************************************************
    /* Convenience methods for known Configurations
    /*************************************************************************/

    // Fluidspeed rewardAddress
    event RewardAddressChanged(
        IFluidspeed indexed host,
        IFluidspeedToken indexed superToken,
        bool isKeySet,
        address rewardAddress);

    function getRewardAddress(
        IFluidspeed host,
        IFluidspeedToken superToken
    )
        external view
        returns (address)
    {
        return getConfigAsAddress(
            host, superToken,
            FluidspeedGovernanceConfigs.SUPERFLUID_REWARD_ADDRESS_CONFIG_KEY);
    }

    function setRewardAddress(
        IFluidspeed host,
        IFluidspeedToken superToken,
        address rewardAddress
    )
        public
    {
        _setConfig(
            host, superToken,
            FluidspeedGovernanceConfigs.SUPERFLUID_REWARD_ADDRESS_CONFIG_KEY,
            rewardAddress);
        emit RewardAddressChanged(host, superToken, true, rewardAddress);
    }

    function clearRewardAddress(
        IFluidspeed host,
        IFluidspeedToken superToken
    )
        external
    {
        _clearConfig(
            host, superToken,
            FluidspeedGovernanceConfigs.SUPERFLUID_REWARD_ADDRESS_CONFIG_KEY);
        emit RewardAddressChanged(host, superToken, false, address(0));
    }

    // CFAv1 liquidationPeriod (DEPRECATED BY PPPConfigurationChanged)
    event CFAv1LiquidationPeriodChanged(
        IFluidspeed indexed host,
        IFluidspeedToken indexed superToken,
        bool isKeySet,
        uint256 liquidationPeriod);

    // CFAv1 PPPConfiguration - Liquidation Period + Patrician Period
    event PPPConfigurationChanged(
        IFluidspeed indexed host,
        IFluidspeedToken indexed superToken,
        bool isKeySet,
        uint256 liquidationPeriod,
        uint256 patricianPeriod);

    function getPPPConfig(
        IFluidspeed host,
        IFluidspeedToken superToken
    )
        external view
        returns (uint256 liquidationPeriod, uint256 patricianPeriod)
    {
        uint256 pppConfig = getConfigAsUint256(
            host,
            superToken,
            FluidspeedGovernanceConfigs.CFAV1_PPP_CONFIG_KEY
        );
        (liquidationPeriod, patricianPeriod) = FluidspeedGovernanceConfigs.decodePPPConfig(pppConfig);
    }

    function setPPPConfig(
        IFluidspeed host,
        IFluidspeedToken superToken,
        uint256 liquidationPeriod,
        uint256 patricianPeriod
    )
        public
    {
        if (liquidationPeriod <= patricianPeriod
            || liquidationPeriod >= type(uint32).max
            || patricianPeriod >= type(uint32).max
        ) {
            revert SF_GOV_INVALID_LIQUIDATION_OR_PATRICIAN_PERIOD();
        }
        uint256 value = (uint256(liquidationPeriod) << 32) | uint256(patricianPeriod);
        _setConfig(
            host,
            superToken,
            FluidspeedGovernanceConfigs.CFAV1_PPP_CONFIG_KEY,
            value
        );
        emit PPPConfigurationChanged(host, superToken, true, liquidationPeriod, patricianPeriod);
    }

    function clearPPPConfig(
        IFluidspeed host,
        IFluidspeedToken superToken
    )
        external
    {
        _clearConfig(host, superToken, FluidspeedGovernanceConfigs.CFAV1_PPP_CONFIG_KEY);
        emit PPPConfigurationChanged(host, superToken, false, 0, 0);
    }

    // CFAv1 minimum deposit
    event SuperTokenMinimumDepositChanged(
        IFluidspeed indexed host,
        IFluidspeedToken indexed superToken,
        bool isKeySet,
        uint256 minimumDeposit
    );

    function getSuperTokenMinimumDeposit(
        IFluidspeed host,
        IFluidspeedToken superToken
    )
        external view
        returns (uint256 value)
    {
        return getConfigAsUint256(host, superToken,
            FluidspeedGovernanceConfigs.SUPERTOKEN_MINIMUM_DEPOSIT_KEY);
    }

    function setSuperTokenMinimumDeposit(
        IFluidspeed host,
        IFluidspeedToken superToken,
        uint256 value
    )
        public
    {
        _setConfig(host, superToken, FluidspeedGovernanceConfigs.SUPERTOKEN_MINIMUM_DEPOSIT_KEY, value);
        emit SuperTokenMinimumDepositChanged(host, superToken, true, value);
    }

    function clearSuperTokenMinimumDeposit(
        IFluidspeed host,
        ISuperToken superToken
    )
        external
    {
        _clearConfig(host, superToken, FluidspeedGovernanceConfigs.SUPERTOKEN_MINIMUM_DEPOSIT_KEY);
        emit SuperTokenMinimumDepositChanged(host, superToken, false, 0);
    }

    // trustedForwarder
    event TrustedForwarderChanged(
        IFluidspeed indexed host,
        IFluidspeedToken indexed superToken,
        bool isKeySet,
        address forwarder,
        bool enabled);

    function isTrustedForwarder(
        IFluidspeed host,
        IFluidspeedToken superToken,
        address forwarder
    )
        external view
        returns (bool)
    {
        return getConfigAsUint256(
            host, superToken,
            FluidspeedGovernanceConfigs.getTrustedForwarderConfigKey(forwarder)) == 1;
    }

    function enableTrustedForwarder(
        IFluidspeed host,
        IFluidspeedToken superToken,
        address forwarder
    )
        public
    {
        _setConfig(
            host, superToken,
            FluidspeedGovernanceConfigs.getTrustedForwarderConfigKey(forwarder),
            1);
        emit TrustedForwarderChanged(host, superToken, true, forwarder, true);
    }

    function disableTrustedForwarder(
        IFluidspeed host,
        IFluidspeedToken superToken,
        address forwarder
    )
        external
    {
        _clearConfig(
            host, superToken,
            FluidspeedGovernanceConfigs.getTrustedForwarderConfigKey(forwarder));
        emit TrustedForwarderChanged(host, superToken, true, forwarder, false);
    }

    // Fluidspeed registrationKey
    event AppRegistrationKeyChanged(
        IFluidspeed indexed host,
        address indexed deployer,
        string appRegistrationKey,
        uint256 expirationTs
    );

    function verifyAppRegistrationKey(
        IFluidspeed host,
        address deployer,
        string memory registrationKey
    )
        external view
        returns(bool validNow, uint256 expirationTs)
    {
        bytes32 configKey = FluidspeedGovernanceConfigs.getAppRegistrationConfigKey(
            deployer,
            registrationKey
        );
        uint256 expirationTS = getConfigAsUint256(host, IFluidspeedToken(address(0)), configKey);
        return (
            // solhint-disable-next-line not-rely-on-time
            expirationTS >= block.timestamp,
            expirationTS
        );
    }

    function setAppRegistrationKey(
        IFluidspeed host,
        address deployer,
        string memory registrationKey,
        uint256 expirationTs
    )
        external
    {
        bytes32 configKey = FluidspeedGovernanceConfigs.getAppRegistrationConfigKey(
            deployer,
            registrationKey
        );
        _setConfig(host, IFluidspeedToken(address(0)), configKey, expirationTs);
        emit AppRegistrationKeyChanged(host, deployer, registrationKey, expirationTs);
    }

    function clearAppRegistrationKey(
        IFluidspeed host,
        address deployer,
        string memory registrationKey
    )
        external
    {
        bytes32 configKey = FluidspeedGovernanceConfigs.getAppRegistrationConfigKey(
            deployer,
            registrationKey
        );
        _clearConfig(host, IFluidspeedToken(address(0)), configKey);
        emit AppRegistrationKeyChanged(host, deployer, registrationKey, 0);
    }

    // Fluidspeed App factory
    event AppFactoryAuthorizationChanged(
        IFluidspeed indexed host,
        address indexed factory,
        bool authorized
    );

    /**
     * @dev tells if the given factory is authorized to register apps
     */
    function isAuthorizedAppFactory(
        IFluidspeed host,
        address factory
    )
        external view
        returns (bool)
    {
        return getConfigAsUint256(
            host, IFluidspeedToken(address(0)),
            FluidspeedGovernanceConfigs.getAppFactoryConfigKey(factory)) == 1;
    }

    modifier onlyAuthorized(IFluidspeed host) {
        _requireAuthorised(host);
        _;
    }

    function _requireAuthorised(IFluidspeed host) internal view virtual;
}
