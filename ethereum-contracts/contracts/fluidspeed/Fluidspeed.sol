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
    
    function updateAgreementClass(ISuperAgreement agreementClassLogic) external onlyGovernance override {
        if (NON_UPGRADABLE_DEPLOYMENT) revert HOST_NON_UPGRADEABLE();
        bytes32 agreementType = agreementClassLogic.agreementType();
        uint idx = _agreementClassIndices[agreementType];
        if (idx == 0) {
            revert FluidspeedErrors.DOES_NOT_EXIST(FluidspeedErrors.HOST_AGREEMENT_IS_NOT_REGISTERED);
        }
        UUPSProxiable proxiable = UUPSProxiable(address(_agreementClasses[idx - 1]));
        proxiable.updateCode(address(agreementClassLogic));
        emit AgreementClassUpdated(agreementType, address(agreementClassLogic));
    }

    function isAgreementTypeListed(bytes32 agreementType)
        external view override
        returns (bool yes)
    {
        uint idx = _agreementClassIndices[agreementType];
        return idx != 0;
    }

    function isAgreementClassListed(ISuperAgreement agreementClass)
        public view override
        returns (bool yes)
    {
        bytes32 agreementType = agreementClass.agreementType();
        uint idx = _agreementClassIndices[agreementType];
        // it should also be the same agreement class proxy address
        return idx != 0 && _agreementClasses[idx - 1] == agreementClass;
    }

    function getAgreementClass(bytes32 agreementType)
        external view override
        returns(ISuperAgreement agreementClass)
    {
        uint idx = _agreementClassIndices[agreementType];
        if (idx == 0) {
            revert FluidspeedErrors.DOES_NOT_EXIST(FluidspeedErrors.HOST_AGREEMENT_IS_NOT_REGISTERED);
        }
        return ISuperAgreement(_agreementClasses[idx - 1]);
    }

    function mapAgreementClasses(uint256 bitmap)
        external view override
        returns (ISuperAgreement[] memory agreementClasses) {
        uint i;
        uint n;
        // create memory output using the counted size
        agreementClasses = new ISuperAgreement[](_agreementClasses.length);
        // add to the output
        n = 0;
        for (i = 0; i < _agreementClasses.length; ++i) {
            if ((bitmap & (1 << i)) > 0) {
                agreementClasses[n++] = _agreementClasses[i];
            }
        }
        // resize memory arrays
        assembly { mstore(agreementClasses, n) }
    }

    function addToAgreementClassesBitmap(uint256 bitmap, bytes32 agreementType)
        external view override
        returns (uint256 newBitmap)
    {
        uint idx = _agreementClassIndices[agreementType];
        if (idx == 0) {
            revert FluidspeedErrors.DOES_NOT_EXIST(FluidspeedErrors.HOST_AGREEMENT_IS_NOT_REGISTERED);
        }
        return bitmap | (1 << (idx - 1));
    }

    function removeFromAgreementClassesBitmap(uint256 bitmap, bytes32 agreementType)
        external view override
        returns (uint256 newBitmap)
    {
        uint idx = _agreementClassIndices[agreementType];
        if (idx == 0) {
            revert FluidspeedErrors.DOES_NOT_EXIST(FluidspeedErrors.HOST_AGREEMENT_IS_NOT_REGISTERED);
        }
        return bitmap & ~(1 << (idx - 1));
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Super Token Factory
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function getSuperTokenFactory()
        external view override
        returns (ISuperTokenFactory factory)
    {
        return _superTokenFactory;
    }

    function getSuperTokenFactoryLogic()
        external view override
        returns (address logic)
    {
        assert(address(_superTokenFactory) != address(0));
        if (NON_UPGRADABLE_DEPLOYMENT) return address(_superTokenFactory);
        else return UUPSProxiable(address(_superTokenFactory)).getCodeAddress();
    }

    function updateSuperTokenFactory(ISuperTokenFactory newFactory)
        external override
        onlyGovernance
    {
        if (address(_superTokenFactory) == address(0)) {
            if (!NON_UPGRADABLE_DEPLOYMENT) {
                // initialize the proxy
                UUPSProxy proxy = new UUPSProxy();
                proxy.initializeProxy(address(newFactory));
                _superTokenFactory = ISuperTokenFactory(address(proxy));
            } else {
                _superTokenFactory = newFactory;
            }
            _superTokenFactory.initialize();
        } else {
            if (NON_UPGRADABLE_DEPLOYMENT) revert HOST_NON_UPGRADEABLE();
            UUPSProxiable(address(_superTokenFactory)).updateCode(address(newFactory));
        }
        emit SuperTokenFactoryUpdated(_superTokenFactory);
    }

    function updateSuperTokenLogic(ISuperToken token)
        external override
        onlyGovernance
    {
        address code = address(_superTokenFactory.getSuperTokenLogic());
        // assuming it's uups proxiable
        UUPSProxiable(address(token)).updateCode(code);
        emit SuperTokenLogicUpdated(token, code);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // App Registry
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function registerApp(
        uint256 configWord
    )
        external override
    {
        // check if whitelisting required
        if (APP_WHITE_LISTING_ENABLED) {
            revert HOST_NO_APP_REGISTRATION_PERMISSIONS();
        }
        _registerApp(configWord, ISuperApp(msg.sender), true);
    }

    function registerAppWithKey(uint256 configWord, string calldata registrationKey)
        external override
    {
        if (APP_WHITE_LISTING_ENABLED) {
            bytes32 configKey = FluidspeedGovernanceConfigs.getAppRegistrationConfigKey(
                // solhint-disable-next-line avoid-tx-origin
                tx.origin,
                registrationKey
            );
            // check if the key is valid and not expired
            if (
                _gov.getConfigAsUint256(
                    this,
                    IFluidspeedToken(address(0)),
                    configKey
                // solhint-disable-next-line not-rely-on-time
                ) < block.timestamp) revert HOST_INVALID_OR_EXPIRED_SUPER_APP_REGISTRATION_KEY();
        }
        _registerApp(configWord, ISuperApp(msg.sender), true);
    }

    function registerAppByFactory(
        ISuperApp app,
        uint256 configWord
    )
        external override
    {
        // msg sender must be a contract
        {
            uint256 cs;
            // solhint-disable-next-line no-inline-assembly
            assembly { cs := extcodesize(caller()) }
            if (cs == 0) revert FluidspeedErrors.MUST_BE_CONTRACT(FluidspeedErrors.HOST_MUST_BE_CONTRACT);
        }

        if (APP_WHITE_LISTING_ENABLED) {
            // check if msg sender is authorized to register
            bytes32 configKey = FluidspeedGovernanceConfigs.getAppFactoryConfigKey(msg.sender);
            bool isAuthorizedAppFactory = _gov.getConfigAsUint256(
                this,
                IFluidspeedToken(address(0)),
                configKey) == 1;

            if (!isAuthorizedAppFactory) revert HOST_UNAUTHORIZED_SUPER_APP_FACTORY();
        }
        _registerApp(configWord, app, false);
    }

    function _registerApp(uint256 configWord, ISuperApp app, bool checkIfInAppConstructor) private
    {
        // solhint-disable-next-line avoid-tx-origin
        if (msg.sender == tx.origin) {
            revert FluidspeedErrors.APP_RULE(SuperAppDefinitions.APP_RULE_NO_REGISTRATION_FOR_EOA);
        }

        if (checkIfInAppConstructor) {
            uint256 cs;
            // solhint-disable-next-line no-inline-assembly
            assembly { cs := extcodesize(app) }
            if (cs != 0) {
                revert FluidspeedErrors.APP_RULE(SuperAppDefinitions.APP_RULE_REGISTRATION_ONLY_IN_CONSTRUCTOR);
            }
        }
        if (
            !SuperAppDefinitions.isConfigWordClean(configWord) ||
            SuperAppDefinitions.getAppCallbackLevel(configWord) == 0 ||
            (configWord & SuperAppDefinitions.APP_JAIL_BIT) != 0
            ) {
                revert HOST_INVALID_CONFIG_WORD();
            }
        if (_appManifests[ISuperApp(app)].configWord != 0) revert HOST_SUPER_APP_ALREADY_REGISTERED();
        _appManifests[ISuperApp(app)] = AppManifest(configWord);
        emit AppRegistered(app);
    }

    function isApp(ISuperApp app) public view override returns(bool) {
        return _appManifests[app].configWord > 0;
    }

    function getAppCallbackLevel(ISuperApp appAddr) public override view returns(uint8) {
        return SuperAppDefinitions.getAppCallbackLevel(_appManifests[appAddr].configWord);
    }

    function getAppManifest(
        ISuperApp app
    )
        external view override
        returns (
            bool isSuperApp,
            bool isJailed,
            uint256 noopMask
        )
    {
        AppManifest memory manifest = _appManifests[app];
        isSuperApp = (manifest.configWord > 0);
        if (isSuperApp) {
            isJailed = SuperAppDefinitions.isAppJailed(manifest.configWord);
            noopMask = manifest.configWord & SuperAppDefinitions.AGREEMENT_CALLBACK_NOOP_BITMASKS;
        }
    }

    function isAppJailed(
        ISuperApp app
    )
        external view override
        returns(bool)
    {
        return SuperAppDefinitions.isAppJailed(_appManifests[app].configWord);
    }

    function allowCompositeApp(
        ISuperApp targetApp
    )
        external override
    {
        ISuperApp sourceApp = ISuperApp(msg.sender);
        if (!isApp(sourceApp)) revert HOST_SENDER_IS_NOT_SUPER_APP();
        if (!isApp(targetApp)) revert HOST_RECEIVER_IS_NOT_SUPER_APP();
        if (getAppCallbackLevel(sourceApp) <= getAppCallbackLevel(targetApp)) {
            revert HOST_SOURCE_APP_NEEDS_HIGHER_APP_LEVEL();
        } 
        _compositeApps[sourceApp][targetApp] = true;
    }

    function isCompositeAppAllowed(
        ISuperApp app,
        ISuperApp targetApp
    )
        external view override
        returns (bool)
    {
        return _compositeApps[app][targetApp];
    }

    /**************************************************************************
     * Agreement Framework
     *************************************************************************/

    function callAppBeforeCallback(
        ISuperApp app,
        bytes calldata callData,
        bool isTermination,
        bytes calldata ctx
    )
        external override
        onlyAgreement
        assertValidCtx(ctx)
        returns(bytes memory cbdata)
    {
        (bool success, bytes memory returnedData) = _callCallback(app, true, isTermination, callData, ctx);
        if (success) {
            if (CallUtils.isValidAbiEncodedBytes(returnedData)) {
                cbdata = abi.decode(returnedData, (bytes));
            } else {
                if (!isTermination) {
                    revert FluidspeedErrors.APP_RULE(SuperAppDefinitions.APP_RULE_CTX_IS_MALFORMATED);
                } else {
                    _jailApp(app, SuperAppDefinitions.APP_RULE_CTX_IS_MALFORMATED);
                }
            }
        }
    }

    function callAppAfterCallback(
        ISuperApp app,
        bytes calldata callData,
        bool isTermination,
        bytes calldata ctx
    )
        external override
        onlyAgreement
        assertValidCtx(ctx)
        returns(bytes memory newCtx)
    {
        (bool success, bytes memory returnedData) = _callCallback(app, false, isTermination, callData, ctx);
        if (success) {
            // the non static callback should not return empty ctx
            if (CallUtils.isValidAbiEncodedBytes(returnedData)) {
                newCtx = abi.decode(returnedData, (bytes));
                if (!_isCtxValid(newCtx)) {
                    if (!isTermination) {
                        revert FluidspeedErrors.APP_RULE(SuperAppDefinitions.APP_RULE_CTX_IS_READONLY);
                    } else {
                        newCtx = ctx;
                        _jailApp(app, SuperAppDefinitions.APP_RULE_CTX_IS_READONLY);
                    }
                }
            } else {
                if (!isTermination) {
                    revert FluidspeedErrors.APP_RULE(SuperAppDefinitions.APP_RULE_CTX_IS_MALFORMATED);
                } else {
                    newCtx = ctx;
                    _jailApp(app, SuperAppDefinitions.APP_RULE_CTX_IS_MALFORMATED);
                }
            }
        } else {
            newCtx = ctx;
        }
    }

    function appCallbackPush(
        bytes calldata ctx,
        ISuperApp app,
        uint256 appCreditGranted,
        int256 appCreditUsed,
        IFluidspeedToken appCreditToken
    )
        external override
        onlyAgreement
        assertValidCtx(ctx)
        returns (bytes memory appCtx)
    {
        Context memory context = decodeCtx(ctx);
        // NOTE: we use 1 as a magic number here as we want to do this check once we are in a callback
        // we use 1 instead of MAX_APP_CALLBACK_LEVEL because 1 captures what we are trying to enforce
        if (isApp(ISuperApp(context.msgSender)) && context.appCallbackLevel >= 1) {
            if (!_compositeApps[ISuperApp(context.msgSender)][app]) {
                revert FluidspeedErrors.APP_RULE(SuperAppDefinitions.APP_RULE_COMPOSITE_APP_IS_NOT_WHITELISTED);
            }
        }
        context.appCallbackLevel++;
        context.callType = ContextDefinitions.CALL_INFO_CALL_TYPE_APP_CALLBACK;
        context.appCreditGranted = appCreditGranted;
        context.appCreditUsed = appCreditUsed;
        context.appAddress = address(app);
        context.appCreditToken = appCreditToken;
        appCtx = _updateContext(context);
    }

    function appCallbackPop(
        bytes calldata ctx,
        int256 appCreditUsedDelta
    )
        external override
        onlyAgreement
        returns (bytes memory newCtx)
    {
        Context memory context = decodeCtx(ctx);
        context.appCreditUsed += appCreditUsedDelta;
        newCtx = _updateContext(context);
    }

    function ctxUseCredit(
        bytes calldata ctx,
        int256 appCreditUsedMore
    )
        external override
        onlyAgreement
        assertValidCtx(ctx)
        returns (bytes memory newCtx)
    {
        Context memory context = decodeCtx(ctx);
        context.appCreditUsed += appCreditUsedMore;

        newCtx = _updateContext(context);
    }

    function jailApp(
        bytes calldata ctx,
        ISuperApp app,
        uint256 reason
    )
        external override
        onlyAgreement
        assertValidCtx(ctx)
        returns (bytes memory newCtx)
    {
        _jailApp(app, reason);
        return ctx;
    }

    /**************************************************************************
    * Contextless Call Proxies
    *************************************************************************/

    function _callAgreement(
        address msgSender,
        ISuperAgreement agreementClass,
        bytes memory callData,
        bytes memory userData
    )
        internal
        cleanCtx
        isAgreement(agreementClass)
        returns(bytes memory returnedData)
    {
        // beware of the endianness
        bytes4 agreementSelector = CallUtils.parseSelector(callData);

        //Build context data
        bytes memory ctx = _updateContext(Context({
            appCallbackLevel: 0,
            callType: ContextDefinitions.CALL_INFO_CALL_TYPE_AGREEMENT,
            timestamp: getNow(),
            msgSender: msgSender,
            agreementSelector: agreementSelector,
            userData: userData,
            appCreditGranted: 0,
            appCreditWantedDeprecated: 0,
            appCreditUsed: 0,
            appAddress: address(0),
            appCreditToken: IFluidspeedToken(address(0))
        }));
        bool success;
        (success, returnedData) = _callExternalWithReplacedCtx(address(agreementClass), callData, ctx);
        if (!success) {
            CallUtils.revertFromReturnedData(returnedData);
        }
        // clear the stamp
        _ctxStamp = 0;
    }

    function callAgreement(
        ISuperAgreement agreementClass,
        bytes memory callData,
        bytes memory userData
    )
        external override
        returns(bytes memory returnedData)
    {
        return _callAgreement(msg.sender, agreementClass, callData, userData);
    }

    function _callAppAction(
        address msgSender,
        ISuperApp app,
        bytes memory callData
    )
        internal
        cleanCtx
        isAppActive(app)
        isValidAppAction(callData)
        returns(bytes memory returnedData)
    {
        // Build context data
        bytes memory ctx = _updateContext(Context({
            appCallbackLevel: 0,
            callType: ContextDefinitions.CALL_INFO_CALL_TYPE_APP_ACTION,
            timestamp: getNow(),
            msgSender: msgSender,
            agreementSelector: 0,
            userData: "",
            appCreditGranted: 0,
            appCreditWantedDeprecated: 0,
            appCreditUsed: 0,
            appAddress: address(app),
            appCreditToken: IFluidspeedToken(address(0))
        }));
        bool success;
        (success, returnedData) = _callExternalWithReplacedCtx(address(app), callData, ctx);
        if (success) {
            ctx = abi.decode(returnedData, (bytes));
            if (!_isCtxValid(ctx)) revert FluidspeedErrors.APP_RULE(SuperAppDefinitions.APP_RULE_CTX_IS_READONLY);
        } else {
            CallUtils.revertFromReturnedData(returnedData);
        }
        // clear the stamp
        _ctxStamp = 0;
    }

}
