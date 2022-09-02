// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.16;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UUPSProxiable } from "../upgradability/UUPSProxiable.sol";
import { UUPSProxy } from "../upgradability/UUPSProxy.sol";

import {
    IFluidspeed,
    IFluidspeedGovernance,
    ISuperAgreement,
    ISuperApp,
    SuperAppDefinitions,
    ContextDefinitions,
    BatchOperation,
    FluidspeedGovernanceConfigs,
    FluidspeedErrors,
    IFluidspeedToken,
    ISuperToken,
    ISuperTokenFactory,
    IERC20
} from "../interfaces/fluidspeed/IFluidspeed.sol";

import { CallUtils } from "../libs/CallUtils.sol";
import { BaseRelayRecipient } from "../libs/BaseRelayRecipient.sol";

/**
 * @dev The Fluidspeed host implementation.
 *
 * NOTE:
 * - Please read IFluidspeed for implementation notes.
 * - For some deeper technical notes, please visit protocol-monorepo wiki area.
 *
 * @author Fluidspeed
 */
contract Fluidspeed is
    UUPSProxiable,
    IFluidspeed,
    BaseRelayRecipient
{

    using SafeCast for uint256;

    struct AppManifest {
        uint256 configWord;
    }

    // solhint-disable-next-line var-name-mixedcase
    bool immutable public NON_UPGRADABLE_DEPLOYMENT;

    // solhint-disable-next-line var-name-mixedcase
    bool immutable public APP_WHITE_LISTING_ENABLED;

    /**
     * @dev Maximum number of level of apps can be composed together
     *
     * NOTE:
     * - TODO Composite app feature is currently disabled. Hence app cannot
     *   will not be able to call other app.
     */
    // solhint-disable-next-line var-name-mixedcase
    uint constant internal MAX_APP_CALLBACK_LEVEL = 1;

    // solhint-disable-next-line var-name-mixedcase
    uint64 constant public CALLBACK_GAS_LIMIT = 3000000;

    /* WARNING: NEVER RE-ORDER VARIABLES! Always double-check that new
       variables are added APPEND-ONLY. Re-ordering variables can
       permanently BREAK the deployed proxy contract. */

    /// @dev Governance contract
    IFluidspeedGovernance internal _gov;

    /// @dev Agreement list indexed by agreement index minus one
    ISuperAgreement[] internal _agreementClasses;
    /// @dev Mapping between agreement type to agreement index (starting from 1)
    mapping (bytes32 => uint) internal _agreementClassIndices;

    /// @dev Super token
    ISuperTokenFactory internal _superTokenFactory;

    /// @dev App manifests
    mapping(ISuperApp => AppManifest) internal _appManifests;
    /// @dev Composite app white-listing: source app => (target app => isAllowed)
    mapping(ISuperApp => mapping(ISuperApp => bool)) internal _compositeApps;
    /// @dev Ctx stamp of the current transaction, it should always be cleared to
    ///      zero before transaction finishes
    bytes32 internal _ctxStamp;
    /// @dev if app whitelisting is enabled, this is to make sure the keys are used only once
    mapping(bytes32 => bool) internal _appKeysUsedDeprecated;

    constructor(bool nonUpgradable, bool appWhiteListingEnabled) {
        NON_UPGRADABLE_DEPLOYMENT = nonUpgradable;
        APP_WHITE_LISTING_ENABLED = appWhiteListingEnabled;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // UUPSProxiable
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function initialize(
        IFluidspeedGovernance gov
    )
        external
        initializer // OpenZeppelin Initializable
    {
        _gov = gov;
    }

    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("org.fluidspeed-finance.contracts.Fluidspeed.implementation");
    }

    function updateCode(address newAddress) external override onlyGovernance {
        if (NON_UPGRADABLE_DEPLOYMENT) revert HOST_NON_UPGRADEABLE();
        if (Fluidspeed(newAddress).NON_UPGRADABLE_DEPLOYMENT()) revert HOST_CANNOT_DOWNGRADE_TO_NON_UPGRADEABLE();
        _updateCodeAddress(newAddress);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Time
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function getNow() public view  returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Governance
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function getGovernance() external view override returns (IFluidspeedGovernance) {
        return _gov;
    }

    function replaceGovernance(IFluidspeedGovernance newGov) external override onlyGovernance {
        emit GovernanceReplaced(_gov, newGov);
        _gov = newGov;
    }

    /**************************************************************************
     * Agreement Whitelisting
     *************************************************************************/

    function registerAgreementClass(ISuperAgreement agreementClassLogic) external onlyGovernance override {
        bytes32 agreementType = agreementClassLogic.agreementType();
        if (_agreementClassIndices[agreementType] != 0) {
            revert FluidspeedErrors.ALREADY_EXISTS(FluidspeedErrors.HOST_AGREEMENT_ALREADY_REGISTERED);
        }
        if (_agreementClasses.length >= 256) revert HOST_MAX_256_AGREEMENTS();
        ISuperAgreement agreementClass;
        if (!NON_UPGRADABLE_DEPLOYMENT) {
            // initialize the proxy
            UUPSProxy proxy = new UUPSProxy();
            proxy.initializeProxy(address(agreementClassLogic));
            agreementClass = ISuperAgreement(address(proxy));
        } else {
            agreementClass = ISuperAgreement(address(agreementClassLogic));
        }
        // register the agreement proxy
        _agreementClasses.push((agreementClass));
        _agreementClassIndices[agreementType] = _agreementClasses.length;
        emit AgreementClassRegistered(agreementType, address(agreementClassLogic));
    }

    

    modifier requireValidCtx(bytes memory ctx) {
        if (!_isCtxValid(ctx)) revert FluidspeedErrors.APP_RULE(SuperAppDefinitions.APP_RULE_CTX_IS_READONLY);
        _;
    }

    modifier assertValidCtx(bytes memory ctx) {
        assert(_isCtxValid(ctx));
        _;
    }

    modifier cleanCtx() {
        if (_ctxStamp != 0) revert FluidspeedErrors.APP_RULE(SuperAppDefinitions.APP_RULE_CTX_IS_NOT_CLEAN);
        _;
    }

    modifier isAgreement(ISuperAgreement agreementClass) {
        if (!isAgreementClassListed(agreementClass)) {
            revert FluidspeedErrors.ONLY_LISTED_AGREEMENT(FluidspeedErrors.HOST_ONLY_LISTED_AGREEMENT);
        }
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != address(_gov)) revert HOST_ONLY_GOVERNANCE();
        _;
    }

    modifier onlyAgreement() {
        if (!isAgreementClassListed(ISuperAgreement(msg.sender))) {
            revert FluidspeedErrors.ONLY_LISTED_AGREEMENT(FluidspeedErrors.HOST_ONLY_LISTED_AGREEMENT);
        }
        _;
    }

    modifier isAppActive(ISuperApp app) {
        uint256 configWord = _appManifests[app].configWord;
        if (configWord == 0) revert HOST_NOT_A_SUPER_APP();
        if (SuperAppDefinitions.isAppJailed(configWord)) revert HOST_SUPER_APP_IS_JAILED();
        _;
    }

    modifier isValidAppAction(bytes memory callData) {
        bytes4 actionSelector = CallUtils.parseSelector(callData);
        if (actionSelector == ISuperApp.beforeAgreementCreated.selector ||
            actionSelector == ISuperApp.afterAgreementCreated.selector ||
            actionSelector == ISuperApp.beforeAgreementUpdated.selector ||
            actionSelector == ISuperApp.afterAgreementUpdated.selector ||
            actionSelector == ISuperApp.beforeAgreementTerminated.selector ||
            actionSelector == ISuperApp.afterAgreementTerminated.selector) {
            revert HOST_AGREEMENT_CALLBACK_IS_NOT_ACTION();
        }
        _;
    }
}
